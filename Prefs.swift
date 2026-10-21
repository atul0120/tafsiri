import Foundation
import Security

/// Languages the app can listen for and translate into (Whisper / translator codes).
enum Langs {
    static let listenOptions: [(code: String, name: String)] = [
        ("sw", "Kiswahili"), ("so", "Somali"), ("am", "Amharic"), ("ar", "Arabic"),
        ("fr", "French"), ("pt", "Portuguese"), ("hi", "Hindi"), ("zh", "Chinese"),
        ("ln", "Lingala"), ("ha", "Hausa"), ("yo", "Yoruba"), ("es", "Spanish"), ("en", "English")
    ]
    static let translateOptions: [(code: String, name: String)] = [
        ("en", "English"), ("hi", "Hindi"), ("sw", "Kiswahili"), ("fr", "French"),
        ("ar", "Arabic"), ("pt", "Portuguese"), ("es", "Spanish"), ("zh", "Chinese")
    ]

    static func name(_ code: String) -> String {
        (listenOptions + translateOptions).first { $0.code == code }?.name ?? code.uppercased()
    }
}

/// User settings, stored on the phone. Views bind to the same keys with @AppStorage.
enum Prefs {
    enum Key {
        static let model = "model"
        static let speakAloud = "speakAloud"
        static let showOriginal = "showOriginal"
        static let assumeSwahili = "assumeSwahili"      // "everyone around me speaks <listen language>"
        static let pauseSeconds = "pauseSeconds"
        static let autoReply = "autoReply"
        static let translatorRegion = "translatorRegion"
        static let speechRegion = "speechRegion"
        static let swahiliVoice = "swahiliVoice"
        static let engine = "engine"
        static let myMemoryEmail = "myMemoryEmail"
        static let sourceLang = "sourceLang"
        static let targetLang = "targetLang"
        static let speakWhere = "speakWhere"
        static let replyWhere = "replyWhere"
    }

    /// How speech is translated.
    enum Engine: String, CaseIterable {
        case mymemory    // free online service, no signup
        case offline     // Whisper translates on the phone, no internet (into English only)
        case microsoft   // Microsoft Translator, needs a free Azure key
    }

    /// Where translations of what you hear are spoken.
    enum SpeakWhere: String, CaseIterable {
        case headphones  // only when headphones are connected; otherwise text only
        case anywhere    // headphones if connected, otherwise the loudspeaker
        case off         // never; text only
    }

    /// Where your replies (in their language) are spoken.
    enum ReplyWhere: String, CaseIterable {
        case speaker     // phone loudspeaker, so the other person hears it
        case headphones  // wherever sound is going (headphones if connected)
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
            Key.showOriginal: false,
            Key.assumeSwahili: false,
            Key.pauseSeconds: 0.6,
            Key.autoReply: false,
            Key.translatorRegion: "southafricanorth",
            Key.speechRegion: "southafricanorth",
            Key.swahiliVoice: "sw-KE-ZuriNeural",
            Key.engine: Engine.mymemory.rawValue,
            Key.myMemoryEmail: "",
            Key.sourceLang: "sw",
            Key.targetLang: "en",
            Key.speakWhere: SpeakWhere.headphones.rawValue,
            Key.replyWhere: ReplyWhere.speaker.rawValue
        ])
    }

    static var d: UserDefaults { .standard }
    static var model: String { d.string(forKey: Key.model) ?? accurateModel }
    static var speakAloud: Bool { d.bool(forKey: Key.speakAloud) }
    static var showOriginal: Bool { d.bool(forKey: Key.showOriginal) }
    static var assumeSource: Bool { d.bool(forKey: Key.assumeSwahili) }
    static var pauseSeconds: Double { d.double(forKey: Key.pauseSeconds) }
    static var autoReply: Bool { d.bool(forKey: Key.autoReply) }
    static var translatorRegion: String { d.string(forKey: Key.translatorRegion) ?? "" }
    static var speechRegion: String { d.string(forKey: Key.speechRegion) ?? "" }
    static var swahiliVoice: String { d.string(forKey: Key.swahiliVoice) ?? "sw-KE-ZuriNeural" }
    static var source: String { d.string(forKey: Key.sourceLang) ?? "sw" }
    static var target: String { d.string(forKey: Key.targetLang) ?? "en" }
    static var sourceName: String { Langs.name(source) }
    static var targetName: String { Langs.name(target) }
    static var speakWhere: SpeakWhere { SpeakWhere(rawValue: d.string(forKey: Key.speakWhere) ?? "") ?? .headphones }
    static var replyWhere: ReplyWhere { ReplyWhere(rawValue: d.string(forKey: Key.replyWhere) ?? "") ?? .speaker }

    // Free Microsoft keys, kept in the Keychain.
    static let translatorKeyName = "ms_translator_key"
    static let speechKeyName = "ms_speech_key"
    static var translatorKey: String { Keychain.get(translatorKeyName) }
    static var speechKey: String { Keychain.get(speechKeyName) }
    static var engine: Engine { Engine(rawValue: d.string(forKey: Key.engine) ?? "") ?? .mymemory }
    static var myMemoryEmail: String { (d.string(forKey: Key.myMemoryEmail) ?? "").trimmingCharacters(in: .whitespaces) }
    /// Offline translation works only into English; otherwise fall back to online translation.
    static var useOffline: Bool { engine == .offline && target == "en" }
    /// The model actually loaded: offline translation needs the translation-capable model.
    static var effectiveModel: String { useOffline ? offlineModel : model }
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
    /// Text in YOUR language: the translation of what you heard, or what you said.
    let mine: String
    /// Text in THEIR language: what they said (when shown), or your reply translated.
    let theirs: String?
    /// Language codes, so replays use the right voice.
    let myLang: String
    let theirLang: String
    let time = Date()
}
