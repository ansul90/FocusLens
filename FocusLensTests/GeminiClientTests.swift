import Testing
import Foundation
@testable import FocusLens

// MARK: - URLProtocol stub

final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeSettings(key: String = "test-key", enabled: Bool = true) -> GeminiSettings {
    let defaults = UserDefaults(suiteName: "GeminiClientTests-\(UUID())")!
    var s = GeminiSettings(defaults: defaults)
    s.apiKey = key
    s.isEnabled = enabled
    return s
}

private func geminiEnvelope(innerJSON: String) -> Data {
    let json = """
    {
      "candidates": [{
        "content": {
          "parts": [{"text": \(innerJSON)}]
        }
      }]
    }
    """
    return json.data(using: .utf8)!
}

private func okResponse(for url: URL) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
}

// MARK: - Tests

// Serialized because StubURLProtocol.handler is a shared static — prevents races between tests.
@Suite("GeminiClient", .serialized)
struct GeminiClientTests {

    @Test("throws missingKey when settings has no key")
    func throwsMissingKeyWhenNoKey() async throws {
        StubURLProtocol.handler = nil
        let settings = makeSettings(key: "", enabled: true)
        let client = GeminiClient(settings: settings, session: makeSession())
        let batch = GeminiBatchRequest(items: [.init(id: 0, title: "test")])
        let error = try await #require(throws: (any Error).self) {
            try await client.classify(batch)
        }
        if case GeminiError.missingKey = error { } else {
            Issue.record("Expected GeminiError.missingKey, got \(error)")
        }
    }

    @Test("throws missingKey when disabled")
    func throwsMissingKeyWhenDisabled() async throws {
        StubURLProtocol.handler = nil
        let settings = makeSettings(key: "valid-key", enabled: false)
        let client = GeminiClient(settings: settings, session: makeSession())
        let batch = GeminiBatchRequest(items: [.init(id: 0, title: "test")])
        let error = try await #require(throws: (any Error).self) {
            try await client.classify(batch)
        }
        if case GeminiError.missingKey = error { } else {
            Issue.record("Expected GeminiError.missingKey, got \(error)")
        }
    }

    @Test("throws httpStatus on 4xx response")
    func throwsHttpStatusOn4xx() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { StubURLProtocol.handler = nil }
        let client = GeminiClient(settings: makeSettings(), session: makeSession())
        let batch = GeminiBatchRequest(items: [.init(id: 0, title: "test")])
        let error = try await #require(throws: (any Error).self) {
            try await client.classify(batch)
        }
        if case GeminiError.httpStatus(401) = error { } else {
            Issue.record("Expected GeminiError.httpStatus(401), got \(error)")
        }
    }

    @Test("throws invalidResponse on malformed envelope")
    func throwsInvalidResponseOnMalformedEnvelope() async throws {
        StubURLProtocol.handler = { request in
            let response = okResponse(for: request.url!)
            return (response, "not json".data(using: .utf8)!)
        }
        defer { StubURLProtocol.handler = nil }
        let client = GeminiClient(settings: makeSettings(), session: makeSession())
        let batch = GeminiBatchRequest(items: [.init(id: 0, title: "test")])
        let error = try await #require(throws: (any Error).self) {
            try await client.classify(batch)
        }
        if case GeminiError.invalidResponse = error { } else {
            Issue.record("Expected GeminiError.invalidResponse, got \(error)")
        }
    }

    @Test("decodes valid response correctly")
    func decodesValidResponse() async throws {
        // The inner text value must be a JSON-encoded string (Gemini wraps the response JSON in a string)
        let innerText = #"{"classifications":[{"id":0,"category":"Development","tier":2}]}"#
        let innerJSONValue = try String(data: JSONEncoder().encode(innerText), encoding: .utf8)!
        StubURLProtocol.handler = { request in
            let response = okResponse(for: request.url!)
            return (response, geminiEnvelope(innerJSON: innerJSONValue))
        }
        defer { StubURLProtocol.handler = nil }
        let client = GeminiClient(settings: makeSettings(), session: makeSession())
        let batch = GeminiBatchRequest(items: [.init(id: 0, title: "GitHub")])
        let result = try await client.classify(batch)
        #expect(result.classifications.count == 1)
        #expect(result.classifications[0].category == "Development")
        #expect(result.classifications[0].tier == 2)
    }

    @Test("throws decoding on bad inner JSON")
    func throwsDecodingOnBadInnerJSON() async throws {
        let innerText = #"{"bad":"data"}"#
        let innerJSONValue = try String(data: JSONEncoder().encode(innerText), encoding: .utf8)!
        StubURLProtocol.handler = { request in
            let response = okResponse(for: request.url!)
            return (response, geminiEnvelope(innerJSON: innerJSONValue))
        }
        defer { StubURLProtocol.handler = nil }
        let client = GeminiClient(settings: makeSettings(), session: makeSession())
        let batch = GeminiBatchRequest(items: [.init(id: 0, title: "test")])
        let error = try await #require(throws: (any Error).self) {
            try await client.classify(batch)
        }
        if case GeminiError.decoding = error { } else {
            Issue.record("Expected GeminiError.decoding, got \(error)")
        }
    }
}
