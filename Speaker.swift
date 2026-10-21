import AVFoundation

/// Plays translations: English with the iPhone's own voice, Kiswahili replies with the
/// Microsoft Kenyan voice (or an iPhone Kiswahili voice if one is installed).
@MainActor
final class Speaker: NSObject {
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var done: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synth.delegate = self
    }

    func speakEnglish(_ text: String) async {
        await speakBuiltIn(text, voice: AVSpeechSynthesisVoice(language: "en-GB") ?? AVSpeechSynthesisVoice(language: "en-US"))
    }

    /// Speaks Kiswahili. Returns false if there was no way to voice it.
    func speakSwahili(_ text: String, audio: Data?) async -> Bool {
        if let audio, let p = try? AVAudioPlayer(data: audio) {
            stop()
            player = p
            p.delegate = self
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                done = c
                if !p.play() { finish() }
            }
            return true
        }
        if let v = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.lowercased().hasPrefix("sw") }) {
            await speakBuiltIn(text, voice: v)
            return true
        }
        return false
    }

    private func speakBuiltIn(_ text: String, voice: AVSpeechSynthesisVoice?) async {
        stop()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            done = c
            let u = AVSpeechUtterance(string: text)
            u.voice = voice
            u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
            synth.speak(u)
        }
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
