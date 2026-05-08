import Foundation
import GRDB
import os

// MARK: - Message model

struct AgentMessage: Identifiable, Sendable {
    enum Role: Sendable { case user, assistant, tool }
    let id: UUID
    let role: Role
    let content: String

    init(role: Role, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
    }
}

// MARK: - Trace step (for debug UI)

struct TraceStep: Identifiable, Sendable {
    enum Kind: Sendable {
        case llmRaw(String)
        case toolCall(name: String, args: [String: Any], result: String)
        case parseError(String)
    }
    let id: UUID
    let kind: Kind

    init(_ kind: Kind) { self.id = UUID(); self.kind = kind }
}

// MARK: - Agent result

struct AgentResult: Sendable {
    let answer: String
    let trace: [TraceStep]
}

// MARK: - Errors

enum AgentError: Error, Sendable {
    case ollamaUnavailable
    case modelNotFound(String)
    case maxIterationsReached
    case unparseable(String)
}

// MARK: - AgentRunner

actor AgentRunner {
    private let llm: OllamaClient
    private let registry: ToolRegistry
    private let dbPool: DatabasePool
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "AgentRunner")

    init(llm: OllamaClient = OllamaClient(), registry: ToolRegistry, dbPool: DatabasePool = DatabaseManager.shared.dbPool) {
        self.llm = llm
        self.registry = registry
        self.dbPool = dbPool
    }

    // MARK: - Public API

    func register(_ tool: any AgentTool) async {
        await registry.register(tool)
    }

    func ask(_ userQuery: String, priorContext: [AgentMessage] = []) async throws -> AgentResult {
        guard await llm.isAvailable() else { throw AgentError.ollamaUnavailable }

        let systemPrompt = await SystemPrompt.build(registry: registry, dbPool: dbPool)
        var messages: [AgentMessage] = priorContext + [
            AgentMessage(role: .user, content: userQuery)
        ]
        var trace: [TraceStep] = []
        var lastToolCall: String? = nil
        var nudgedToAnswer = false

        let logFile = AgentLogger(query: userQuery)
        logFile.write("Query: \(userQuery)\n")

        for iteration in 0..<AppConstants.Agent.maxIterations {
            logger.debug("AgentRunner: iteration \(iteration + 1)/\(AppConstants.Agent.maxIterations)")

            let prompt = buildPrompt(system: systemPrompt, messages: messages)

            let rawResponse: String
            do {
                rawResponse = try await llm.generate(prompt: prompt, jsonMode: true)
            } catch OllamaError.unreachable {
                throw AgentError.ollamaUnavailable
            } catch OllamaError.modelNotFound(let name) {
                throw AgentError.modelNotFound(name)
            }
            trace.append(TraceStep(.llmRaw(rawResponse)))
            logger.debug("AgentRunner: LLM raw: \(rawResponse.prefix(200))")
            logFile.write("\n→ LLM (iteration \(iteration + 1)): \(rawResponse)")

            let parsed: ParsedResponse
            do {
                parsed = try ResponseParser.parse(rawResponse)
            } catch {
                logger.warning("AgentRunner: parse error: \(error.localizedDescription)")
                trace.append(TraceStep(.parseError(rawResponse)))
                messages.append(AgentMessage(role: .assistant, content: rawResponse))
                messages.append(AgentMessage(role: .tool,
                    content: #"{"error":"Invalid JSON response. Respond ONLY with a JSON object, no markdown, no extra text."}"#))
                continue
            }

            if let answer = parsed.answer {
                logger.info("AgentRunner: completed in \(iteration + 1) iterations")
                logFile.write("\n\n✓ Final Answer: \(answer)\n")
                return AgentResult(answer: answer, trace: trace)
            }

            // If we already nudged this model to answer and it still won't, synthesize from trace
            if nudgedToAnswer {
                logger.warning("AgentRunner: model ignored nudge, synthesizing answer from last tool result")
                let lastToolStep = trace.last(where: {
                    if case .toolCall = $0.kind { return true }
                    return false
                })
                let synthesized: String
                if let step = lastToolStep,
                   case .toolCall(let name, _, let result) = step.kind {
                    synthesized = formatFallbackAnswer(toolName: name, jsonResult: result)
                } else {
                    synthesized = "No data available for that query."
                }
                logFile.write("\n\n✓ Synthesized Answer: \(synthesized)\n")
                return AgentResult(answer: synthesized, trace: trace)
            }

            guard let toolName = parsed.toolName else {
                messages.append(AgentMessage(role: .assistant, content: rawResponse))
                messages.append(AgentMessage(role: .tool,
                    content: #"{"error":"Response missing both 'answer' and 'tool_name' keys."}"#))
                continue
            }

            guard let tool = await registry.get(toolName) else {
                let available = await registry.all().map(\.name).joined(separator: ", ")
                let err = #"{"error":"Unknown tool '\#(toolName)'. Available tools: \#(available)"}"#
                trace.append(TraceStep(.toolCall(name: toolName, args: [:], result: err)))
                messages.append(AgentMessage(role: .assistant, content: rawResponse))
                messages.append(AgentMessage(role: .tool, content: err))
                continue
            }

            // Detect repeat tool call: track by tool name + args (not full raw response)
            // to catch semantically identical calls regardless of JSON key ordering.
            let args = ResponseParser.extractArgs(from: parsed.rawArgs, toolName: toolName)
            let argsKey = args.keys.sorted().map { "\($0)=\(args[$0] ?? "")" }.joined(separator: ",")
            let toolCallKey = "\(toolName):\(argsKey)"
            if toolCallKey == lastToolCall {
                logger.warning("AgentRunner: detected repeat tool call '\(toolName)', nudging to answer")
                messages.append(AgentMessage(role: .assistant, content: rawResponse))
                messages.append(AgentMessage(role: .tool,
                    content: """
                    {"info":"You already called \(toolName) and received the data. \
                    Stop calling tools. \
                    Respond NOW with {\"answer\": \"<your plain English summary of the data>\"}. \
                    DO NOT call any tool. Write the answer in plain English."}
                    """))
                lastToolCall = nil
                nudgedToAnswer = true
                continue
            }
            lastToolCall = toolCallKey
            nudgedToAnswer = false

            logger.debug("AgentRunner: calling tool '\(toolName)' args=\(args)")

            let result = await tool.run(args: args)
            trace.append(TraceStep(.toolCall(name: toolName, args: args, result: result)))
            logger.debug("AgentRunner: tool result: \(result.prefix(200))")
            logFile.write("\n   Tool Result (\(toolName)): \(result)")

            messages.append(AgentMessage(role: .assistant, content: rawResponse))
            // toolJSON already truncates at AppConstants.Agent.toolResultMaxChars with valid JSON
            messages.append(AgentMessage(role: .tool, content: result))
        }

        logger.warning("AgentRunner: max iterations reached")
        throw AgentError.maxIterationsReached
    }

    // MARK: - Prompt rendering

    private func buildPrompt(system: String, messages: [AgentMessage]) -> String {
        var parts: [String] = [system, ""]
        for msg in messages {
            switch msg.role {
            case .user: parts.append("User: \(msg.content)")
            case .assistant: parts.append("Assistant: \(msg.content)")
            case .tool: parts.append("Tool Result: \(msg.content)")
            }
        }
        parts.append("Assistant:")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Fallback answer formatter

    /// Converts a raw tool JSON result into a readable English sentence.
    /// Used when the model refuses to format the data itself.
    private func formatFallbackAnswer(toolName: String, jsonResult: String) -> String {
        guard let data = jsonResult.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "I retrieved data but couldn't format it. Raw: \(jsonResult.prefix(300))"
        }

        switch toolName {
        case "get_activity":
            let range = json["date_range"] as? String ?? "the selected period"
            if let score = json["score"] as? Int,
               let totalMins = json["total_active_minutes"] as? Double {
                let h = Int(totalMins / 60), m = Int(totalMins.truncatingRemainder(dividingBy: 60))
                let dur = h > 0 ? "\(h)h \(m)m" : "\(m)m"
                var lines = "Productivity score: \(score)/100, active time: \(dur)"
                if let apps = json["top_apps"] as? [[String: Any]] {
                    let appList = apps.prefix(5).compactMap { app -> String? in
                        guard let name = app["app"] as? String, let mins = app["minutes"] as? Double else { return nil }
                        return "\(name) (\(Int(mins))m)"
                    }.joined(separator: ", ")
                    lines += "\nTop apps: \(appList)"
                }
                return "For \(range): \(lines)"
            }

        case "classify_app":
            if let appName = json["app_name"] as? String,
               let verdict = json["verdict"] as? String {
                let summary = json["summary"] as? String ?? ""
                let cached = json["cached"] as? Bool ?? false
                return "\(appName) is classified as \(verdict)\(summary.isEmpty ? "" : " — \(summary)")\(cached ? " (cached)" : "")."
            }

        case "query_sessions":
            if let sessions = json["sessions"] as? [[String: Any]] {
                let date = json["date"] as? String ?? "the selected date"
                let count = json["count"] as? Int ?? sessions.count
                if count == 0 { return "No sessions found for \(date)." }
                let lines = sessions.prefix(5).compactMap { s -> String? in
                    guard let app = s["app"] as? String else { return nil }
                    let title = s["window_title"] as? String ?? ""
                    let mins = s["duration_minutes"] as? Double ?? 0
                    return "• \(app)\(title.isEmpty ? "" : " — \(title)") (\(Int(mins))m)"
                }.joined(separator: "\n")
                return "Sessions on \(date) (\(count) total):\n\(lines)"
            }

        default:
            break
        }
        return "I retrieved the data but couldn't summarize it. Raw: \(jsonResult.prefix(400))"
    }
}

// MARK: - Default tools factory

extension AgentRunner {
    /// Returns all built-in query tools. Used to pre-populate a ToolRegistry at
    /// construction time, eliminating the async-registration race on app startup.
    static func defaultTools() -> [any AgentTool] {
        [
            CurrentTimeTool(),
            GetActivityTool(),
            QuerySessionsTool(),
            ClassifyAppTool(),
        ]
    }
}

// MARK: - Agent Logger

/// Writes a human-readable LLM interaction log to ~/Desktop/focuslens-agent-log.txt.
/// Each query appends a new section so the file accumulates all demo runs.
final class AgentLogger: @unchecked Sendable {
    private let path: String

    init(query: String) {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        path = desktop.appendingPathComponent("focuslens-agent-log.txt").path

        let separator = "\n" + String(repeating: "─", count: 60) + "\n"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        write(separator + "[\(timestamp)]\n")
    }

    func write(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: path),
           let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}
