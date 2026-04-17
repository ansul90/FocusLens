import Foundation

// MARK: - Error

enum GeminiError: Error, Sendable {
    case missingKey
    case httpStatus(Int)
    case invalidResponse
    case decoding(Error)
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
        // 1. Guard: key must be present
        guard settings.hasValidKey else { throw GeminiError.missingKey }
        let apiKey = settings.apiKey

        // 2. Build URL: {endpointBase}/{modelName}:generateContent?key={apiKey}
        let urlString = "\(AppConstants.AI.endpointBase)/\(AppConstants.AI.modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw GeminiError.invalidResponse }

        // 3. Build request body
        // Gemini REST body shape:
        // {
        //   "system_instruction": { "parts": [{ "text": "<system prompt>" }] },
        //   "contents": [{ "parts": [{ "text": "<user message>" }] }],
        //   "generationConfig": { "responseMimeType": "application/json", "temperature": 0.0 }
        // }
        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": GeminiPrompt.system]]
            ],
            "contents": [
                ["parts": [["text": GeminiPrompt.user(for: input)]]]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.0
            ]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw GeminiError.invalidResponse
        }

        // 4. Configure request
        var request = URLRequest(
            url: url,
            timeoutInterval: AppConstants.AI.requestTimeoutSeconds
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        // 5. Execute
        let (data, response) = try await session.data(for: request)

        // 6. Check HTTP status
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw GeminiError.httpStatus(httpResponse.statusCode)
        }

        // 7. Extract inner text from Gemini envelope
        // Envelope shape: { "candidates": [{ "content": { "parts": [{ "text": "<json string>" }] } }] }
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

        // 8. Decode inner JSON as GeminiBatchResponse
        do {
            return try JSONDecoder().decode(GeminiBatchResponse.self, from: innerData)
        } catch {
            throw GeminiError.decoding(error)
        }
    }
}
