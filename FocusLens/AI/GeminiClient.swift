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
        let responseSchema: GeminiResponseSchema?
    }
    let system_instruction: SystemInstruction
    let contents: [Content]
    let generationConfig: GenerationConfig
}

// MARK: - Response schema (enum-constrained category)

/// Constrained-output schema for the Gemini /generateContent call.
/// The `category` field carries an `enum` whose values are the live category names,
/// so Gemini's constrained decoding cannot emit a category that doesn't exist in the DB.
struct GeminiResponseSchema: Encodable {
    let type: String
    let properties: Properties
    let required: [String]

    init(allowedCategories: [String]) {
        self.type = "object"
        self.properties = Properties(
            classifications: ClassificationsArray(
                items: ClassificationItem(
                    properties: ClassificationItemProperties(
                        id: SimpleField(type: "integer"),
                        category: EnumField(enumValues: allowedCategories),
                        tier: SimpleField(type: "integer")
                    )
                )
            )
        )
        self.required = ["classifications"]
    }

    struct Properties: Encodable {
        let classifications: ClassificationsArray
    }

    struct ClassificationsArray: Encodable {
        let type: String = "array"
        let items: ClassificationItem
    }

    struct ClassificationItem: Encodable {
        let type: String = "object"
        let properties: ClassificationItemProperties
        let required: [String] = ["id", "category", "tier"]
    }

    struct ClassificationItemProperties: Encodable {
        let id: SimpleField
        let category: EnumField
        let tier: SimpleField
    }

    struct SimpleField: Encodable {
        let type: String
    }

    struct EnumField: Encodable {
        let type: String = "string"
        let enumValues: [String]

        enum CodingKeys: String, CodingKey {
            case type
            case enumValues = "enum"
        }
    }
}

// MARK: - Actor

actor GeminiClient {
    private let settings: GeminiSettings
    private let session: URLSession

    init(settings: GeminiSettings = GeminiSettings(), session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    func classify(
        _ input: GeminiBatchRequest,
        allowedCategories: [String]
    ) async throws -> GeminiBatchResponse {
        // Snapshot key once to avoid TOCTOU across hasValidKey / apiKey reads.
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.isEnabled && !apiKey.isEmpty else { throw GeminiError.missingKey }

        let urlString = "\(AppConstants.AI.endpointBase)/\(AppConstants.AI.modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw GeminiError.invalidResponse }

        let schema: GeminiResponseSchema? = allowedCategories.isEmpty
            ? nil
            : GeminiResponseSchema(allowedCategories: allowedCategories)

        let envelope = GeminiRequestEnvelope(
            system_instruction: .init(parts: [.init(text: GeminiPrompt.systemPrompt(allowedCategories: allowedCategories))]),
            contents: [.init(parts: [.init(text: GeminiPrompt.user(for: input))])],
            generationConfig: .init(
                responseMimeType: "application/json",
                temperature: 0.0,
                responseSchema: schema
            )
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
