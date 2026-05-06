import Testing
import Foundation
@testable import FocusLens

// MARK: - Dedicated stub for AgentRunner tests (avoids shared static with GeminiClientTests)

final class AgentStubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = AgentStubURLProtocol.handler else {
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

// MARK: - Scripted session builder for AgentRunner tests

private func makeScriptedAgentSession(responses: [String]) -> URLSession {
    var remaining = responses
    AgentStubURLProtocol.handler = { req in
        let url = req.url!
        if req.httpMethod == "GET" {
            // Health check: always say gemma4 is available
            let tagsData = #"{"models":[{"name":"gemma4:latest"}]}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, tagsData)
        }
        // Generate call
        let response = remaining.isEmpty ? #"{"answer":"fallback"}"# : remaining.removeFirst()
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                agentGenerateData(response))
    }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AgentStubURLProtocol.self]
    return URLSession(configuration: config)
}

private func agentGenerateData(_ response: String) -> Data {
    let escaped = response
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    return #"{"model":"gemma4","response":"\#(escaped)","done":true}"#.data(using: .utf8)!
}

private func makeRegistry() -> ToolRegistry {
    ToolRegistry(tools: [CurrentTimeTool()])
}

private func makeAgentOllamaSettings() -> OllamaSettings {
    let defaults = UserDefaults(suiteName: "AgentRunnerTests-\(UUID())")!
    var s = OllamaSettings(defaults: defaults)
    s.host = "http://localhost:11434"
    s.modelName = "gemma4"
    s.isEnabled = true
    return s
}

// MARK: - AgentRunner Tests

@Suite("AgentRunner", .serialized)
struct AgentRunnerTests {

    @Test("returns answer from single-turn response")
    func returnsSingleTurnAnswer() async throws {
        let session = makeScriptedAgentSession(responses: [#"{"answer":"Today is great!"}"#])
        defer { AgentStubURLProtocol.handler = nil }

        let client = OllamaClient(settings: makeAgentOllamaSettings(), session: session)
        let registry = makeRegistry()
        let runner = AgentRunner(llm: client, registry: registry)

        let result = try await runner.ask("How is today?")
        #expect(result.answer == "Today is great!")
        #expect(result.trace.count == 1)
    }

    @Test("calls tool then returns answer in multi-turn")
    func callsToolThenReturnsAnswer() async throws {
        let session = makeScriptedAgentSession(responses: [
            #"{"tool_name":"current_time","tool_arguments":{}}"#,
            #"{"answer":"Today is 2026-04-24"}"#
        ])
        defer { AgentStubURLProtocol.handler = nil }

        let client = OllamaClient(settings: makeAgentOllamaSettings(), session: session)
        let registry = makeRegistry()
        let runner = AgentRunner(llm: client, registry: registry)

        let result = try await runner.ask("What is today's date?")
        #expect(result.answer == "Today is 2026-04-24")
        // trace: llmRaw(tool call) + toolCall + llmRaw(answer)
        #expect(result.trace.count == 3)
    }

    @Test("throws maxIterationsReached when LLM never returns answer")
    func throwsMaxIterations() async throws {
        let repeated = Array(repeating: #"{"tool_name":"current_time","tool_arguments":{}}"#, count: 10)
        let session = makeScriptedAgentSession(responses: repeated)
        defer { AgentStubURLProtocol.handler = nil }

        let client = OllamaClient(settings: makeAgentOllamaSettings(), session: session)
        let registry = makeRegistry()
        let runner = AgentRunner(llm: client, registry: registry)

        let error = try await #require(throws: (any Error).self) {
            try await runner.ask("loop forever")
        }
        guard case AgentError.maxIterationsReached = error else {
            Issue.record("Expected AgentError.maxIterationsReached, got \(error)")
            return
        }
    }

    @Test("recovers from unparseable JSON then continues")
    func recoversFromUnparseableJSON() async throws {
        let session = makeScriptedAgentSession(responses: [
            "not valid json at all",
            #"{"answer":"Recovered fine"}"#
        ])
        defer { AgentStubURLProtocol.handler = nil }

        let client = OllamaClient(settings: makeAgentOllamaSettings(), session: session)
        let registry = makeRegistry()
        let runner = AgentRunner(llm: client, registry: registry)

        let result = try await runner.ask("can you answer?")
        #expect(result.answer == "Recovered fine")
    }

    @Test("handles unknown tool gracefully")
    func handlesUnknownTool() async throws {
        let session = makeScriptedAgentSession(responses: [
            #"{"tool_name":"nonexistent_tool","tool_arguments":{}}"#,
            #"{"answer":"I used another approach"}"#
        ])
        defer { AgentStubURLProtocol.handler = nil }

        let client = OllamaClient(settings: makeAgentOllamaSettings(), session: session)
        let registry = makeRegistry()
        let runner = AgentRunner(llm: client, registry: registry)

        let result = try await runner.ask("test")
        #expect(result.answer == "I used another approach")
    }
}

