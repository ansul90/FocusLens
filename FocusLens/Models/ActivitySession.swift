import Foundation

struct ActivitySession {
    var id: Int64?
    var appBundleId: String
    var appName: String
    var windowTitle: String?
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Double?
    var isIdle: Bool
}
