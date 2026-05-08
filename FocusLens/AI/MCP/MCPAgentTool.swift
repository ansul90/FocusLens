import Foundation

/// Wraps a discovered MCP tool as an AgentTool so it can be registered
/// in the existing ToolRegistry and called by AgentRunner transparently.
struct MCPAgentTool: AgentTool {
    let name: String
    let description: String
    let argsDescription: String

    private let client: MCPClient

    init(definition: MCPToolDefinition, client: MCPClient = .shared) {
        self.name = definition.name
        self.description = definition.description
        self.argsDescription = definition.argsDescription
        self.client = client
    }

    func run(args: [String: Any]) async -> String {
        do {
            return try await client.callTool(name: name, arguments: args)
        } catch {
            return toolError(error.localizedDescription)
        }
    }
}

// MARK: - Factory

extension MCPClient {
    /// Returns all discovered tools as AgentTool instances ready for ToolRegistry.
    func agentTools() -> [any AgentTool] {
        discoveredTools.map { MCPAgentTool(definition: $0, client: self) }
    }
}
