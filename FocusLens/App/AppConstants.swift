import Foundation

enum AppConstants {
    static let idleThresholdSeconds: TimeInterval = 300
    static let minimumSessionSeconds: TimeInterval = 60
    static let idlePollIntervalSeconds: TimeInterval = 30
    static let menuRefreshIntervalSeconds: TimeInterval = 1
    static let bundleIdentifier: String = "com.focuslens.app"
    static let databaseName: String = "focuslens.db"
    static let maxReasonableSessionSeconds: TimeInterval = 14400

    static let appSupportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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
        static let toolResultMaxChars: Int = 4000
    }
}
