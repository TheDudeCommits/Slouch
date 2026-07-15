import AVFoundation
import Foundation

@MainActor
final class SoundscapeEngine {
    enum Effect {
        case pickup
        case collision
        case boost
        case roll
        case complete
    }

    private let engine = AVAudioEngine()
    private let musicPlayer = AVAudioPlayerNode()
    private let effectPlayer = AVAudioPlayerNode()
    private let reverb = AVAudioUnitReverb()
    private var isConfigured = false
    private let sampleRate = 44_100.0

    func start(musicEnabled: Bool) {
        guard musicEnabled else { return }
        configureIfNeeded()
        guard !engine.isRunning else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            if !musicPlayer.isPlaying {
                musicPlayer.scheduleBuffer(makeAmbientLoop(), at: nil, options: .loops)
                musicPlayer.play()
            }
        } catch {
            // Gameplay remains fully functional when audio is unavailable.
        }
    }

    func stop() {
        musicPlayer.stop()
        effectPlayer.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func play(_ effect: Effect, enabled: Bool) {
        guard enabled else { return }
        configureIfNeeded()
        if !engine.isRunning {
            try? engine.start()
        }
        effectPlayer.scheduleBuffer(makeEffect(effect), completionHandler: nil)
        if !effectPlayer.isPlaying { effectPlayer.play() }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        engine.attach(musicPlayer)
        engine.attach(effectPlayer)
        engine.attach(reverb)
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = 38
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.connect(musicPlayer, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engine.connect(effectPlayer, to: engine.mainMixerNode, format: format)
        musicPlayer.volume = 0.34
        effectPlayer.volume = 0.5
        engine.prepare()
    }

    private func makeAmbientLoop() -> AVAudioPCMBuffer {
        let seconds = 12.0
        let frameCount = AVAudioFrameCount(sampleRate * seconds)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let roots = [55.0, 82.41, 110.0, 164.81]
        for channel in 0..<2 {
            guard let samples = buffer.floatChannelData?[channel] else { continue }
            for frame in 0..<Int(frameCount) {
                let t = Double(frame) / sampleRate
                let breath = 0.58 + 0.42 * sin(2 * .pi * t / seconds - .pi / 2)
                var value = 0.0
                for (index, frequency) in roots.enumerated() {
                    let detune = channel == 0 ? 1.0 : 1.0022
                    let phase = Double(index) * 0.73 + Double(channel) * 0.21
                    value += sin(2 * .pi * frequency * detune * t + phase) / Double(index + 2)
                }
                let shimmer = sin(2 * .pi * 659.25 * t + sin(t * 0.17)) * (0.018 + 0.014 * breath)
                samples[frame] = Float(value * 0.075 * breath + shimmer)
            }
        }
        return buffer
    }

    private func makeEffect(_ effect: Effect) -> AVAudioPCMBuffer {
        let duration: Double
        let startFrequency: Double
        let endFrequency: Double
        switch effect {
        case .pickup: (duration, startFrequency, endFrequency) = (0.34, 660, 990)
        case .collision: (duration, startFrequency, endFrequency) = (0.25, 110, 42)
        case .boost: (duration, startFrequency, endFrequency) = (0.46, 150, 420)
        case .roll: (duration, startFrequency, endFrequency) = (0.28, 420, 260)
        case .complete: (duration, startFrequency, endFrequency) = (0.9, 440, 880)
        }

        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        for channel in 0..<2 {
            guard let samples = buffer.floatChannelData?[channel] else { continue }
            var phase = 0.0
            for frame in 0..<Int(frameCount) {
                let progress = Double(frame) / Double(frameCount)
                let frequency = startFrequency + (endFrequency - startFrequency) * progress
                phase += 2 * .pi * frequency / sampleRate
                let envelope = sin(.pi * progress) * exp(-1.2 * progress)
                samples[frame] = Float(sin(phase + Double(channel) * 0.08) * envelope * 0.26)
            }
        }
        return buffer
    }
}
