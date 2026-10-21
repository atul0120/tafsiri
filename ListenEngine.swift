import AVFoundation
import SwiftUI

/// The hands-free loop: listen → hear a pause → translate → speak → keep listening.
/// Their language (e.g. Kiswahili) becomes yours (e.g. English); your replies go back the other way.
@MainActor
final class ListenEngine: ObservableObject {
    enum ModelState: Equatable { case notLoaded, loading, ready, failed(String) }

    @Published var lines: [Line] = []
    @Published var isListening = false
    @Published var hearingSpeech = false
    @Published var isTranslating = false
    @Published var level: Float = -80
    @Published var status = "Tap Start. Tafsiri keeps listening and translates what it hears."
    @Published var modelState: ModelState = .notLoaded
    /// When true, the next thing heard is your reply.
    @Published var replyArmed = false
    @Published var headphonesConnected = Speaker.headphonesConnected

    private let recorder = UtteranceRecorder()
    private let interpreter = Interpreter()
    private let speaker = Speaker()
    private var pipeline: Task<Void, Never> = Task {}
    private var pending = 0

    init() {
        Prefs.register()
        recorder.onLevel = { [weak self] db in Task { @MainActor in self?.level = db } }
        recorder.onSpeaking = { [weak self] on in Task { @MainActor in self?.hearingSpeech = on } }
        recorder.onUtterance = { [weak self] samples in Task { @MainActor in self?.enqueue(samples) } }
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.routeChanged() }
        }
    }

    // MARK: Model

    func loadModel() async {
        if case .loading = modelState { return }
        modelState = .loading
        status = "Preparing the speech model. The first time it downloads 600–950 MB and sets itself up for this iPhone, which can take 5–10 minutes. Keep the app open on Wi-Fi."
        do {
            try await interpreter.load(model: Prefs.effectiveModel)
            modelState = .ready
            status = isListening ? listeningText : "Ready. Tap Start."
        } catch {
            modelState = .failed(error.localizedDescription)
            status = "Couldn't load the speech model: \(error.localizedDescription)"
        }
    }

    // MARK: Start / stop

    func toggle() {
        if isListening { stop() } else { Task { await start() } }
    }

    func start() async {
        if modelState != .ready { await loadModel() }
        guard modelState == .ready else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            status = "Allow the microphone in iPhone Settings → Tafsiri."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            // The phone's own mic listens; sound goes to headphones (A2DP) or the loudspeaker.
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
            try session.setActive(true)
            recorder.pauseSeconds = Prefs.pauseSeconds
            try recorder.start()
            isListening = true
            headphonesConnected = Speaker.headphonesConnected
            UIApplication.shared.isIdleTimerDisabled = true
            status = listeningText
        } catch {
            status = "Couldn't start the microphone: \(error.localizedDescription)"
        }
    }

    func stop() {
        recorder.stop()
        speaker.stop()
        isListening = false
        hearingSpeech = false
        replyArmed = false
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        status = "Stopped. Tap Start to listen again."
    }

    func clear() { lines.removeAll() }

    func replay(_ line: Line) {
        Task {
            switch line.kind {
            case .heard: await sayTranslation(line.mine, language: line.myLang, force: true)
            case .reply: if let t = line.theirs { await sayReply(t, language: line.theirLang) }
            }
        }
    }

    // MARK: Replying

    /// Tap Reply, then speak in your language. The next pause sends it.
    func armReply() async {
        guard Prefs.canReply else {
            status = "Add your Microsoft key, or choose the free MyMemory translator in Settings."
            return
        }
        if !isListening { await start() }
        guard isListening else { return }
        replyArmed.toggle()
        status = replyArmed ? "Speak your reply in \(Prefs.targetName) now…" : listeningText
    }

    /// A reply you typed instead of spoke.
    func reply(typed text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let previous = pipeline
        pending += 1
        pipeline = Task { [weak self] in
            await previous.value
            guard let self else { return }
            await self.sendReply(t)
            self.pending -= 1
            self.isTranslating = self.pending > 0
        }
    }

    private func sendReply(_ text: String) async {
        let from = Prefs.target, to = Prefs.source
        isTranslating = true
        status = "Translating your reply…"
        do {
            let translated = try await ReplyService.translate(text, from: from, to: to)
            lines.insert(Line(kind: .reply, mine: text, theirs: translated, myLang: from, theirLang: to), at: 0)
            trim()
            await sayReply(translated, language: to)
            status = isListening ? listeningText : "Ready."
        } catch {
            status = error.localizedDescription
        }
    }

    // MARK: Pipeline

    private func enqueue(_ samples: [Float]) {
        let isReply = replyArmed
        if isReply { replyArmed = false }
        // Never let a backlog build up: if two sentences are already waiting, skip this one.
        if !isReply && pending >= 2 {
            status = "Still working on the last sentence, skipped one."
            return
        }
        pending += 1
        let previous = pipeline
        pipeline = Task { [weak self] in
            await previous.value
            await self?.handle(samples, isReply: isReply)
        }
    }

    private func handle(_ samples: [Float], isReply: Bool) async {
        isTranslating = true
        defer { pending -= 1; isTranslating = pending > 0 }
        let source = Prefs.source, target = Prefs.target
        do {
            if isReply {
                let said = try await interpreter.transcribe(samples, language: target)
                if said.isEmpty { status = "Didn't catch that. Tap Reply and try again."; return }
                await sendReply(said)
                return
            }

            if Prefs.useOffline {
                guard let heard = try await interpreter.translateOffline(samples, source: source,
                                                                         forceSource: Prefs.assumeSource) else {
                    status = listeningText
                    return
                }
                if heard.language == target { await heardMine(heard.text); return }
                await show(translation: heard.text, original: nil)
                return
            }

            guard let heard = try await interpreter.listen(samples, source: source, target: target,
                                                           forceSource: Prefs.assumeSource) else {
                status = listeningText
                return
            }
            if heard.language == target { await heardMine(heard.text); return }
            guard Prefs.canReply else {
                status = "No translation yet: choose MyMemory (free) in Settings → Translate with, or add your Microsoft key."
                return
            }
            status = "Translating…"
            let translated = try await ReplyService.translate(heard.text, from: source, to: target)
            await show(translation: translated, original: heard.text)
        } catch {
            status = "Translation error: \(error.localizedDescription)"
        }
    }

    /// Someone (probably you) spoke your own language.
    private func heardMine(_ text: String) async {
        if Prefs.autoReply && Prefs.canReply { await sendReply(text) }
        else { status = "Heard \(Prefs.targetName), skipped." }
    }

    private func show(translation: String, original: String?) async {
        lines.insert(Line(kind: .heard, mine: translation,
                          theirs: Prefs.showOriginal ? original : nil,
                          myLang: Prefs.target, theirLang: Prefs.source), at: 0)
        trim()
        await sayTranslation(translation, language: Prefs.target, force: false)
        if !status.hasPrefix("Connect") { status = listeningText }
    }

    private func trim() { if lines.count > 200 { lines.removeLast() } }

    // MARK: Speaking

    /// Speaks a translation for you, following Settings → "Speak translations".
    /// `force` (tapping "Hear again") plays it even when no headphones are connected.
    private func sayTranslation(_ text: String, language: String, force: Bool) async {
        if !force {
            guard Prefs.speakAloud else { return }
            switch Prefs.speakWhere {
            case .off:
                return
            case .headphones:
                guard Speaker.headphonesConnected else {
                    status = "Connect headphones to hear translations. Showing text only."
                    return
                }
            case .anywhere:
                break
            }
        }
        // On the loudspeaker the mic pauses so it doesn't hear itself; with headphones it keeps listening.
        let mute = Speaker.usingPhoneSpeaker
        if mute { recorder.isPaused = true }
        let spoke = await speaker.speak(text, language: language)
        if !spoke { status = "This iPhone has no \(Langs.name(language)) voice. Add one in iPhone Settings → Accessibility → Spoken Content → Voices." }
        if mute { await resumeMic() }
    }

    /// Speaks your reply in their language, following Settings → "Speak my replies on".
    private func sayReply(_ text: String, language: String) async {
        let session = AVAudioSession.sharedInstance()
        let forceSpeaker = Prefs.replyWhere == .speaker
        if forceSpeaker { try? session.overrideOutputAudioPort(.speaker) }
        recorder.isPaused = true
        let audio = try? await ReplyService.voiceAudio(text, language: language)
        let spoke = await speaker.speak(text, language: language, audio: audio)
        if !spoke {
            status = "Show them the screen: this iPhone has no \(Langs.name(language)) voice."
        }
        if forceSpeaker { try? session.overrideOutputAudioPort(.none) }
        await resumeMic()
    }

    private func resumeMic() async {
        try? await Task.sleep(for: .milliseconds(250))
        recorder.isPaused = false
    }

    private func routeChanged() {
        headphonesConnected = Speaker.headphonesConnected
        if isListening && !isTranslating { status = listeningText }
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        // A phone call or Siri takes the mic; resume afterwards.
        if type == .ended, isListening, !recorder.isRunning {
            try? AVAudioSession.sharedInstance().setActive(true)
            try? recorder.start()
            status = listeningText
        }
    }

    var listeningText: String {
        var t = "Listening for \(Prefs.sourceName) → \(Prefs.targetName)"
        if Prefs.autoReply && Prefs.canReply { t += ", auto-reply on" }
        if Prefs.speakAloud && Prefs.speakWhere == .headphones && !Speaker.headphonesConnected {
            t += " (text only until headphones connect)"
        }
        return t + "…"
    }
}
