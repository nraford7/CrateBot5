import AVFoundation
import Accelerate

/// Extracts spectral features using vDSP (MFCCs, spectral centroid, etc.)
public final class SpectralExtractor: FeatureExtractor, @unchecked Sendable {
    public let id = "spectral"
    public let version = "v1"

    // Feature dimensions
    private let numMFCCs = 13
    private let numChroma = 12
    private let numSpectralStats = 7  // centroid, bandwidth, rolloff, flux, flatness, crest, entropy

    public var featureCount: Int {
        numMFCCs + numChroma + numSpectralStats  // 32 features
    }

    // FFT setup
    private let fftSize = 2048
    private let hopSize = 512
    private let fftSetup: vDSP_DFT_Setup?

    public init() {
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)
    }

    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }

    public func extract(from buffer: AVAudioPCMBuffer) async throws -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            throw FeatureExtractionError.invalidBuffer
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength >= fftSize else {
            throw FeatureExtractionError.insufficientData(required: fftSize, got: frameLength)
        }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        // Compute spectrogram
        let spectrogram = computeSpectrogram(samples: samples)

        // Extract features from spectrogram
        var features: [Float] = []

        // MFCCs (mean across frames)
        let mfccs = computeMFCCs(spectrogram: spectrogram)
        features.append(contentsOf: mfccs)

        // Chroma features (mean across frames)
        let chroma = computeChroma(spectrogram: spectrogram)
        features.append(contentsOf: chroma)

        // Spectral statistics
        let stats = computeSpectralStats(spectrogram: spectrogram)
        features.append(contentsOf: stats)

        return features
    }

    // MARK: - Private Methods

    private func computeSpectrogram(samples: [Float]) -> [[Float]] {
        var spectrogram: [[Float]] = []
        let numFrames = (samples.count - fftSize) / hopSize + 1

        for frameIdx in 0..<numFrames {
            let startIdx = frameIdx * hopSize
            let frame = Array(samples[startIdx..<(startIdx + fftSize)])
            let spectrum = computeFFT(frame: frame)
            spectrogram.append(spectrum)
        }

        return spectrogram
    }

    private func computeFFT(frame: [Float]) -> [Float] {
        var windowed = frame
        // Apply Hann window
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        // Compute FFT
        var realIn = windowed
        var imagIn = [Float](repeating: 0, count: fftSize)
        var realOut = [Float](repeating: 0, count: fftSize)
        var imagOut = [Float](repeating: 0, count: fftSize)

        guard let setup = fftSetup else {
            // Return zeros if FFT setup failed (initialization issue)
            return [Float](repeating: 0, count: fftSize / 2)
        }
        vDSP_DFT_Execute(setup, &realIn, &imagIn, &realOut, &imagOut)

        // Compute magnitude spectrum
        var magnitude = [Float](repeating: 0, count: fftSize / 2)
        realOut.withUnsafeMutableBufferPointer { realPtr in
            imagOut.withUnsafeMutableBufferPointer { imagPtr in
                var complex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvabs(&complex, 1, &magnitude, 1, vDSP_Length(fftSize / 2))
            }
        }

        return magnitude
    }

    // TODO: Implement proper mel-filterbank and DCT for true MFCCs
    // Current implementation uses linear log-band energies as a simplified approximation
    private func computeMFCCs(spectrogram: [[Float]]) -> [Float] {
        // Simplified MFCC computation (mean magnitude in mel-spaced bands)
        guard !spectrogram.isEmpty else { return [Float](repeating: 0, count: numMFCCs) }

        let binCount = spectrogram[0].count
        var mfccSum = [Float](repeating: 0, count: numMFCCs)

        for spectrum in spectrogram {
            for i in 0..<numMFCCs {
                let startBin = Int(Float(i) / Float(numMFCCs) * Float(binCount))
                let endBin = Int(Float(i + 1) / Float(numMFCCs) * Float(binCount))
                let bandEnergy = spectrum[startBin..<endBin].reduce(0, +) / Float(endBin - startBin)
                mfccSum[i] += log(bandEnergy + 1e-10)
            }
        }

        return mfccSum.map { $0 / Float(spectrogram.count) }
    }

    // TODO: Map bins to pitch classes based on actual frequency
    // Current implementation uses bin index modulo, not true pitch mapping
    private func computeChroma(spectrogram: [[Float]]) -> [Float] {
        // Simplified chroma: fold spectrum into 12 pitch classes
        guard !spectrogram.isEmpty else { return [Float](repeating: 0, count: numChroma) }

        var chromaSum = [Float](repeating: 0, count: numChroma)

        for spectrum in spectrogram {
            for (binIdx, magnitude) in spectrum.enumerated() {
                let pitchClass = binIdx % numChroma
                chromaSum[pitchClass] += magnitude
            }
        }

        let total = chromaSum.reduce(0, +) + 1e-10
        return chromaSum.map { $0 / total }
    }

    private func computeSpectralStats(spectrogram: [[Float]]) -> [Float] {
        guard !spectrogram.isEmpty else { return [Float](repeating: 0, count: numSpectralStats) }

        var centroidSum: Float = 0
        var bandwidthSum: Float = 0
        var rolloffSum: Float = 0
        var fluxSum: Float = 0
        var flatnessSum: Float = 0
        var crestSum: Float = 0
        var entropySum: Float = 0

        var prevSpectrum: [Float]?

        for spectrum in spectrogram {
            let total = spectrum.reduce(0, +) + 1e-10

            // Centroid
            var weightedSum: Float = 0
            for (i, mag) in spectrum.enumerated() {
                weightedSum += Float(i) * mag
            }
            centroidSum += weightedSum / total

            // Bandwidth (spread around centroid)
            let centroid = weightedSum / total
            var variance: Float = 0
            for (i, mag) in spectrum.enumerated() {
                variance += mag * pow(Float(i) - centroid, 2)
            }
            bandwidthSum += sqrt(variance / total)

            // Rolloff (frequency below which 85% of energy)
            let threshold = total * 0.85
            var cumSum: Float = 0
            var rolloffBin = 0
            for (i, mag) in spectrum.enumerated() {
                cumSum += mag
                if cumSum >= threshold {
                    rolloffBin = i
                    break
                }
            }
            rolloffSum += Float(rolloffBin)

            // Spectral flux (change from previous frame)
            if let prev = prevSpectrum {
                var flux: Float = 0
                for i in 0..<spectrum.count {
                    flux += pow(spectrum[i] - prev[i], 2)
                }
                fluxSum += sqrt(flux)
            }
            prevSpectrum = spectrum

            // Flatness (geometric mean / arithmetic mean)
            let arithmeticMean = total / Float(spectrum.count)
            var logSum: Float = 0
            for mag in spectrum {
                logSum += log(mag + 1e-10)
            }
            let geometricMean = exp(logSum / Float(spectrum.count))
            flatnessSum += geometricMean / (arithmeticMean + 1e-10)

            // Crest factor (peak / RMS)
            let peak = spectrum.max() ?? 0
            var sumSquares: Float = 0
            vDSP_svesq(spectrum, 1, &sumSquares, vDSP_Length(spectrum.count))
            let rms = sqrt(sumSquares / Float(spectrum.count))
            crestSum += peak / (rms + 1e-10)

            // Entropy
            var entropy: Float = 0
            for mag in spectrum {
                let p = mag / total
                if p > 1e-10 {
                    entropy -= p * log(p)
                }
            }
            entropySum += entropy
        }

        let count = Float(spectrogram.count)
        return [
            centroidSum / count,
            bandwidthSum / count,
            rolloffSum / count,
            fluxSum / count,
            flatnessSum / count,
            crestSum / count,
            entropySum / count
        ]
    }
}
