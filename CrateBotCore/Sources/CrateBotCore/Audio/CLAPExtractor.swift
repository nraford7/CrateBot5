import Foundation
import CoreML
import Accelerate

/// Extracts 512-dimensional CLAP embeddings for music understanding.
/// CLAP (Contrastive Language-Audio Pretraining) embeddings capture
/// semantic/conceptual aspects of music that complement EffNet features.
public actor CLAPExtractor {

    public static let embeddingDimension = 512
    public static let melBins = 64
    public static let targetFrames = 1001  // ~10 seconds at default hop
    public static let targetSampleRate: Double = 48000

    // CLAP mel spectrogram parameters
    private static let fftSize = 2048
    private static let hopSize = 480  // ~10ms at 48kHz
    private static let fMin: Float = 0
    private static let fMax: Float = 24000  // Nyquist for 48kHz

    private let model: MLModel

    // FFT resources
    private let fftSetup: FFTSetup?
    private let log2n: vDSP_Length
    private let melFilterbank: [[Float]]

    public init() throws {
        // Load model from bundle
        // Try multiple locations for the CoreML model
        var modelURL: URL?

        // 1. Try compiled model from Bundle.module
        if let url = Bundle.module.url(forResource: "CLAPAudioEncoder", withExtension: "mlmodelc") {
            modelURL = url
        }
        // 2. Try uncompiled model from Bundle.module
        else if let url = Bundle.module.url(forResource: "CLAPAudioEncoder", withExtension: "mlpackage") {
            modelURL = url
        }
        // 3. Try compiled model from Bundle.main
        else if let url = Bundle.main.url(forResource: "CLAPAudioEncoder", withExtension: "mlmodelc") {
            modelURL = url
        }
        // 4. Try uncompiled model from Bundle.main
        else if let url = Bundle.main.url(forResource: "CLAPAudioEncoder", withExtension: "mlpackage") {
            modelURL = url
        }

        guard let url = modelURL else {
            throw CLAPError.modelNotFound
        }

        let compiledURL: URL
        if url.pathExtension == "mlmodelc" {
            compiledURL = url
        } else {
            compiledURL = try MLModel.compileModel(at: url)
        }

        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        self.model = try MLModel(contentsOf: compiledURL, configuration: config)

        // Initialize FFT for mel spectrogram generation
        log2n = vDSP_Length(log2(Double(Self.fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

        // Create mel filterbank for CLAP parameters
        melFilterbank = Self.createMelFilterbank(
            numMelBands: Self.melBins,
            fftSize: Self.fftSize,
            sampleRate: Float(Self.targetSampleRate),
            fMin: Self.fMin,
            fMax: Self.fMax
        )
    }

    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    /// Extract CLAP embeddings from audio buffer
    /// - Parameters:
    ///   - audioBuffer: Audio samples as Float array
    ///   - sampleRate: Sample rate of the input audio
    /// - Returns: 512-dimensional embedding vector
    public func extract(from audioBuffer: [Float], sampleRate: Double) throws -> [Float] {
        // Resample if needed
        let resampled: [Float]
        if abs(sampleRate - Self.targetSampleRate) > 1 {
            resampled = resample(audioBuffer, from: sampleRate, to: Self.targetSampleRate)
        } else {
            resampled = audioBuffer
        }

        // Generate mel spectrogram
        var melSpec = generateMelSpectrogram(from: resampled)

        // Pad or truncate to fixed size
        melSpec = normalizeToFixedSize(melSpec, targetFrames: Self.targetFrames)

        // Flatten to MLMultiArray format [1, 64, 1001]
        // melSpec is [melBins][frames], we need to flatten correctly
        let inputArray = try MLMultiArray(
            shape: [1, NSNumber(value: Self.melBins), NSNumber(value: Self.targetFrames)],
            dataType: .float32
        )

        for melIdx in 0..<Self.melBins {
            for frameIdx in 0..<Self.targetFrames {
                let index = melIdx * Self.targetFrames + frameIdx
                inputArray[index] = NSNumber(value: melSpec[melIdx][frameIdx])
            }
        }

        let input = try MLDictionaryFeatureProvider(dictionary: ["mel_spectrogram": inputArray])
        let output = try model.prediction(from: input)

        guard let embeddingArray = output.featureValue(for: "embedding")?.multiArrayValue else {
            throw CLAPError.predictionFailed
        }

        // Extract 512-dim embedding
        var embedding = [Float](repeating: 0, count: Self.embeddingDimension)
        for i in 0..<Self.embeddingDimension {
            embedding[i] = embeddingArray[i].floatValue
        }

        return embedding
    }

    // MARK: - Mel Spectrogram Generation

    /// Generate mel spectrogram with CLAP-specific parameters
    /// - Parameter samples: Audio samples at 48kHz
    /// - Returns: 2D array [melBins][frames]
    private func generateMelSpectrogram(from samples: [Float]) -> [[Float]] {
        let numFrames = max(1, (samples.count - Self.fftSize) / Self.hopSize + 1)

        var melSpectrogram = [[Float]](
            repeating: [Float](repeating: 0, count: numFrames),
            count: Self.melBins
        )

        for frameIdx in 0..<numFrames {
            let startIdx = frameIdx * Self.hopSize
            let endIdx = min(startIdx + Self.fftSize, samples.count)
            var frame = Array(samples[startIdx..<endIdx])

            // Pad if needed
            if frame.count < Self.fftSize {
                frame.append(contentsOf: [Float](repeating: 0, count: Self.fftSize - frame.count))
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

    private func computePowerSpectrum(frame: [Float]) -> [Float] {
        guard let setup = fftSetup else {
            return [Float](repeating: 0, count: Self.fftSize / 2 + 1)
        }

        var windowed = [Float](repeating: 0, count: Self.fftSize)

        // Apply Hann window
        var window = [Float](repeating: 0, count: Self.fftSize)
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(Self.fftSize))

        // Prepare for FFT
        var real = [Float](repeating: 0, count: Self.fftSize)
        var imag = [Float](repeating: 0, count: Self.fftSize)
        for i in 0..<Self.fftSize {
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
        var powerSpectrum = [Float](repeating: 0, count: Self.fftSize / 2 + 1)
        for i in 0..<(Self.fftSize / 2 + 1) {
            powerSpectrum[i] = real[i] * real[i] + imag[i] * imag[i]
        }

        return powerSpectrum
    }

    private func applyMelFilterbank(powerSpectrum: [Float]) -> [Float] {
        var melEnergies = [Float](repeating: 0, count: Self.melBins)

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

    // MARK: - Size Normalization

    private func normalizeToFixedSize(_ melSpec: [[Float]], targetFrames: Int) -> [[Float]] {
        let currentFrames = melSpec.first?.count ?? 0

        if currentFrames == targetFrames {
            return melSpec
        } else if currentFrames > targetFrames {
            // Truncate from center
            let start = (currentFrames - targetFrames) / 2
            return melSpec.map { Array($0[start..<(start + targetFrames)]) }
        } else {
            // Pad with zeros symmetrically
            let padLeft = (targetFrames - currentFrames) / 2
            let padRight = targetFrames - currentFrames - padLeft
            return melSpec.map { row in
                [Float](repeating: 0, count: padLeft) + row + [Float](repeating: 0, count: padRight)
            }
        }
    }

    // MARK: - Resampling

    private func resample(_ buffer: [Float], from sourceSR: Double, to targetSR: Double) -> [Float] {
        let ratio = targetSR / sourceSR
        let outputLength = Int(Double(buffer.count) * ratio)
        var output = [Float](repeating: 0, count: outputLength)

        var sourceIndex: Double = 0
        for i in 0..<outputLength {
            let idx = Int(sourceIndex)
            if idx < buffer.count - 1 {
                let frac = Float(sourceIndex - Double(idx))
                output[i] = buffer[idx] * (1 - frac) + buffer[idx + 1] * frac
            } else if idx < buffer.count {
                output[i] = buffer[idx]
            }
            sourceIndex += 1.0 / ratio
        }

        return output
    }

    // MARK: - Error Types

    public enum CLAPError: Error, LocalizedError {
        case modelNotFound
        case predictionFailed

        public var errorDescription: String? {
            switch self {
            case .modelNotFound:
                return "CLAP model not found in bundle"
            case .predictionFailed:
                return "CLAP prediction failed"
            }
        }
    }
}
