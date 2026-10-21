import SwiftUI

struct SettingsView: View {
    @ObservedObject var engine: ListenEngine
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.Key.model) private var model = Prefs.accurateModel
    @AppStorage(Prefs.Key.speakAloud) private var speakAloud = true
    @AppStorage(Prefs.Key.showOriginal) private var showOriginal = true
    @AppStorage(Prefs.Key.onlySwahili) private var onlySwahili = true
    @AppStorage(Prefs.Key.assumeSwahili) private var assumeSwahili = false
    @AppStorage(Prefs.Key.pauseSeconds) private var pauseSeconds = 0.8
    @AppStorage(Prefs.Key.autoReply) private var autoReply = false
    @AppStorage(Prefs.Key.replyOnSpeaker) private var replyOnSpeaker = true
    @AppStorage(Prefs.Key.translatorRegion) private var translatorRegion = "southafricanorth"
    @AppStorage(Prefs.Key.speechRegion) private var speechRegion = "southafricanorth"
    @AppStorage(Prefs.Key.swahiliVoice) private var swahiliVoice = "sw-KE-ZuriNeural"

    @State private var translatorKey = Prefs.translatorKey
    @State private var speechKey = Prefs.speechKey
    @State private var modelAtOpen = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Read translations aloud", isOn: $speakAloud)
                    Toggle("Only translate Kiswahili", isOn: $onlySwahili)
                    Toggle("Show the Kiswahili words too", isOn: $showOriginal)
                } header: {
                    Text("Listening")
                } footer: {
                    Text("Connect AirPods to hear translations privately while the phone keeps listening.")
                }

                Section {
                    Toggle("Auto-reply: translate my English", isOn: $autoReply)
                    Toggle("Play replies on the phone speaker", isOn: $replyOnSpeaker)
                    Picker("Kiswahili voice", selection: $swahiliVoice) {
                        Text("Zuri (female, Kenya)").tag("sw-KE-ZuriNeural")
                        Text("Rafiki (male, Kenya)").tag("sw-KE-RafikiNeural")
                        Text("Rehema (female, Tanzania)").tag("sw-TZ-RehemaNeural")
                        Text("Daudi (male, Tanzania)").tag("sw-TZ-DaudiNeural")
                    }
                } header: {
                    Text("Replying in Kiswahili")
                } footer: {
                    Text("With auto-reply on, any English the phone hears is spoken back in Kiswahili, fully hands-free. Turn it off if other people nearby speak English, and use the Reply button instead.")
                }

                Section {
                    SecureField("Translator key", text: $translatorKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Translator region (e.g. southafricanorth)", text: $translatorRegion)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Speech key (for the Kiswahili voice)", text: $speechKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Speech region", text: $speechRegion)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: {
                    Text("Free Microsoft keys")
                } footer: {
                    Text("The Translator key turns Kiswahili into English and your replies into Kiswahili; without it you see only the Kiswahili words. The Speech key gives replies a Kenyan voice. In portal.azure.com create a Translator and a Speech resource, choose the Free (F0) tier, then copy Key 1 and the Location/Region from \"Keys and Endpoint\". The free tier stops at its monthly limit; it doesn't charge you.")
                }

                Section {
                    Stepper(value: $pauseSeconds, in: 0.5...2.0, step: 0.1) {
                        Text("Translate after a \(pauseSeconds, specifier: "%.1f") s pause")
                    }
                    Toggle("Everyone around me speaks Kiswahili", isOn: $assumeSwahili)
                } header: {
                    Text("Fine-tuning")
                } footer: {
                    Text("Lower the pause for faster translations; raise it if sentences get cut. \"Everyone speaks Kiswahili\" skips language detection (better for short phrases) but turns off auto-reply. Pause changes apply next time you tap Start.")
                }

                Section {
                    Picker("Speech model", selection: $model) {
                        Text("Accurate (about 626 MB)").tag(Prefs.accurateModel)
                        Text("Fast (smaller, less accurate)").tag(Prefs.fastModel)
                    }
                } header: {
                    Text("On-device model")
                } footer: {
                    Text("Downloaded once. Listening and English translation then work offline, and what you hear never leaves the phone. Only your replies go to Microsoft.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { modelAtOpen = model }
            .onDisappear {
                Keychain.set(translatorKey.trimmingCharacters(in: .whitespacesAndNewlines), for: Prefs.translatorKeyName)
                Keychain.set(speechKey.trimmingCharacters(in: .whitespacesAndNewlines), for: Prefs.speechKeyName)
                if model != modelAtOpen {
                    if engine.isListening { engine.stop() }
                    engine.modelState = .notLoaded
                    Task { await engine.loadModel() }
                }
            }
        }
    }
}
