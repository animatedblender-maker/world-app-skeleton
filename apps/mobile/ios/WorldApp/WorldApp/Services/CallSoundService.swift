import AVFoundation
import Foundation

@MainActor
final class CallSoundService {
    static let shared = CallSoundService()

    enum Pattern {
        case incomingRing
        case outgoingRing
        case tryingToReach
    }

    private var engine: AVAudioEngine?
    private var player = AVAudioPlayerNode()
    private var loopTask: Task<Void, Never>?
    private var activePattern: Pattern?

    private init() {}

    func start(_ pattern: Pattern) {
        guard activePattern != pattern else { return }
        stop()
        activePattern = pattern
        configureSession()
        loopTask = Task {
            while !Task.isCancelled {
                await playBurst(for: pattern)
                let pause = pauseDuration(for: pattern)
                try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        activePattern = nil
        player.stop()
        engine?.stop()
        engine?.reset()
        engine = nil
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? session.setActive(true)
    }

    private func pauseDuration(for pattern: Pattern) -> TimeInterval {
        switch pattern {
        case .incomingRing, .outgoingRing: 2.0
        case .tryingToReach: 2.8
        }
    }

    private func playBurst(for pattern: Pattern) async {
        switch pattern {
        case .incomingRing:
            // Matterya signature: bright rising triad
            await playTone(frequency: 392, duration: 0.11, volume: 0.36)
            try? await Task.sleep(nanoseconds: 55_000_000)
            await playTone(frequency: 523.25, duration: 0.11, volume: 0.38)
            try? await Task.sleep(nanoseconds: 55_000_000)
            await playTone(frequency: 659.25, duration: 0.24, volume: 0.4)
            try? await Task.sleep(nanoseconds: 90_000_000)
            await playTone(frequency: 440, duration: 0.1, volume: 0.3)
            try? await Task.sleep(nanoseconds: 50_000_000)
            await playTone(frequency: 659.25, duration: 0.22, volume: 0.34)
        case .outgoingRing:
            await playTone(frequency: 440, duration: 0.18, volume: 0.28)
            try? await Task.sleep(nanoseconds: 100_000_000)
            await playTone(frequency: 554.37, duration: 0.18, volume: 0.28)
            try? await Task.sleep(nanoseconds: 100_000_000)
            await playTone(frequency: 659.25, duration: 0.24, volume: 0.3)
        case .tryingToReach:
            await playTone(frequency: 294, duration: 0.18, volume: 0.22)
            try? await Task.sleep(nanoseconds: 90_000_000)
            await playTone(frequency: 330, duration: 0.16, volume: 0.18)
        }
    }

    private func playTone(frequency: Double, duration: TimeInterval, volume: Float = 0.34) async {
        guard let buffer = makeToneBuffer(frequency: frequency, duration: duration, volume: volume) else { return }

        let audioEngine = AVAudioEngine()
        let audioPlayer = AVAudioPlayerNode()
        audioEngine.attach(audioPlayer)
        audioEngine.connect(audioPlayer, to: audioEngine.mainMixerNode, format: buffer.format)

        engine = audioEngine
        player = audioPlayer

        do {
            try audioEngine.start()
            audioPlayer.play()
            await audioPlayer.scheduleBuffer(buffer, at: nil, options: [])
            audioPlayer.stop()
            audioEngine.stop()
        } catch {
            audioEngine.stop()
        }
    }

    private func makeToneBuffer(frequency: Double, duration: TimeInterval, volume: Float) -> AVAudioPCMBuffer? {
        let sampleRate = 44_100.0
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0]
        else { return nil }

        buffer.frameLength = frameCount
        let angular = 2.0 * Double.pi * frequency / sampleRate
        let attack = sampleRate * 0.015
        let release = sampleRate * 0.04
        let total = Double(frameCount)

        for frame in 0..<Int(frameCount) {
            let t = Double(frame)
            let attackEnv = min(1.0, t / attack)
            let releaseEnv = min(1.0, (total - t) / release)
            let envelope = Float(min(attackEnv, releaseEnv))
            channel[frame] = Float(sin(angular * t)) * envelope * volume
        }

        return buffer
    }
}