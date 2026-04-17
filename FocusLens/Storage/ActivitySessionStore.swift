import Foundation
import GRDB

struct ActivitySessionStore {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool = DatabaseManager.shared.dbPool) {
        self.dbPool = dbPool
    }

    func insert(_ session: ActivitySession) throws -> ActivitySession {
        var mutable = session
        try dbPool.write { db in
            try mutable.insert(db)
        }
        return mutable
    }

    func close(id: Int64, at endDate: Date) throws {
        try dbPool.write { db in
            let started = try ActivitySession
                .filter(ActivitySession.Columns.id == id)
                .fetchOne(db)
            let duration: Double? = started.map { endDate.timeIntervalSince($0.startedAt) }
            try db.execute(
                sql: "UPDATE activity_sessions SET ended_at = ?, duration_seconds = ? WHERE id = ?",
                arguments: [endDate, duration, id]
            )
        }
    }

    func fetchOpenSessions() throws -> [ActivitySession] {
        try dbPool.read { db in
            try ActivitySession
                .filter(ActivitySession.Columns.endedAt == nil)
                .fetchAll(db)
        }
    }

    func fetchTodaySessions() throws -> [ActivitySession] {
        let midnight = todayMidnightISO()
        return try dbPool.read { db in
            try ActivitySession
                .filter(ActivitySession.Columns.startedAt >= midnight)
                .filter(ActivitySession.Columns.endedAt != nil)
                .fetchAll(db)
        }
    }

    func fetchTodayTopApps(limit: Int) throws -> [(appName: String, appBundleId: String, totalSeconds: Double)] {
        let midnight = todayMidnightISO()
        return try dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT app_name, app_bundle_id, COALESCE(SUM(duration_seconds), 0) as total
                    FROM activity_sessions
                    WHERE started_at >= ? AND is_idle = 0 AND ended_at IS NOT NULL
                    GROUP BY app_bundle_id
                    ORDER BY total DESC
                    LIMIT ?
                    """,
                arguments: [midnight, limit]
            )
            return rows.map { (appName: $0["app_name"], appBundleId: $0["app_bundle_id"], totalSeconds: $0["total"]) }
        }
    }

    func fetchTodayActiveSeconds() throws -> Double {
        let midnight = todayMidnightISO()
        return try dbPool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(SUM(duration_seconds), 0) as total
                    FROM activity_sessions
                    WHERE started_at >= ? AND is_idle = 0 AND ended_at IS NOT NULL
                    """,
                arguments: [midnight]
            )
            return row?["total"] ?? 0.0
        }
    }

    private func todayMidnightISO() -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let midnight = cal.startOfDay(for: Date())
        return DateFormatters.string(from: midnight)
    }
}
