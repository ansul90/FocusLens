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
    var reportURL: URL?

    init(sender: Sender, text: String, trace: [TraceStep] = [], reportURL: URL? = nil) {
        self.id = UUID()
        self.sender = sender
        self.text = text
        self.trace = trace
        self.reportURL = reportURL
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
            // Data tools are covered natively; only register UI/narrative MCP tools.
            let mcpToolNames: Set<String> = ["render_report", "summarize_day"]
            let filtered = tools.filter { mcpToolNames.contains($0.name) }
            for tool in filtered {
                await runner.register(tool)
            }
            logger.info("MCP: registered \(filtered.count) tool(s): \(filtered.map(\.name).joined(separator: ", "))")
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
            // Post-answer: Swift builds the render_report payload from trace data and calls MCP.
            // The LLM never sees render_report — this makes the MCP call reliable.
            let entryIdx = entries.count - 1
            if let reportURL = await tryRenderReport(from: result.trace, query: query) {
                entries[entryIdx].reportURL = reportURL
            }

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

    // MARK: - MCP report rendering

    /// Builds a render_report call from the agent's trace data and calls it via MCP.
    /// Only triggers when the trace includes a get_activity result.
    /// Returns nil if MCP is not running or the tool call fails.
    private func tryRenderReport(from trace: [TraceStep], query: String) async -> URL? {
        guard await MCPClient.shared.isRunning else {
            logger.debug("tryRenderReport: skipped — MCP not running")
            return nil
        }

        guard let activityStep = trace.reversed().first(where: {
            if case .toolCall(let name, _, _) = $0.kind { return name == "get_activity" }
            return false
        }), case .toolCall(_, _, let resultJSON) = activityStep.kind else {
            logger.debug("tryRenderReport: skipped — no get_activity step in trace")
            return nil
        }

        guard let sections = buildReportSections(from: resultJSON, query: query),
              !sections.isEmpty else {
            logger.warning("tryRenderReport: buildReportSections returned nil/empty — activityJSON: \(resultJSON.prefix(200))")
            return nil
        }

        do {
            let result = try await MCPClient.shared.callTool(
                name: "render_report",
                arguments: ["title": "FocusLens Report", "sections": sections]
            )
            logger.debug("tryRenderReport: render_report raw result: \(result.prefix(300))")
            if let urlStr = (try? JSONSerialization.jsonObject(with: Data(result.utf8)))
                .flatMap({ $0 as? [String: Any] })?["url"] as? String,
               let url = URL(string: urlStr) {
                logger.info("MCP render_report: \(url.absoluteString)")
                return url
            }
            logger.warning("tryRenderReport: no 'url' key in render_report result: \(result.prefix(300))")
        } catch {
            logger.error("render_report MCP call failed: \(error.localizedDescription)")
        }
        return nil
    }

    private func buildReportSections(from activityJSON: String, query: String) -> [[String: Any]]? {
        guard let data = activityJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let score = json["score"] as? Int ?? 0
        let totalMins = json["total_active_minutes"] as? Double ?? 0
        let dateRange = json["date_range"] as? String ?? "this period"
        let topApps = json["top_apps"] as? [[String: Any]] ?? []

        guard !topApps.isEmpty else { return nil }

        var sections: [[String: Any]] = []

        // KPI row
        let h = Int(totalMins / 60), m = Int(totalMins.truncatingRemainder(dividingBy: 60))
        let durStr = h > 0 ? "\(h)h \(m)m" : "\(m)m"
        let scoreTrend = score >= 60 ? "up" : score >= 40 ? "neutral" : "down"
        let scoreSentiment = score >= 60 ? "positive" : score >= 40 ? "neutral" : "negative"
        sections.append([
            "type": "kpi", "label": "Productivity Score",
            "value": "\(score)/100", "description": dateRange,
            "trend": scoreTrend, "trend_sentiment": scoreSentiment
        ])
        sections.append(["type": "kpi", "label": "Active Time", "value": durStr])

        // Bar chart: use hours when any app exceeds 60 min for readable axis values
        let appMins = topApps.prefix(10).compactMap { $0["minutes"] as? Double }
        let useHours = appMins.max().map { $0 > 60 } ?? false
        let chartTitle = useHours ? "Top Apps by Time (hours)" : "Top Apps by Time (min)"
        let chartData: [[String: Any]] = topApps.prefix(10).compactMap { app in
            guard let name = app["app"] as? String,
                  let mins = app["minutes"] as? Double else { return nil }
            let value = useHours ? ((mins / 60 * 10).rounded() / 10) : mins
            var item: [String: Any] = ["label": name, "value": value]
            if let tier = app["tier"] as? Int { item["tier"] = tier }
            return item
        }
        if !chartData.isEmpty {
            sections.append(["type": "bar_chart", "title": chartTitle, "data": chartData])
        }

        // Table with category and tier
        let headers = ["App", "Category", "Time", "Tier"]
        let rows: [[String]] = topApps.prefix(10).compactMap { app in
            guard let name = app["app"] as? String else { return nil }
            return [
                name,
                app["category"] as? String ?? "?",
                formatMinutes(app["minutes"] as? Double ?? 0),
                String(app["tier"] as? Int ?? 0)
            ]
        }
        if !rows.isEmpty {
            sections.append(["type": "table", "title": "App Details", "headers": headers, "rows": rows])
        }

        return sections
    }

    private func formatMinutes(_ mins: Double) -> String {
        guard mins >= 60 else { return "\(Int(mins))m" }
        let h = Int(mins / 60)
        let m = Int(mins.truncatingRemainder(dividingBy: 60))
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    // MARK: - History compression

    /// Build a short summary of what tool was called and its key data,
    /// keeping the rolling context tiny enough that the local model doesn't degrade.
    private func compactToolSummary(from trace: [TraceStep]) -> String {
        let summaries: [String] = trace.compactMap { step in
            guard case .toolCall(let toolName, let args, let result) = step.kind else { return nil }

            let parsed = result.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }

            var summary = "Called \(toolName)"
            let argsStr = args.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            if !argsStr.isEmpty { summary += " with [\(argsStr)]" }

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
                    if let today = dict["today"] as? String { summary += ". Result: today=\(today)" }
                case "query_sessions":
                    if let count = dict["count"] as? Int { summary += ". Result: \(count) sessions" }
                default:
                    break
                }
            }
            return summary
        }
        return summaries.joined(separator: "\n")
    }
}
