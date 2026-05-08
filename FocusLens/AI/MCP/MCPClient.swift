import Foundation
import os

// MARK: - Errors

enum MCPError: Error, LocalizedError {
    case processLaunchFailed(String)
    case encodingFailed
    case serverError(String)
    case notInitialized
    case noContent

    var errorDescription: String? {
        switch self {
        case .processLaunchFailed(let msg): return "MCP process failed to launch: \(msg)"
        case .encodingFailed:               return "Failed to encode MCP request"
        case .serverError(let msg):         return "MCP server error: \(msg)"
        case .notInitialized:               return "MCP client is not running"
        case .noContent:                    return "MCP tool returned no content"
        }
    }
}

// MARK: - Tool definition

struct MCPToolDefinition: Sendable {
    let name: String
    let description: String
    let argsDescription: String
}

// MARK: - MCPClient

actor MCPClient {
    static let shared = MCPClient()

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var pendingContinuations: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var nextID = 1
    private var lineBuffer = ""
    private(set) var discoveredTools: [MCPToolDefinition] = []
    private(set) var isRunning = false

    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "MCPClient")

    // MARK: - Lifecycle

    func start() async throws {
        guard !isRunning else { return }

        let uvPath = AppConstants.MCP.uvPath
        let serverDir = URL(fileURLWithPath: AppConstants.MCP.serverDirectory)
        let serverScript = AppConstants.MCP.serverScript

        // Pre-flight: give actionable errors before Process.run() produces a cryptic one.
        guard FileManager.default.fileExists(atPath: serverDir.path) else {
            throw MCPError.processLaunchFailed(
                "Server directory not found: \(serverDir.path). " +
                "Set the focuslens-mcp path in Settings → AI → MCP."
            )
        }
        guard FileManager.default.fileExists(atPath: uvPath) else {
            throw MCPError.processLaunchFailed(
                "uv not found at \(uvPath). " +
                "Install uv (https://docs.astral.sh/uv/) or update the path in Settings → AI → MCP."
            )
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: uvPath)
        p.arguments = ["run", "python", serverScript]
        p.currentDirectoryURL = serverDir

        let stdin = Pipe()
        let stdout = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = Pipe()

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { await self?.handleData(text) }
        }

        do {
            try p.run()
        } catch {
            throw MCPError.processLaunchFailed(error.localizedDescription)
        }

        process = p
        stdinHandle = stdin.fileHandleForWriting
        isRunning = true

        // Initialize handshake
        let initResult = try await sendRequest(method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": [:] as [String: Any],
            "clientInfo": ["name": "FocusLens", "version": "1.0"] as [String: Any]
        ])
        logger.info("MCP initialized: \(String(describing: (initResult["serverInfo"] as? [String: Any])?["name"] ?? "unknown"))")

        sendNotification(method: "notifications/initialized", params: [:])

        // Discover tools
        let toolsResult = try await sendRequest(method: "tools/list", params: [:])
        discoveredTools = parseTools(from: toolsResult)
        logger.info("MCP: \(self.discoveredTools.count) tools available")
    }

    func stop() {
        stdinHandle?.closeFile()
        process?.terminate()
        process = nil
        stdinHandle = nil
        isRunning = false
        for (_, cont) in pendingContinuations {
            cont.resume(throwing: MCPError.notInitialized)
        }
        pendingContinuations = [:]
        discoveredTools = []
    }

    // MARK: - Tool calling

    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        guard isRunning else { throw MCPError.notInitialized }
        let result = try await sendRequest(method: "tools/call", params: [
            "name": name,
            "arguments": arguments
        ])
        return extractText(from: result)
    }

    // MARK: - JSON-RPC

    private func sendRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
        let id = nextID
        nextID += 1

        let request: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let line = String(data: data, encoding: .utf8) else {
            throw MCPError.encodingFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuations[id] = continuation
            stdinHandle?.write((line + "\n").data(using: .utf8)!)
        }
    }

    private func sendNotification(method: String, params: [String: Any]) {
        let msg: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              let line = String(data: data, encoding: .utf8) else { return }
        stdinHandle?.write((line + "\n").data(using: .utf8)!)
    }

    // MARK: - Response parsing

    private func handleData(_ text: String) {
        lineBuffer += text
        var lines = lineBuffer.components(separatedBy: "\n")
        lineBuffer = lines.removeLast()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            processLine(trimmed)
        }
    }

    private func processLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.warning("MCPClient: unparseable line: \(line.prefix(200))")
            return
        }

        guard let idAny = json["id"] else { return } // notification, no response needed

        let id: Int
        if let i = idAny as? Int { id = i }
        else if let d = idAny as? Double { id = Int(d) }
        else { return }

        guard let cont = pendingContinuations.removeValue(forKey: id) else { return }

        if let result = json["result"] as? [String: Any] {
            cont.resume(returning: result)
        } else if let error = json["error"] as? [String: Any] {
            let msg = error["message"] as? String ?? "unknown MCP error"
            cont.resume(throwing: MCPError.serverError(msg))
        } else {
            cont.resume(returning: [:])
        }
    }

    private func parseTools(from result: [String: Any]) -> [MCPToolDefinition] {
        guard let tools = result["tools"] as? [[String: Any]] else { return [] }
        return tools.compactMap { tool in
            guard let name = tool["name"] as? String,
                  let desc = tool["description"] as? String else { return nil }
            let schema = tool["inputSchema"] as? [String: Any] ?? [:]
            return MCPToolDefinition(name: name, description: desc, argsDescription: argsDesc(schema))
        }
    }

    private func argsDesc(_ schema: [String: Any]) -> String {
        guard let props = schema["properties"] as? [String: Any], !props.isEmpty else { return "none" }
        let required = (schema["required"] as? [String]) ?? []
        return props.keys.sorted().map { key in
            let info = props[key] as? [String: Any]
            let type_ = info?["type"] as? String ?? "any"
            return required.contains(key) ? "\(key): \(type_)" : "\(key): \(type_) (optional)"
        }.joined(separator: ", ")
    }

    private func extractText(from result: [String: Any]) -> String {
        if let content = result["content"] as? [[String: Any]],
           let first = content.first,
           let text = first["text"] as? String {
            return text
        }
        return (try? JSONSerialization.data(withJSONObject: result))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
