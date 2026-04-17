import Foundation

enum AppConstants {
    static let idleThresholdSeconds: TimeInterval = 300
    static let minimumSessionSeconds: TimeInterval = 2
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
        static let modelName: String = "gemini-2.0-flash"
        static let maxBatchSize: Int = 25
        static let requestTimeoutSeconds: TimeInterval = 15
        static let userDefaultsKeyAPIKey: String = "ai.gemini.apiKey"
        static let userDefaultsKeyEnabled: String = "ai.gemini.enabled"
    }
}
