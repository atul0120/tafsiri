import AVFoundation
import SwiftUI

/// The hands-free loop: listen → hear a pause → translate → speak → keep listening.
/// Kiswahili it hears becomes English for you; your English replies become spoken Kiswahili.
@MainActor
final class ListenEngine: ObservableObject {
    enum ModelState: Equatable { case notLoaded, loading, ready, failed(String) }

    @Published var lines: [Line] = []
    @Published var isListening = false
    @Published var hearingSpeech = false
    @Published var isTranslating = false
    @Published var level: Float = -80
    @Published var status = "Tap Start. Tafsiri will translate any Kiswahili it hears."
    @Published var modelState: ModelState = .notLoaded
    /// When true, the next thing heard is your English reply.
    @Published var replyArmed = false

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
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                               object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
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
            // Phone mic listens; translations play in AirPods (A2DP) or the loudspeaker.
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
            try session.setActive(true)
            recorder.pauseSeconds = Prefs.pauseSeconds
            try recorder.start()
            isListening = true
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
            case .heard: await sayEnglish(line.english)
            case .reply: if let sw = line.swahili { await saySwahili(sw) }
            }
        }
    }

    // MARK: Replying in Kiswahili

    /// Tap Reply, then speak English. The next pause sends it.
    func armReply() async {
        guard Prefs.canReply else {
            status = "Add your Microsoft key, or choose the free MyMemory translator in Settings."
            return
        }
        if !isListening { await start() }
        guard isListening else { return }
        replyArmed.toggle()
        status = replyArmed ? "Speak your reply in English now…" : listeningText
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

    private func sendReply(_ english: String) async {
        isTranslating = true
        status = "Translating your reply…"
        do {
            let swahili = try await ReplyService.translateToSwahili(english)
            lines.insert(Line(kind: .reply, english: english, swahili: swahili), at: 0)
            trim()
            await saySwahili(swahili)
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
        do {
            if isReply {
                let english = try await interpreter.transcribeEnglish(samples)
                if english.isEmpty { status = "Didn't catch that. Tap Reply and try again."; return }
                await sendReply(english)
                return
            }

            if Prefs.engine == .offline {
                await handleOffline(samples)
                return
            }

            guard let heard = try await interpreter.listen(samples, assumeSwahili: Prefs.assumeSwahili) else {
                status = listeningText
                return
            }
            if heard.language == "en" {
                if Prefs.autoReply && Prefs.canReply { await sendReply(heard.text) }
                else { status = "Heard English, skipped." }
                return
            }
            if Prefs.onlySwahili && !Prefs.assumeSwahili && heard.language != "sw" {
                status = "Heard another language (\(heard.language)), skipped."
                return
            }
            guard Prefs.canReply else {
                // No translator key yet: show what was said so the app is still useful.
                lines.insert(Line(kind: .heard, english: heard.text, swahili: nil), at: 0)
                trim()
                status = "Showing Kiswahili only. Add your Microsoft key, or choose the free MyMemory translator in Settings."
                return
            }
            status = "Translating…"
            let english = try await ReplyService.translateToEnglish(heard.text)
            lines.insert(Line(kind: .heard, english: english,
                              swahili: Prefs.showOriginal ? heard.text : nil), at: 0)
            trim()
            if Prefs.speakAloud { await sayEnglish(english) }
            status = listeningText
        } catch {
            status = "Translation error: \(error.localizedDescription)"
        }
    }

    /// Offline: Whisper translates straight to English on the phone; no internet needed.
    private func handleOffline(_ samples: [Float]) async {
        do {
            guard let heard = try await interpreter.translateOffline(samples, assumeSwahili: Prefs.assumeSwahili) else {
                status = listeningText
                return
            }
            if heard.language == "en" {
                if Prefs.autoReply { await sendReply(heard.text) } else { status = "Heard English, skipped." }
                return
            }
            if Prefs.onlySwahili && !Prefs.assumeSwahili && heard.language != "sw" {
                status = "Heard another language (\(heard.language)), skipped."
                return
            }
            lines.insert(Line(kind: .heard, english: heard.text, swahili: nil), at: 0)
            trim()
            if Prefs.speakAloud { await sayEnglish(heard.text) }
            status = listeningText
        } catch {
            status = "Translation error: \(error.localizedDescription)"
        }
    }

    private func trim() { if lines.count > 200 { lines.removeLast() } }

    // MARK: Speaking

    private func sayEnglish(_ text: String) async {
        // With AirPods the mic keeps listening; on the loudspeaker it pauses so it won't hear itself.
        let mute = Speaker.usingPhoneSpeaker
        if mute { recorder.isPaused = true }
        await speaker.speakEnglish(text)
        if mute { await resumeMic() }
    }

    /// Kiswahili replies are for the other person, so by default they play on the phone's loudspeaker
    /// even when you wear AirPods.
    private func saySwahili(_ text: String) async {
        let session = AVAudioSession.sharedInstance()
        if Prefs.replyOnSpeaker { try? session.overrideOutputAudioPort(.speaker) }
        recorder.isPaused = true
        let audio = try? await ReplyService.swahiliAudio(text)
        let spoke = await speaker.speakSwahili(text, audio: audio)
        if !spoke { status = "Show them the screen. Add a Speech key in Settings for a Kiswahili voice." }
        if Prefs.replyOnSpeaker { try? session.overrideOutputAudioPort(.none) }
        await resumeMic()
    }

    private func resumeMic() async {
        try? await Task.sleep(for: .milliseconds(250))
        recorder.isPaused = false
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

    private var listeningText: String {
        if Prefs.autoReply && Prefs.canReply { return "Listening… Kiswahili → English, your English → Kiswahili" }
        return Prefs.onlySwahili ? "Listening for Kiswahili…" : "Listening… translating anything not in English"
    }
}
