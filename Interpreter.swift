import Foundation
import WhisperKit

/// Runs OpenAI's Whisper speech model on the iPhone (via WhisperKit) to write down what
/// people say and tell which language it is. Free, private and offline once downloaded.
actor Interpreter {
    struct Heard {
        let language: String   // e.g. "sw", "en"
        let text: String
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

    /// Writes down one utterance. Returns it as `target` (you speaking) or `source` (them).
    /// Anything else is treated as `source`, because Whisper often mistakes Kiswahili
    /// for Indonesian, Malay or Somali.
    func listen(_ samples: [Float], source: String, target: String, forceSource: Bool) async throws -> Heard? {
        guard let pipe else { return nil }
        let first = try await pipe.transcribe(audioArray: samples,
                                              decodeOptions: Self.options(language: forceSource ? source : nil))
        let text = Self.clean(first.map(\.text).joined(separator: " "))
        guard !text.isEmpty else { return nil }
        let detected = forceSource ? source : (first.first?.language ?? source)
        if detected == target { return Heard(language: target, text: text) }
        // Anything else is theirs. A misdetected sentence (e.g. "Indonesian") is still written in
        // their words, so use it as-is instead of running the model a second time (much faster).
        return Heard(language: source, text: text)
    }

    /// Offline mode: Whisper translates speech straight into English on the phone.
    /// Returns language "en" with the English if the speaker was already speaking English.
    func translateOffline(_ samples: [Float], source: String, forceSource: Bool) async throws -> Heard? {
        guard let pipe else { return nil }
        var options = Self.options(language: forceSource ? source : nil)
        options.task = .translate
        let first = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        let text = Self.clean(first.map(\.text).joined(separator: " "))
        guard !text.isEmpty else { return nil }
        let detected = forceSource ? source : (first.first?.language ?? source)
        if detected == source || detected == "en" { return Heard(language: detected, text: text) }

        var forced = Self.options(language: source)
        forced.task = .translate
        let again = try await pipe.transcribe(audioArray: samples, decodeOptions: forced)
        let english = Self.clean(again.map(\.text).joined(separator: " "))
        return english.isEmpty ? nil : Heard(language: source, text: english)
    }

    /// Writes down speech in a known language (used for your replies).
    func transcribe(_ samples: [Float], language: String) async throws -> String {
        guard let pipe else { return "" }
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: Self.options(language: language))
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
