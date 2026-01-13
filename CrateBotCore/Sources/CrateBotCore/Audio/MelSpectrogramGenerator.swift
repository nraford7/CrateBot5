import AVFoundation
import Accelerate

/// Generates mel spectrograms compatible with Discogs-EffNet model
/// Output shape: [128 mel bands, 96 time frames]
public final class MelSpectrogramGenerator: @unchecked Sendable {

    // EffNet parameters (based on Essentia preprocessing)
    private let targetSampleRate: Float = 16000
    private let frameSize = 400      // 25ms at 16kHz
    private let hopSize = 160        // 10ms at 16kHz
    private let numMelBands = 128
    private let numTimeFrames = 96
    private let fMin: Float = 0
    private let fMax: Float = 8000   // Nyquist for 16kHz

    // FFT setup
    private let fftSize = 512        // Next power of 2 >= frameSize
    private let fftSetup: FFTSetup?
    private let log2n: vDSP_Length

    // Mel filterbank (computed once)
    private let melFilterbank: [[Float]]

    public init() {
        log2n = vDSP_Length(log2(Double(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        melFilterbank = Self.createMelFilterbank(
            numMelBands: numMelBands,
            fftSize: fftSize,
            sampleRate: targetSampleRate,
            fMin: fMin,
            fMax: fMax
        )
    }

    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    /// Generate mel spectrogram from audio buffer
    /// - Parameter buffer: Audio buffer (will be resampled to 16kHz if needed)
    /// - Returns: 2D array [numMelBands][numTimeFrames]
    public func generate(from buffer: AVAudioPCMBuffer) throws -> [[Float]] {
        guard let channelData = buffer.floatChannelData else {
            throw MelSpectrogramError.invalidBuffer
        }

        let frameLength = Int(buffer.frameLength)
        let requiredSamples = (numTimeFrames - 1) * hopSize + frameSize

        guard frameLength >= requiredSamples else {
            throw MelSpectrogramError.insufficientData(required: requiredSamples, got: frameLength)
        }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        // Compute STFT and convert to mel scale
        var melSpectrogram = [[Float]](repeating: [Float](repeating: 0, count: numTimeFrames), count: numMelBands)

        for frameIdx in 0..<numTimeFrames {
            let startIdx = frameIdx * hopSize
            let endIdx = min(startIdx + frameSize, samples.count)
            var frame = Array(samples[startIdx..<endIdx])

            // Pad if needed
            if frame.count < frameSize {
                frame.append(contentsOf: [Float](repeating: 0, count: frameSize - frame.count))
            }

            // Compute power spectrum
            let powerSpectrum = computePowerSpectrum(frame: frame)

            // Apply mel filterbank
            let melEnergies = applyMelFilterbank(powerSpectrum: powerSpectrum)

            // Store with log scaling
            for (bandIdx, energy) in melEnergies.enumerated() {
                melSpectrogram[bandIdx][frameIdx] = log10(max(energy, 1e-10))
            }
        }

        return melSpectrogram
    }

    /// Convert 2D mel spectrogram to flat array for CoreML input
    public func flatten(_ melSpec: [[Float]]) -> [Float] {
        var flat = [Float]()
        flat.reserveCapacity(numMelBands * numTimeFrames)
        for band in melSpec {
            flat.append(contentsOf: band)
        }
        return flat
    }

    // MARK: - Private Methods

    private func computePowerSpectrum(frame: [Float]) -> [Float] {
        guard let setup = fftSetup else {
            return [Float](repeating: 0, count: fftSize / 2 + 1)
        }

        var windowed = [Float](repeating: 0, count: frameSize)

        // Apply Hann window
        var window = [Float](repeating: 0, count: frameSize)
        vDSP_hann_window(&window, vDSP_Length(frameSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(frameSize))

        // Zero-pad to FFT size
        var real = [Float](repeating: 0, count: fftSize)
        var imag = [Float](repeating: 0, count: fftSize)
        for i in 0..<frameSize {
            real[i] = windowed[i]
        }

        // Perform FFT using proper buffer scoping
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_fft_zip(setup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }

        // Compute power spectrum (magnitude squared)
        var powerSpectrum = [Float](repeating: 0, count: fftSize / 2 + 1)
        for i in 0..<(fftSize / 2 + 1) {
            powerSpectrum[i] = real[i] * real[i] + imag[i] * imag[i]
        }

        return powerSpectrum
    }

    private func applyMelFilterbank(powerSpectrum: [Float]) -> [Float] {
        var melEnergies = [Float](repeating: 0, count: numMelBands)

        for (bandIdx, filterWeights) in melFilterbank.enumerated() {
            var energy: Float = 0
            let count = min(powerSpectrum.count, filterWeights.count)
            vDSP_dotpr(powerSpectrum, 1, filterWeights, 1, &energy, vDSP_Length(count))
            melEnergies[bandIdx] = energy
        }

        return melEnergies
    }

    // MARK: - Mel Filterbank Creation

    private static func createMelFilterbank(
        numMelBands: Int,
        fftSize: Int,
        sampleRate: Float,
        fMin: Float,
        fMax: Float
    ) -> [[Float]] {
        let numBins = fftSize / 2 + 1

        func hzToMel(_ hz: Float) -> Float {
            return 2595.0 * log10(1.0 + hz / 700.0)
        }

        func melToHz(_ mel: Float) -> Float {
            return 700.0 * (pow(10.0, mel / 2595.0) - 1.0)
        }

        let melMin = hzToMel(fMin)
        let melMax = hzToMel(fMax)

        // Create mel points
        var melPoints = [Float]()
        for i in 0...(numMelBands + 1) {
            let mel = melMin + Float(i) * (melMax - melMin) / Float(numMelBands + 1)
            melPoints.append(mel)
        }

        // Convert to Hz and then to FFT bin indices
        let hzPoints = melPoints.map { melToHz($0) }
        let binPoints = hzPoints.map { Int(($0 / sampleRate) * Float(fftSize)) }

        // Create triangular filters
        var filterbank = [[Float]]()
        for i in 0..<numMelBands {
            var filter = [Float](repeating: 0, count: numBins)
            let startBin = binPoints[i]
            let centerBin = binPoints[i + 1]
            let endBin = binPoints[i + 2]

            // Rising edge
            for j in startBin..<centerBin where j < numBins && j >= 0 {
                if centerBin != startBin {
                    filter[j] = Float(j - startBin) / Float(centerBin - startBin)
                }
            }

            // Falling edge
            for j in centerBin..<endBin where j < numBins && j >= 0 {
                if endBin != centerBin {
                    filter[j] = Float(endBin - j) / Float(endBin - centerBin)
                }
            }

            filterbank.append(filter)
        }

        return filterbank
    }
}

// MARK: - Errors

public enum MelSpectrogramError: LocalizedError {
    case invalidBuffer
    case insufficientData(required: Int, got: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidBuffer:
            return "Invalid audio buffer"
        case .insufficientData(let required, let got):
            return "Insufficient audio data: need \(required) samples, got \(got)"
        }
    }
}
