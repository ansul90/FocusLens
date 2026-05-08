import Foundation

// MARK: - Protocol

/// A single tool the agent can invoke. All tools are read-only.
protocol AgentTool: Sendable {
    /// The name the LLM uses to invoke this tool (snake_case, no spaces).
    var name: String { get }

    /// One-sentence description shown to the LLM in the system prompt.
    var description: String { get }

    /// Human-readable argument schema shown to the LLM in the system prompt.
    /// Format: comma-separated `argName: type` pairs with a description.
    var argsDescription: String { get }

    /// Execute the tool with the provided args dict.
    /// Always returns a JSON string — on failure returns {"error": "..."}.
    func run(args: [String: Any]) async -> String
}

// MARK: - Registry

/// Thread-safe registry of all available agent tools.
actor ToolRegistry {
    private var tools: [String: any AgentTool]

    /// Creates an empty registry. Use `register(_:)` to add tools afterwards.
    init() {
        tools = [:]
    }

    /// Creates a pre-populated registry. All tools are registered before any
    /// caller can observe the registry, eliminating the startup race where the
    /// agent's system prompt would list no tools.
    init(tools: [any AgentTool]) {
        self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    }

    func register(_ tool: any AgentTool) {
        tools[tool.name] = tool
    }

    func get(_ name: String) -> (any AgentTool)? {
        tools[name]
    }

    func all() -> [any AgentTool] {
        tools.values.sorted { $0.name < $1.name }
    }

    /// Generates the tools section of the system prompt, optionally excluding named tools.
    func systemPromptSection(excluding hidden: Set<String> = []) -> String {
        let sorted = tools.values
            .filter { !hidden.contains($0.name) }
            .sorted { $0.name < $1.name }
        let descriptions = sorted.enumerated().map { idx, tool in
            """
            \(idx + 1). \(tool.name)
               Args: \(tool.argsDescription)
               \(tool.description)
            """
        }
        return descriptions.joined(separator: "\n\n")
    }
}

// MARK: - Helpers

/// Encode any value as a compact JSON string for returning from tools.
func toolJSON(_ value: some Encodable) -> String {
    guard let data = try? JSONEncoder().encode(value),
          let str = String(data: data, encoding: .utf8) else {
        return #"{"error":"encoding failed"}"#
    }
    let truncated = str.count > AppConstants.Agent.toolResultMaxChars
        ? String(str.prefix(AppConstants.Agent.toolResultMaxChars)) + "...}"
        : str
    return truncated
}

func toolError(_ message: String) -> String {
    #"{"error":"\#(message.replacingOccurrences(of: "\"", with: "'"))"}"#
}
