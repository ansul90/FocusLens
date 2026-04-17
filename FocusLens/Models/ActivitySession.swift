import Foundation
import GRDB

struct ActivitySession: Codable, Identifiable, Hashable, Sendable {
    var id: Int64?
    let appBundleId: String
    let appName: String
    let windowTitle: String?
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Double?
    let isIdle: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case appBundleId = "app_bundle_id"
        case appName = "app_name"
        case windowTitle = "window_title"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case isIdle = "is_idle"
    }

    var isActive: Bool { endedAt == nil }

    var displayDuration: TimeInterval {
        durationSeconds ?? Date().timeIntervalSince(startedAt)
    }
}

extension ActivitySession: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "activity_sessions"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let appBundleId = Column(CodingKeys.appBundleId)
        static let appName = Column(CodingKeys.appName)
        static let windowTitle = Column(CodingKeys.windowTitle)
        static let startedAt = Column(CodingKeys.startedAt)
        static let endedAt = Column(CodingKeys.endedAt)
        static let durationSeconds = Column(CodingKeys.durationSeconds)
        static let isIdle = Column(CodingKeys.isIdle)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
