import Foundation
import Security

/// User settings, stored on the phone. Views bind to the same keys with @AppStorage.
enum Prefs {
    enum Key {
        static let model = "model"
        static let speakAloud = "speakAloud"
        static let showOriginal = "showOriginal"
        static let onlySwahili = "onlySwahili"
        static let assumeSwahili = "assumeSwahili"
        static let pauseSeconds = "pauseSeconds"
        static let autoReply = "autoReply"
        static let replyOnSpeaker = "replyOnSpeaker"
        static let translatorRegion = "translatorRegion"
        static let speechRegion = "speechRegion"
        static let swahiliVoice = "swahiliVoice"
        static let engine = "engine"
        static let myMemoryEmail = "myMemoryEmail"
    }

    /// How Kiswahili becomes English (and your English becomes Kiswahili).
    enum Engine: String, CaseIterable {
        case mymemory    // free online service, no signup
        case offline     // Whisper translates on the phone, no internet
        case microsoft   // Microsoft Translator, needs a free Azure key
    }

    /// Whisper model that can translate to English itself (the turbo model can't).
    static let offlineModel = "large-v2_949MB"

    /// Accurate model recommended for iPhone (about 626 MB download, once).
    static let accurateModel = "large-v3-v20240930_626MB"
    /// Smaller, faster model; noticeably weaker on Kiswahili.
    static let fastModel = "small"

    static func register() {
        UserDefaults.standard.register(defaults: [
            Key.model: accurateModel,
            Key.speakAloud: true,
            Key.showOriginal: true,
            Key.onlySwahili: true,
            Key.assumeSwahili: false,
            Key.pauseSeconds: 0.8,
            Key.autoReply: false,
            Key.replyOnSpeaker: true,
            Key.translatorRegion: "southafricanorth",
            Key.speechRegion: "southafricanorth",
            Key.swahiliVoice: "sw-KE-ZuriNeural",
            Key.engine: Engine.mymemory.rawValue,
            Key.myMemoryEmail: ""
        ])
    }

    static var d: UserDefaults { .standard }
    static var model: String { d.string(forKey: Key.model) ?? accurateModel }
    static var speakAloud: Bool { d.bool(forKey: Key.speakAloud) }
    static var showOriginal: Bool { d.bool(forKey: Key.showOriginal) }
    static var onlySwahili: Bool { d.bool(forKey: Key.onlySwahili) }
    static var assumeSwahili: Bool { d.bool(forKey: Key.assumeSwahili) }
    static var pauseSeconds: Double { d.double(forKey: Key.pauseSeconds) }
    static var autoReply: Bool { d.bool(forKey: Key.autoReply) }
    static var replyOnSpeaker: Bool { d.bool(forKey: Key.replyOnSpeaker) }
    static var translatorRegion: String { d.string(forKey: Key.translatorRegion) ?? "" }
    static var speechRegion: String { d.string(forKey: Key.speechRegion) ?? "" }
    static var swahiliVoice: String { d.string(forKey: Key.swahiliVoice) ?? "sw-KE-ZuriNeural" }

    // Free Microsoft keys, kept in the Keychain.
    static let translatorKeyName = "ms_translator_key"
    static let speechKeyName = "ms_speech_key"
    static var translatorKey: String { Keychain.get(translatorKeyName) }
    static var speechKey: String { Keychain.get(speechKeyName) }
    static var engine: Engine { Engine(rawValue: d.string(forKey: Key.engine) ?? "") ?? .mymemory }
    static var myMemoryEmail: String { (d.string(forKey: Key.myMemoryEmail) ?? "").trimmingCharacters(in: .whitespaces) }
    /// The model actually loaded: offline translation needs the translation-capable model.
    static var effectiveModel: String { engine == .offline ? offlineModel : model }
    /// Online translation is available (MyMemory needs nothing; Microsoft needs its key).
    static var canReply: Bool { engine != .microsoft || !translatorKey.isEmpty }
}

/// Stores keys encrypted in the iPhone Keychain.
enum Keychain {
    static func set(_ value: String, for key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// One line in the conversation.
struct Line: Identifiable, Equatable {
    enum Kind { case heard, reply }
    let id = UUID()
    let kind: Kind
    /// For `.heard`: the English translation. For `.reply`: what you said in English.
    let english: String
    /// For `.heard`: the original Kiswahili (optional). For `.reply`: the Kiswahili translation.
    let swahili: String?
    let time = Date()
}
