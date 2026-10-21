import Foundation
import WhisperKit

/// Runs OpenAI's Whisper speech model on the iPhone (via WhisperKit) to write down what
/// people say and tell which language it is. Free, private and offline once downloaded.
/// (The recommended "turbo" model is excellent at writing down Kiswahili but does not
/// translate, so translation is done separately.)
actor Interpreter {
    struct Heard {
        let language: String   // e.g. "sw", "en"
        let text: String       // what was said, in that language
    }

    private var pipe: WhisperKit?
    private(set) var loadedModel: String?

    func load(model: String) async throws {
        if loadedModel == model, pipe != nil { return }
        pipe = nil
        let kit = try await WhisperKit(WhisperKitConfig(model: model))
        // The first run on a new iPhone compiles the model for its chip, which can take
        // a few minutes. Do it now with one second of silence, not mid-conversation.
        _ = try? await kit.transcribe(audioArray: [Float](repeating: 0, count: 16_000),
                                      decodeOptions: Self.options(language: "sw"))
        pipe = kit
        loadedModel = model
    }

    /// Writes down one utterance and detects its language.
    func listen(_ samples: [Float], assumeSwahili: Bool) async throws -> Heard? {
        guard let pipe else { return nil }
        let options = Self.options(language: assumeSwahili ? "sw" : nil)
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        let text = Self.clean(results.map(\.text).joined(separator: " "))
        guard !text.isEmpty else { return nil }
        let detected = assumeSwahili ? "sw" : (results.first?.language ?? "sw")
        if detected == "en" || detected == "sw" { return Heard(language: detected, text: text) }

        // Whisper often mistakes Kiswahili for Indonesian, Malay, Somali and others.
        // Anything that isn't English is treated as Kiswahili and written down again as Kiswahili.
        let again = try await pipe.transcribe(audioArray: samples, decodeOptions: Self.options(language: "sw"))
        let swText = Self.clean(again.map(\.text).joined(separator: " "))
        return swText.isEmpty ? nil : Heard(language: "sw", text: swText)
    }

    /// Offline mode: Whisper translates the speech straight into English on the phone.
    /// Needs a translation-capable model (Prefs.offlineModel).
    func translateOffline(_ samples: [Float], assumeSwahili: Bool) async throws -> Heard? {
        guard let pipe else { return nil }
        var options = Self.options(language: assumeSwahili ? "sw" : nil)
        options.task = .translate
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        let text = Self.clean(results.map(\.text).joined(separator: " "))
        guard !text.isEmpty else { return nil }
        let detected = assumeSwahili ? "sw" : (results.first?.language ?? "sw")
        if detected == "en" || detected == "sw" { return Heard(language: detected, text: text) }

        // Misdetected (often as Indonesian): translate again, telling Whisper it's Kiswahili.
        var forced = Self.options(language: "sw")
        forced.task = .translate
        let again = try await pipe.transcribe(audioArray: samples, decodeOptions: forced)
        let english = Self.clean(again.map(\.text).joined(separator: " "))
        return english.isEmpty ? nil : Heard(language: "sw", text: english)   // text is English here
    }

    /// Writes down English speech (used when you reply).
    func transcribeEnglish(_ samples: [Float]) async throws -> String {
        guard let pipe else { return "" }
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: Self.options(language: "en"))
        return Self.clean(results.map(\.text).joined(separator: " "))
    }

    private static func options(language: String?) -> DecodingOptions {
        var o = DecodingOptions()
        o.task = .transcribe
        o.language = language
        o.detectLanguage = language == nil
        o.temperature = 0
        o.skipSpecialTokens = true
        o.withoutTimestamps = true
        return o
    }

    /// Removes Whisper's stock "hallucinations" on background noise.
    static func clean(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = t.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        let junk: Set<String> = ["", "you", "thank you", "thanks for watching", "thank you for watching",
                                 "bye", "subtitles by the amaraorg community", "music",
                                 "asante kwa kutazama", "asante"]
        if junk.contains(lower) { return "" }
        if (t.hasPrefix("[") && t.hasSuffix("]")) || (t.hasPrefix("(") && t.hasSuffix(")")) { return "" }
        return t
    }
}
