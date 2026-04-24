import Testing
import Foundation
@testable import FocusLens

// MARK: - ResponseParser Tests

@Suite("ResponseParser")
struct ResponseParserTests {

    // MARK: - Happy path

    @Test("parses plain answer JSON")
    func parsesAnswer() throws {
        let parsed = try ResponseParser.parse(#"{"answer":"All done!"}"#)
        #expect(parsed.answer == "All done!")
        #expect(parsed.toolName == nil)
    }

    @Test("parses tool_name with tool_arguments")
    func parsesToolCall() throws {
        let parsed = try ResponseParser.parse(#"{"tool_name":"top_apps","tool_arguments":{"date":"today"}}"#)
        #expect(parsed.toolName == "top_apps")
        #expect(parsed.answer == nil)
    }

    @Test("strips markdown fences with json tag")
    func stripsMarkdownFences() throws {
        let raw = """
        ```json
        {"answer":"Done"}
        ```
        """
        let parsed = try ResponseParser.parse(raw)
        #expect(parsed.answer == "Done")
    }

    @Test("strips plain markdown fences without language tag")
    func stripsPlainMarkdownFences() throws {
        let raw = """
        ```
        {"tool_name":"current_time","tool_arguments":{}}
        ```
        """
        let parsed = try ResponseParser.parse(raw)
        #expect(parsed.toolName == "current_time")
    }

    @Test("falls back to regex extraction when there is surrounding noise")
    func regexFallback() throws {
        let raw = #"Here is my response: {"answer":"test"} hope that helps!"#
        let parsed = try ResponseParser.parse(raw)
        #expect(parsed.answer == "test")
    }

    @Test("throws on completely unparseable input")
    func throwsOnUnparseable() async throws {
        try await #require(throws: (any Error).self) {
            _ = try ResponseParser.parse("not json at all")
        }
    }

    // MARK: - extractArgs key alias tests

    @Test("extracts tool_arguments key")
    func extractsToolArguments() {
        let dict: [String: Any] = [
            "tool_name": "top_apps",
            "tool_arguments": ["date": "today", "limit": 5]
        ]
        let args = ResponseParser.extractArgs(from: dict, toolName: "top_apps")
        #expect(args["date"] as? String == "today")
    }

    @Test("falls back to tool_args alias")
    func extractsToolArgs() {
        let dict: [String: Any] = [
            "tool_name": "top_apps",
            "tool_args": ["date": "today"]
        ]
        let args = ResponseParser.extractArgs(from: dict, toolName: "top_apps")
        #expect(args["date"] as? String == "today")
    }

    @Test("falls back to tool_agents alias (Gemma typo)")
    func extractsToolAgents() {
        let dict: [String: Any] = [
            "tool_name": "top_apps",
            "tool_agents": ["date": "yesterday"]
        ]
        let args = ResponseParser.extractArgs(from: dict, toolName: "top_apps")
        #expect(args["date"] as? String == "yesterday")
    }

    @Test("falls back to top-level siblings when no known key")
    func extractsTopLevelSiblings() {
        let dict: [String: Any] = [
            "tool_name": "top_apps",
            "date": "today",
            "limit": 10
        ]
        let args = ResponseParser.extractArgs(from: dict, toolName: "top_apps")
        #expect(args["date"] as? String == "today")
        #expect(args["limit"] as? Int == 10)
    }

    @Test("returns empty dict when no args found")
    func returnsEmptyDictWhenNoArgs() {
        let dict: [String: Any] = ["tool_name": "current_time"]
        let args = ResponseParser.extractArgs(from: dict, toolName: "current_time")
        #expect(args.isEmpty)
    }
}
