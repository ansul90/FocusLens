import Foundation

enum AppConstants {
    static let idleThresholdSeconds: TimeInterval = 600
    static let minimumSessionSeconds: TimeInterval = 60
    static let idlePollIntervalSeconds: TimeInterval = 30
    static let menuRefreshIntervalSeconds: TimeInterval = 1
    static let bundleIdentifier: String = "com.focuslens.app"
    static let databaseName: String = "focuslens.db"
    static let maxReasonableSessionSeconds: TimeInterval = 14400
    static let walCheckpointIntervalSeconds: TimeInterval = 1800 // 30 minutes

    // Window titles that carry no useful signal — sessions ending with these are discarded.
    // Matched case-insensitively as a prefix so "New tab - Google Chrome" is caught by "new tab".
    static let noisyWindowTitlePrefixes: [String] = [
        "new tab",    // Chrome, Firefox
        "new window", // Chrome, Firefox
        "start page", // Safari
    ]

    static let appSupportDirectory: URL = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not resolve Application Support directory — cannot launch FocusLens")
        }
        return base.appendingPathComponent("FocusLens", isDirectory: true)
    }()

    static let databaseURL: URL = {
        appSupportDirectory.appendingPathComponent(databaseName)
    }()

    enum AI {
        static let endpointBase: String = "https://generativelanguage.googleapis.com/v1beta/models"
        static let modelName: String = "gemini-2.5-flash"
        static let maxBatchSize: Int = 25
        static let requestTimeoutSeconds: TimeInterval = 15
        static let userDefaultsKeyAPIKey: String = "ai.gemini.apiKey"
        static let userDefaultsKeyEnabled: String = "ai.gemini.enabled"
        // Free tier: 1,500 RPD / 15 RPM. At 30-min intervals = ~48 calls/day.
        static let reclassifyIntervalSeconds: TimeInterval = 1800
    }

    enum Ollama {
        static let defaultHost: String = "http://localhost:11434"
        static let defaultModel: String = "gemma4:26b-a4b-it-q4_K_M"
        static let requestTimeoutSeconds: TimeInterval = 60
        static let healthCheckTimeoutSeconds: TimeInterval = 2
        static let userDefaultsKeyEnabled: String = "ai.ollama.enabled"
        static let userDefaultsKeyHost: String = "ai.ollama.host"
        static let userDefaultsKeyModel: String = "ai.ollama.model"
    }

    enum Agent {
        static let maxIterations: Int = 15
        // num_ctx = 8192 tokens ≈ 32 KB; budget: system prompt + history + ≤4 tool results × 2000 chars
        static let toolResultMaxChars: Int = 2000
        static let fileLogEnabled: Bool = false
        static let logFileSizeCapBytes: Int = 1_048_576  // 1 MB
    }

    enum MCP {
        static let defaultUvPath: String = "\(NSHomeDirectory())/.local/bin/uv"
        static let defaultServerDirectory: String = {
            guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                fatalError("Could not resolve Application Support directory — cannot launch FocusLens")
            }
            return appSupport.appendingPathComponent("FocusLens/mcp").path
        }()
        static let serverScript: String = "server.py"
        static let userDefaultsKeyServerDirectory: String = "mcp.serverDirectory"
        static let userDefaultsKeyUvPath: String = "mcp.uvPath"

        static var uvPath: String {
            UserDefaults.standard.string(forKey: userDefaultsKeyUvPath)
                .flatMap { $0.isEmpty ? nil : $0 } ?? defaultUvPath
        }
        static var serverDirectory: String {
            UserDefaults.standard.string(forKey: userDefaultsKeyServerDirectory)
                .flatMap { $0.isEmpty ? nil : $0 } ?? defaultServerDirectory
        }
    }
}
