import SwiftUI

struct SettingsView: View {
    @ObservedObject var engine: ListenEngine
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.Key.sourceLang) private var source = "sw"
    @AppStorage(Prefs.Key.targetLang) private var target = "en"
    @AppStorage(Prefs.Key.speakWhere) private var speakWhere = Prefs.SpeakWhere.headphones.rawValue
    @AppStorage(Prefs.Key.replyWhere) private var replyWhere = Prefs.ReplyWhere.speaker.rawValue
    @AppStorage(Prefs.Key.model) private var model = Prefs.accurateModel
    @AppStorage(Prefs.Key.showOriginal) private var showOriginal = false
    @AppStorage(Prefs.Key.assumeSwahili) private var assumeSource = false
    @AppStorage(Prefs.Key.pauseSeconds) private var pauseSeconds = 0.8
    @AppStorage(Prefs.Key.autoReply) private var autoReply = false
    @AppStorage(Prefs.Key.translatorRegion) private var translatorRegion = "southafricanorth"
    @AppStorage(Prefs.Key.speechRegion) private var speechRegion = "southafricanorth"
    @AppStorage(Prefs.Key.swahiliVoice) private var swahiliVoice = "sw-KE-ZuriNeural"
    @AppStorage(Prefs.Key.engine) private var engineChoice = Prefs.Engine.mymemory.rawValue
    @AppStorage(Prefs.Key.myMemoryEmail) private var myMemoryEmail = ""

    @State private var translatorKey = Prefs.translatorKey
    @State private var speechKey = Prefs.speechKey
    @State private var modelAtOpen = ""

    private var sourceName: String { Langs.name(source) }
    private var targetName: String { Langs.name(target) }

    private var engineFooter: String {
        switch Prefs.Engine(rawValue: engineChoice) ?? .mymemory {
        case .mymemory:
            return "No signup. The phone writes down what it hears, then MyMemory's free service translates it (and your replies). Needs internet; there's a daily free limit. The email is optional."
        case .offline:
            return target == "en"
                ? "No internet needed. Uses a larger speech model (about 950 MB, downloaded once on Wi-Fi) that translates speech straight into English. Slower and less accurate than MyMemory. Replies still use MyMemory online."
                : "Offline translation only works into English, so MyMemory (online) is used for \(targetName)."
        case .microsoft:
            return "Best quality. Needs a free Microsoft Translator key (below), which requires an Azure account."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Listen for", selection: $source) {
                        ForEach(Langs.listenOptions, id: \.code) { Text($0.name).tag($0.code) }
                    }
                    Picker("Translate into", selection: $target) {
                        ForEach(Langs.translateOptions, id: \.code) { Text($0.name).tag($0.code) }
                    }
                } header: {
                    Text("Languages")
                } footer: {
                    Text(source == target
                         ? "Choose two different languages."
                         : "Tafsiri listens all the time. When it hears \(sourceName) it shows and speaks \(targetName). When it hears \(targetName), it treats that as you.")
                }

                Section {
                    Picker("Speak translations", selection: $speakWhere) {
                        Text("Headphones only").tag(Prefs.SpeakWhere.headphones.rawValue)
                        Text("Headphones or speaker").tag(Prefs.SpeakWhere.anywhere.rawValue)
                        Text("Don't speak (text only)").tag(Prefs.SpeakWhere.off.rawValue)
                    }
                    Picker("Speak my replies on", selection: $replyWhere) {
                        Text("Phone speaker").tag(Prefs.ReplyWhere.speaker.rawValue)
                        Text("Headphones").tag(Prefs.ReplyWhere.headphones.rawValue)
                    }
                    Toggle("Auto-reply: translate my \(targetName)", isOn: $autoReply)
                } header: {
                    Text("Sound")
                } footer: {
                    Text("\"Headphones only\" speaks translations in your AirPods or earphones and shows text only when none are connected. Replies on the phone speaker let the other person hear you even while you wear headphones. With auto-reply on, any \(targetName) the phone hears is spoken back in \(sourceName) with no taps; leave it off where other people nearby speak \(targetName).")
                }

                Section {
                    Picker("Translate with", selection: $engineChoice) {
                        Text("MyMemory (free, online)").tag(Prefs.Engine.mymemory.rawValue)
                        Text("On this iPhone (free, offline)").tag(Prefs.Engine.offline.rawValue)
                        Text("Microsoft (free key needed)").tag(Prefs.Engine.microsoft.rawValue)
                    }
                    if engineChoice == Prefs.Engine.mymemory.rawValue {
                        TextField("Your email (optional)", text: $myMemoryEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                } header: {
                    Text("Translation")
                } footer: {
                    Text(engineFooter)
                }

                Section {
                    Toggle("Also show the \(sourceName) words (small)", isOn: $showOriginal)
                    Toggle("Everyone around me speaks \(sourceName)", isOn: $assumeSource)
                    Stepper(value: $pauseSeconds, in: 0.5...2.0, step: 0.1) {
                        Text("Translate after a \(pauseSeconds, specifier: "%.1f") s pause")
                    }
                } header: {
                    Text("Fine-tuning")
                } footer: {
                    Text("\"Everyone around me speaks \(sourceName)\" skips language detection, which helps with short phrases, but then your own \(targetName) is also treated as theirs. Lower the pause for faster translations; raise it if sentences get cut. Pause changes apply next time you tap Start.")
                }

                if source == "sw" {
                    Section {
                        Picker("Kiswahili voice", selection: $swahiliVoice) {
                            Text("Zuri (female, Kenya)").tag("sw-KE-ZuriNeural")
                            Text("Rafiki (male, Kenya)").tag("sw-KE-RafikiNeural")
                            Text("Rehema (female, Tanzania)").tag("sw-TZ-RehemaNeural")
                            Text("Daudi (male, Tanzania)").tag("sw-TZ-DaudiNeural")
                        }
                    } header: {
                        Text("Kiswahili voice for replies")
                    } footer: {
                        Text("Uses the Microsoft Speech key below. Without it, the iPhone's own Kiswahili voice is used if installed; otherwise replies are shown on screen.")
                    }
                }

                Section {
                    SecureField("Translator key", text: $translatorKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Translator region (e.g. southafricanorth)", text: $translatorRegion)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Speech key (Kiswahili voice)", text: $speechKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Speech region", text: $speechRegion)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: {
                    Text("Optional Microsoft keys")
                } footer: {
                    Text("Not needed with MyMemory. Only for the Microsoft translation option and the natural Kiswahili voice. In portal.azure.com create Translator and Speech resources on the Free (F0) tier and copy Key 1 and the region.")
                }

                Section {
                    Picker("Speech model", selection: $model) {
                        Text("Accurate (about 626 MB)").tag(Prefs.accurateModel)
                        Text("Fast (smaller, less accurate)").tag(Prefs.fastModel)
                    }
                } header: {
                    Text("On-device speech model")
                } footer: {
                    Text("Used to hear speech. Downloaded once; it then works without internet.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { modelAtOpen = Prefs.effectiveModel }
            .onDisappear {
                Keychain.set(translatorKey.trimmingCharacters(in: .whitespacesAndNewlines), for: Prefs.translatorKeyName)
                Keychain.set(speechKey.trimmingCharacters(in: .whitespacesAndNewlines), for: Prefs.speechKeyName)
                if Prefs.effectiveModel != modelAtOpen {
                    if engine.isListening { engine.stop() }
                    engine.modelState = .notLoaded
                    Task { await engine.loadModel() }
                } else if engine.isListening {
                    engine.status = engine.listeningText
                }
            }
        }
    }
}
