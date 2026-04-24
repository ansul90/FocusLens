import Foundation
import os

// MARK: - Errors

enum OllamaError: Error, Sendable {
    case disabled
    case unreachable(String)
    case httpStatus(Int)
    case invalidResponse
    case modelNotFound(String)
}

// MARK: - Wire types

private struct OllamaGenerateRequest: Encodable {
    struct Options: Encodable {
        let temperature: Double
        let num_predict: Int
        let num_ctx: Int
    }
    let model: String
    let prompt: String
    let system: String?
    let stream: Bool
    let format: String?
    let options: Options
}

private struct OllamaGenerateResponse: Decodable {
    let model: String
    let response: String
    let done: Bool
}

private struct OllamaTagsResponse: Decodable {
    struct ModelEntry: Decodable {
        let name: String
    }
    let models: [ModelEntry]
}

// MARK: - Actor

actor OllamaClient {
    private let settings: OllamaSettings
    private let session: URLSession
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "OllamaClient")

    init(settings: OllamaSettings = OllamaSettings(), session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    // MARK: - Availability

    /// Returns true if Ollama is reachable and the configured model is available.
    func isAvailable() async -> Bool {
        guard settings.isEnabled else { return false }
        do {
            let url = settings.baseURL.appendingPathComponent("api/tags")
            var req = URLRequest(url: url, timeoutInterval: AppConstants.Ollama.healthCheckTimeoutSeconds)
            req.httpMethod = "GET"
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            let tags = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            let configuredBase = settings.modelName.lowercased().components(separatedBy: ":").first ?? settings.modelName.lowercased()
            return tags.models.contains { entry in
                let entryBase = entry.name.lowercased().components(separatedBy: ":").first ?? entry.name.lowercased()
                return entryBase == configuredBase
            }
        } catch {
            return false
        }
    }

    /// Returns the list of locally available model names.
    func availableModels() async throws -> [String] {
        let url = settings.baseURL.appendingPathComponent("api/tags")
        var req = URLRequest(url: url, timeoutInterval: AppConstants.Ollama.healthCheckTimeoutSeconds)
        req.httpMethod = "GET"
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw OllamaError.invalidResponse }
            if http.statusCode != 200 { throw OllamaError.httpStatus(http.statusCode) }
            let tags = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            return tags.models.map(\.name)
        } catch let e as OllamaError {
            throw e
        } catch {
            throw OllamaError.unreachable(error.localizedDescription)
        }
    }

    // MARK: - Generation

    /// Send a prompt to the model and return the raw response text.
    /// - Parameters:
    ///   - prompt: The user prompt (will be appended after any system content).
    ///   - system: Optional system instruction prepended to the conversation.
    ///   - jsonMode: When true, forces the model to respond with valid JSON via Ollama's format="json" parameter.
    func generate(prompt: String, system: String? = nil, jsonMode: Bool = true) async throws -> String {
        guard settings.isEnabled else { throw OllamaError.disabled }

        let url = settings.baseURL.appendingPathComponent("api/generate")
        let body = OllamaGenerateRequest(
            model: settings.modelName,
            prompt: prompt,
            system: system,
            stream: false,
            format: jsonMode ? "json" : nil,
            options: .init(temperature: 0.1, num_predict: 1024, num_ctx: 8192)
        )

        let bodyData: Data
        do {
            bodyData = try JSONEncoder().encode(body)
        } catch {
            throw OllamaError.invalidResponse
        }

        var req = URLRequest(url: url, timeoutInterval: AppConstants.Ollama.requestTimeoutSeconds)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyData

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw OllamaError.invalidResponse }

            if http.statusCode == 404 {
                throw OllamaError.modelNotFound(settings.modelName)
            }
            if !(200..<300).contains(http.statusCode) {
                throw OllamaError.httpStatus(http.statusCode)
            }
            let envelope = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
            logger.debug("OllamaClient: model=\(envelope.model) done=\(envelope.done)")
            return envelope.response
        } catch let e as OllamaError {
            throw e
        } catch {
            throw OllamaError.unreachable(error.localizedDescription)
        }
    }
}
