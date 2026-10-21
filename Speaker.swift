import AVFoundation

/// Speaks text with the iPhone's voices, or plays ready-made audio (the Microsoft Kenyan voice).
@MainActor
final class Speaker: NSObject {
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var done: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synth.delegate = self
    }

    /// Speaks `text` in `language` ("en", "sw", …). Returns false if there was no voice for it.
    func speak(_ text: String, language: String, audio: Data? = nil) async -> Bool {
        stop()
        if let audio, let p = try? AVAudioPlayer(data: audio) {
            player = p
            p.delegate = self
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                done = c
                if !p.play() { finish() }
            }
            return true
        }
        guard let voice = Self.voice(for: language) else { return false }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            done = c
            let u = AVSpeechUtterance(string: text)
            u.voice = voice
            u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
            synth.speak(u)
        }
        return true
    }

    static func voice(for language: String) -> AVSpeechSynthesisVoice? {
        let preferred = ["en": "en-GB", "sw": "sw-KE", "hi": "hi-IN", "fr": "fr-FR", "ar": "ar-001",
                         "pt": "pt-PT", "es": "es-ES", "zh": "zh-CN"][language]
        if let p = preferred, let v = AVSpeechSynthesisVoice(language: p) { return v }
        return AVSpeechSynthesisVoice.speechVoices().first { $0.language.lowercased().hasPrefix(language) }
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player?.stop()
        finish()
    }

    private func finish() {
        done?.resume()
        done = nil
    }

    /// True when sound comes out of the phone itself (so the mic would hear it).
    static var usingPhoneSpeaker: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains {
            $0.portType == .builtInSpeaker || $0.portType == .builtInReceiver
        }
    }

    /// True when wired, USB or Bluetooth headphones/earbuds (e.g. AirPods) are connected.
    static var headphonesConnected: Bool {
        let kinds: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothHFP,
                                               .bluetoothLE, .usbAudio]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { kinds.contains($0.portType) }
    }
}

extension Speaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }
}

extension Speaker: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finish() }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ p: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.finish() }
    }
}
