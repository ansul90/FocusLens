import Foundation

// MARK: - Parsed LLM turn

struct ParsedResponse {
    let answer: String?
    let toolName: String?
    let rawArgs: [String: Any]

    var isAnswer: Bool { answer != nil }
    var isTool: Bool { toolName != nil }
}

// MARK: - Parser

enum ResponseParser {

    /// Extracts a JSON object from raw LLM text, tolerating markdown fences and whitespace.
    static func parse(_ text: String) throws -> ParsedResponse {
        let cleaned = stripMarkdownFences(text)

        // Attempt direct parse, then fallback regex extraction
        let dict: [String: Any]
        if let d = try? JSONSerialization.jsonObject(with: Data(cleaned.utf8)) as? [String: Any] {
            dict = d
        } else if let match = cleaned.range(of: #"\{[\s\S]*\}"#, options: .regularExpression),
                  let d = try? JSONSerialization.jsonObject(with: Data(cleaned[match].utf8)) as? [String: Any] {
            dict = d
        } else {
            throw AgentError.unparseable(cleaned)
        }

        if let raw = dict["answer"] as? String {
            let answer = truncateAnswer(raw)
            return ParsedResponse(answer: answer, toolName: nil, rawArgs: dict)
        }

        let toolName = dict["tool_name"] as? String ?? dict["name"] as? String
        return ParsedResponse(answer: nil, toolName: toolName, rawArgs: dict)
    }

    /// Extracts tool arguments from a parsed dict with forgiving key lookup.
    /// Local models (gemma, llama) are notoriously sloppy about argument key names.
    static func extractArgs(from dict: [String: Any], toolName: String) -> [String: Any] {
        let candidateKeys = [
            "tool_arguments", "tool_args", "arguments", "args",
            "parameters", "params", "tool_agents", "input", "inputs"
        ]

        for key in candidateKeys {
            if let value = dict[key] {
                if let d = value as? [String: Any] { return d }
                // Raw string/number at this key — wrap it if the tool has one param
                if let scalar = value as? String { return ["value": scalar] }
                if let scalar = value as? Int { return ["value": scalar] }
            }
        }

        // Nothing matched — look for top-level siblings of tool_name / answer / name
        let reserved: Set<String> = ["tool_name", "answer", "name", "thought", "reasoning"]
        let siblings = dict.filter { !reserved.contains($0.key) }
        if !siblings.isEmpty { return siblings }

        return [:]
    }

    // MARK: - Private

    /// Caps answer length and detects token-repetition loops (local models occasionally
    /// repeat the same word/phrase hundreds of times before generating a stop token).
    private static func truncateAnswer(_ text: String) -> String {
        let maxChars = 800
        guard text.count > maxChars else { return text }

        // Hard cap — take the first complete sentence within the limit if possible.
        let prefix = String(text.prefix(maxChars))
        if let lastSentence = prefix.range(of: #"[.!?][^.!?]*$"#, options: .regularExpression) {
            return String(prefix[..<lastSentence.lowerBound]) + "."
        }
        return prefix + "…"
    }

    private static func stripMarkdownFences(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            var lines = t.components(separatedBy: "\n")
            lines.removeFirst()
            if lines.last?.trimmingCharacters(in: .whitespaces) == "```" {
                lines.removeLast()
            }
            t = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("json") { t = String(t.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return t
    }
}
