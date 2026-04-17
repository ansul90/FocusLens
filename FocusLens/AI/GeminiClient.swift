import Foundation

// MARK: - Error

enum GeminiError: Error, Sendable {
    case missingKey
    case httpStatus(Int)
    case invalidResponse
    case decoding(Error)
}

// MARK: - Typed request envelope (avoids untyped [String: Any] body)

private struct GeminiRequestEnvelope: Encodable {
    struct Part: Encodable { let text: String }
    struct Content: Encodable { let parts: [Part] }
    struct SystemInstruction: Encodable { let parts: [Part] }
    struct GenerationConfig: Encodable {
        let responseMimeType: String
        let temperature: Double
    }
    let system_instruction: SystemInstruction
    let contents: [Content]
    let generationConfig: GenerationConfig
}

// MARK: - Actor

actor GeminiClient {
    private let settings: GeminiSettings
    private let session: URLSession

    init(settings: GeminiSettings = GeminiSettings(), session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    func classify(_ input: GeminiBatchRequest) async throws -> GeminiBatchResponse {
        // Snapshot key once to avoid TOCTOU across hasValidKey / apiKey reads.
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.isEnabled && !apiKey.isEmpty else { throw GeminiError.missingKey }

        let urlString = "\(AppConstants.AI.endpointBase)/\(AppConstants.AI.modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw GeminiError.invalidResponse }

        let envelope = GeminiRequestEnvelope(
            system_instruction: .init(parts: [.init(text: GeminiPrompt.system)]),
            contents: [.init(parts: [.init(text: GeminiPrompt.user(for: input))])],
            generationConfig: .init(responseMimeType: "application/json", temperature: 0.0)
        )
        let bodyData = try JSONEncoder().encode(envelope)

        var request = URLRequest(url: url, timeoutInterval: AppConstants.AI.requestTimeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw GeminiError.httpStatus(httpResponse.statusCode)
        }

        // Extract inner JSON string from Gemini envelope:
        // { "candidates": [{ "content": { "parts": [{ "text": "<json>" }] } }] }
        guard
            let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = envelope["candidates"] as? [[String: Any]],
            let firstCandidate = candidates.first,
            let content = firstCandidate["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String,
            let innerData = text.data(using: .utf8)
        else {
            throw GeminiError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(GeminiBatchResponse.self, from: innerData)
        } catch {
            throw GeminiError.decoding(error)
        }
    }
}
