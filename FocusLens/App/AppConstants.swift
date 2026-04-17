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
}
