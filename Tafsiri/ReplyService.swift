import Foundation

/// English → Kiswahili for your replies, using Microsoft's free tiers:
/// Azure AI Translator (F0) for the text and Azure AI Speech (F0) for a natural Kenyan voice.
enum ReplyService {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func translateToSwahili(_ english: String) async throws -> String {
        let key = Prefs.translatorKey
        guard !key.isEmpty else {
            throw Failure(message: "Add your free Microsoft Translator key in Settings to reply in Kiswahili.")
        }
        var url = URLComponents(string: "https://api.cognitive.microsofttranslator.com/translate")!
        url.queryItems = [.init(name: "api-version", value: "3.0"),
                          .init(name: "from", value: "en"),
                          .init(name: "to", value: "sw")]
        var request = URLRequest(url: url.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        let region = Prefs.translatorRegion.trimmingCharacters(in: .whitespaces)
        if !region.isEmpty && region.lowercased() != "global" {
            request.setValue(region, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [["Text": english]])

        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data, service: "Translator")
        struct Item: Decodable { struct T: Decodable { let text: String }; let translations: [T] }
        let items = try JSONDecoder().decode([Item].self, from: data)
        guard let text = items.first?.translations.first?.text else {
            throw Failure(message: "Translator returned no text.")
        }
        return text
    }

    /// Returns MP3 audio of the Kiswahili text, or nil when no Speech key is set.
    static func swahiliAudio(_ text: String) async throws -> Data? {
        let key = Prefs.speechKey
        let region = Prefs.speechRegion.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !region.isEmpty else { return nil }
        var request = URLRequest(url: URL(string: "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.setValue("Tafsiri", forHTTPHeaderField: "User-Agent")
        let ssml = """
        <speak version="1.0" xml:lang="sw-KE"><voice name="\(Prefs.swahiliVoice)">\(escape(text))</voice></speak>
        """
        request.httpBody = Data(ssml.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data, service: "Kiswahili voice")
        return data
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func check(_ response: URLResponse, _ data: Data, service: String) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        switch http.statusCode {
        case 401, 403:
            throw Failure(message: "\(service): the key or region in Settings isn't accepted.")
        case 429:
            throw Failure(message: "\(service): free monthly allowance used up or too many requests. Try again later.")
        default:
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = (json?["error"] as? [String: Any])?["message"] as? String
            throw Failure(message: "\(service): \(detail ?? "error \(http.statusCode)")")
        }
    }
}
