import Foundation
import WhisperKit

/// Runs OpenAI's Whisper model on the iPhone (via WhisperKit). Whisper can translate
/// speech in other languages straight into English, so one pass both detects the
/// language and gives the English. Free, private and offline once the model is downloaded.
actor Interpreter {
    struct Output {
        let language: String     // e.g. "sw", "en"
        let english: String
        let original: String?    // Kiswahili text, when requested
    }

    private var pipe: WhisperKit?
    private(set) var loadedModel: String?

    func load(model: String) async throws {
        if loadedModel == model, pipe != nil { return }
        pipe = nil
        pipe = try await WhisperKit(WhisperKitConfig(model: model))
        loadedModel = model
    }

    func process(_ samples: [Float], assumeSwahili: Bool, wantOriginal: Bool) async throws -> Output? {
        guard let pipe else { return nil }

        var options = DecodingOptions()
        options.task = .translate                    // speech → English
        options.language = assumeSwahili ? "sw" : nil
        options.detectLanguage = !assumeSwahili
        options.temperature = 0
        options.skipSpecialTokens = true
        options.withoutTimestamps = true

        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        let language = (assumeSwahili ? "sw" : results.first?.language) ?? "unknown"
        let english = Self.clean(results.map(\.text).joined(separator: " "))
        guard !english.isEmpty else { return nil }

        var original: String?
        if wantOriginal, language != "en" {
            var t = options
            t.task = .transcribe
            t.language = language == "unknown" ? "sw" : language
            t.detectLanguage = false
            let r = try await pipe.transcribe(audioArray: samples, decodeOptions: t)
            original = Self.clean(r.map(\.text).joined(separator: " "))
        }
        return Output(language: language, english: english, original: original)
    }

    /// Writes down English speech (used when you reply). Runs on the phone.
    func transcribeEnglish(_ samples: [Float]) async throws -> String {
        guard let pipe else { return "" }
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = "en"
        options.detectLanguage = false
        options.temperature = 0
        options.skipSpecialTokens = true
        options.withoutTimestamps = true
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        return Self.clean(results.map(\.text).joined(separator: " "))
    }

    /// Removes Whisper's stock "hallucinations" on background noise.
    static func clean(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = t.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        let junk: Set<String> = ["", "you", "thank you", "thanks for watching", "thank you for watching",
                                 "bye", "subtitles by the amaraorg community", "music"]
        if junk.contains(lower) { return "" }
        if (t.hasPrefix("[") && t.hasSuffix("]")) || (t.hasPrefix("(") && t.hasSuffix(")")) { return "" }
        return t
    }
}
