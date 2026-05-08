import Foundation
import Observation
import os

// MARK: - Conversation entry

struct ConversationEntry: Identifiable, Sendable {
    enum Sender: Sendable { case user, agent }
    let id: UUID
    let sender: Sender
    let text: String
    let trace: [TraceStep]

    init(sender: Sender, text: String, trace: [TraceStep] = []) {
        self.id = UUID()
        self.sender = sender
        self.text = text
        self.trace = trace
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class AskViewModel {
    private(set) var entries: [ConversationEntry] = []
    private(set) var isRunning: Bool = false
    private(set) var ollamaAvailable: Bool = false
    private(set) var statusMessage: String = "Checking Ollama..."
    var inputText: String = ""

    private let runner: AgentRunner
    private let ollamaClient: OllamaClient
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "AskViewModel")

    // Rolling history: last 2 user+answer pairs, prepended to each new ask() call
    // so follow-up questions retain context (e.g. date, previously-mentioned apps)
    private var conversationHistory: [AgentMessage] = []
    private static let maxHistoryPairs = 2

    static let sampleQueries = [
        "Top apps today",
        "Productivity score yesterday",
        "How much time on Development this week?",
        "Compare today vs yesterday",
        "What was I doing at 3pm today?"
    ]

    init(runner: AgentRunner, ollamaClient: OllamaClient) {
        self.runner = runner
        self.ollamaClient = ollamaClient
    }

    // MARK: - Lifecycle

    func startMCP() async {
        do {
            try await MCPClient.shared.start()
            let tools = await MCPClient.shared.agentTools()
            // Only register render_report from MCP — the data tools are covered natively.
            let filtered = tools.filter { $0.name == "render_report" }
            for tool in filtered {
                await runner.register(tool)
            }
            logger.info("MCP: registered \(filtered.count) tool(s) (render_report only)")
        } catch {
            logger.error("MCP startup failed: \(error.localizedDescription)")
        }
    }

    func checkAvailability() async {
        let available = await ollamaClient.isAvailable()
        ollamaAvailable = available
        if available {
            let settings = OllamaSettings()
            statusMessage = "Connected to \(settings.modelName)"
        } else {
            statusMessage = "Ollama not running"
        }
    }

    // MARK: - Send

    func send() async {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isRunning else { return }

        inputText = ""
        isRunning = true
        entries.append(ConversationEntry(sender: .user, text: query))

        defer { isRunning = false }

        let priorContext = conversationHistory

        do {
            let result = try await runner.ask(query, priorContext: priorContext)
            entries.append(ConversationEntry(sender: .agent, text: result.answer, trace: result.trace))

            // Append this exchange to rolling history. Use a compact summary of the tool result
            // (not the full JSON) so the context stays small enough for the local model to handle.
            conversationHistory.append(AgentMessage(role: .user, content: query))

            let summary = compactToolSummary(from: result.trace)
            if !summary.isEmpty {
                conversationHistory.append(AgentMessage(role: .tool, content: summary))
            }
            conversationHistory.append(AgentMessage(role: .assistant, content: result.answer))

            // Keep only the last N pairs (each pair = user + optional tool + assistant = up to 3 messages)
            let maxMessages = Self.maxHistoryPairs * 3
            if conversationHistory.count > maxMessages {
                conversationHistory = Array(conversationHistory.suffix(maxMessages))
            }
        } catch AgentError.ollamaUnavailable {
            ollamaAvailable = false
            statusMessage = "Ollama not running"
            entries.append(ConversationEntry(sender: .agent,
                text: "Ollama is not running. Start it with `ollama serve`, then try again."))
        } catch AgentError.modelNotFound(let name) {
            ollamaAvailable = false
            statusMessage = "Model '\(name)' not found"
            entries.append(ConversationEntry(sender: .agent,
                text: "Model '\(name)' was not found in Ollama. Go to Settings → AI → Local AI and update the model name to match what you have installed (e.g. gemma4:26b-a4b-it-q4_K_M). You can use 'Test Ollama' to see available models."))
        } catch AgentError.maxIterationsReached {
            entries.append(ConversationEntry(sender: .agent,
                text: "I wasn't able to fully answer that question in time. Try rephrasing or breaking it into smaller parts."))
        } catch {
            entries.append(ConversationEntry(sender: .agent,
                text: "Something went wrong: \(error.localizedDescription)"))
        }
    }

    func sendSample(_ text: String) async {
        inputText = text
        await send()
    }

    func clear() {
        entries.removeAll()
        conversationHistory.removeAll()
    }

    // MARK: - History compression

    /// Build a short summary of what tool was called and its key data,
    /// keeping the rolling context tiny enough that the local model doesn't degrade.
    private func compactToolSummary(from trace: [TraceStep]) -> String {
        // Find the last tool call
        guard let lastStep = trace.reversed().first(where: {
            if case .toolCall = $0.kind { return true }
            return false
        }), case .toolCall(let toolName, let args, let result) = lastStep.kind else {
            return ""
        }

        // Try to extract the most identifying piece of data from the result
        let resultData = result.data(using: .utf8)
        let parsed = resultData.flatMap { try? JSONSerialization.jsonObject(with: $0) }

        var summary = "Called \(toolName)"
        let argsStr = args.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        if !argsStr.isEmpty {
            summary += " with [\(argsStr)]"
        }

        // Add a one-line data summary specific to each tool
        if let dict = parsed as? [String: Any] {
            switch toolName {
            case "get_activity":
                if let score = dict["score"] as? Int, let totalMins = dict["total_active_minutes"] as? Double {
                    let apps = (dict["top_apps"] as? [[String: Any]])?
                        .prefix(5).compactMap { $0["app"] as? String }.joined(separator: ", ") ?? ""
                    summary += ". Result: score=\(score)/100, \(Int(totalMins))m active, top apps: \(apps)"
                }
            case "classify_app":
                if let appName = dict["app_name"] as? String, let verdict = dict["verdict"] as? String {
                    summary += ". Result: \(appName)=\(verdict)"
                }
            case "current_time":
                if let today = dict["today"] as? String {
                    summary += ". Result: today=\(today)"
                }
            case "query_sessions":
                if let count = dict["count"] as? Int {
                    summary += ". Result: \(count) sessions"
                }
            default:
                break
            }
        }

        return summary
    }
}
