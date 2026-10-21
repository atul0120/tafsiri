import Foundation

/// English → Kiswahili for your replies, using Microsoft's free tiers:
/// Azure AI Translator (F0) for the text and Azure AI Speech (F0) for a natural Kenyan voice.
enum ReplyService {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func translateToSwahili(_ english: String) async throws -> String {
        try await translate(english, from: "en", to: "sw")
    }

    static func translateToEnglish(_ swahili: String) async throws -> String {
        try await translate(swahili, from: "sw", to: "en")
    }

    /// Uses Microsoft when chosen in Settings, otherwise the free MyMemory service.
    static func translate(_ text: String, from: String, to: String) async throws -> String {
        if Prefs.engine == .microsoft { return try await microsoft(text, from: from, to: to) }
        return try await myMemory(text, from: from, to: to)
    }

    // MARK: MyMemory — free, no account (mymemory.translated.net)

    static func myMemory(_ text: String, from: String, to: String) async throws -> String {
        var parts: [String] = []
        for chunk in chunks(text, maxBytes: 450) {          // the service takes up to 500 bytes per request
            var url = URLComponents(string: "https://api.mymemory.translated.net/get")!
            var items = [URLQueryItem(name: "q", value: chunk),
                         URLQueryItem(name: "langpair", value: "\(from)|\(to)")]
            if !Prefs.myMemoryEmail.isEmpty { items.append(URLQueryItem(name: "de", value: Prefs.myMemoryEmail)) }
            url.queryItems = items
            var request = URLRequest(url: url.url!)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = (response as? HTTPURLResponse)?.statusCode ?? 200
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let translated = (json?["responseData"] as? [String: Any])?["translatedText"] as? String ?? ""
            let status = (json?["responseStatus"] as? Int) ?? Int("\(json?["responseStatus"] ?? "200")") ?? 200
            if translated.uppercased().contains("MYMEMORY WARNING") || http == 429 || status == 429 {
                throw Failure(message: "Today's free translations are used up. They reset tomorrow, or switch to another option in Settings.")
            }
            guard http == 200, status == 200, !translated.isEmpty else {
                throw Failure(message: "Free translator: \(translated.isEmpty ? "no answer (error \(http))" : translated)")
            }
            parts.append(unescape(translated))
        }
        let result = parts.joined(separator: " ")
        // The free service sometimes hands the text back untranslated. Never pass that on as "English".
        if normalized(result) == normalized(text) {
            throw Failure(message: "Couldn't translate that sentence. Try again, or choose another option in Settings → Translate with.")
        }
        return result
    }

    private static func chunks(_ text: String, maxBytes: Int) -> [String] {
        var out: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if candidate.utf8.count > maxBytes, !current.isEmpty {
                out.append(current)
                current = String(word)
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private static func normalized(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: Microsoft Translator — free F0 tier, needs an Azure key

    static func microsoft(_ text: String, from: String, to: String) async throws -> String {
        let key = Prefs.translatorKey
        guard !key.isEmpty else {
            throw Failure(message: "Add your free Microsoft Translator key in Settings.")
        }
        var url = URLComponents(string: "https://api.cognitive.microsofttranslator.com/translate")!
        url.queryItems = [.init(name: "api-version", value: "3.0"),
                          .init(name: "from", value: from),
                          .init(name: "to", value: to)]
        var request = URLRequest(url: url.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        let region = Prefs.translatorRegion.trimmingCharacters(in: .whitespaces)
        if !region.isEmpty && region.lowercased() != "global" {
            request.setValue(region, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [["Text": text]])

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
