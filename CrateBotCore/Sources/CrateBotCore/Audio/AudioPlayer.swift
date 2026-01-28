import AVFoundation
import Observation

@Observable
public class AudioPlayer {
    private var player: AVAudioPlayer?
    private var displayLink: Timer?

    public private(set) var isPlaying = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    public init() {}

    public func play(url: URL) throws {
        stop()

        player = try AVAudioPlayer(contentsOf: url)
        duration = player?.duration ?? 0
        player?.play()
        isPlaying = true
        startTimeUpdates()
    }

    public func pause() {
        player?.pause()
        isPlaying = false
        stopTimeUpdates()
    }

    public func resume() {
        player?.play()
        isPlaying = true
        startTimeUpdates()
    }

    public func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        stopTimeUpdates()
    }

    public func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    public func seek(toProgress progress: Double) {
        let time = progress * duration
        seek(to: time)
    }

    // MARK: - Time Updates

    private func startTimeUpdates() {
        stopTimeUpdates()
        displayLink = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateTime()
        }
    }

    private func stopTimeUpdates() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func updateTime() {
        guard let player = player else { return }
        currentTime = player.currentTime

        if !player.isPlaying && isPlaying {
            // Playback finished
            isPlaying = false
            stopTimeUpdates()
        }
    }

    deinit {
        stop()
    }
}
