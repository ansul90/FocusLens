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
        let (start, end) = dayBoundsISO(for: Date())
        return try dbPool.read { db in
            try ActivitySession
                .filter(ActivitySession.Columns.startedAt >= start)
                .filter(ActivitySession.Columns.startedAt < end)
                .filter(ActivitySession.Columns.endedAt != nil)
                .fetchAll(db)
        }
    }

    func fetchTopApps(for date: Date, limit: Int) throws -> [(appName: String, appBundleId: String, totalSeconds: Double)] {
        let (start, end) = dayBoundsISO(for: date)
        return try dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT app_name, app_bundle_id, COALESCE(SUM(duration_seconds), 0) as total
                    FROM activity_sessions
                    WHERE started_at >= ? AND started_at < ? AND is_idle = 0 AND ended_at IS NOT NULL
                    GROUP BY app_bundle_id
                    ORDER BY total DESC
                    LIMIT ?
                    """,
                arguments: [start, end, limit]
            )
            return rows.map { (appName: $0["app_name"], appBundleId: $0["app_bundle_id"], totalSeconds: $0["total"]) }
        }
    }

    func fetchActiveSeconds(for date: Date) throws -> Double {
        let (start, end) = dayBoundsISO(for: date)
        return try dbPool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(SUM(duration_seconds), 0) as total
                    FROM activity_sessions
                    WHERE started_at >= ? AND started_at < ? AND is_idle = 0 AND ended_at IS NOT NULL
                    """,
                arguments: [start, end]
            )
            return row?["total"] ?? 0.0
        }
    }

    func fetchCategoryBreakdown(for date: Date) throws -> [(categoryId: Int64?, totalSeconds: Double)] {
        let (start, end) = dayBoundsISO(for: date)
        return try dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT category_id, COALESCE(SUM(duration_seconds), 0) as total
                    FROM activity_sessions
                    WHERE started_at >= ? AND started_at < ? AND is_idle = 0 AND ended_at IS NOT NULL
                    GROUP BY category_id
                    ORDER BY total DESC
                    """,
                arguments: [start, end]
            )
            return rows.map { (categoryId: $0["category_id"], totalSeconds: $0["total"]) }
        }
    }

    func fetchHourlyTierBreakdown(for date: Date) throws -> [(hour: Int, tier: Int, seconds: Double)] {
        let (start, end) = dayBoundsISO(for: date)
        return try dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        CAST(strftime('%H', a.started_at, 'localtime') AS INTEGER) as hour,
                        COALESCE(c.is_productive, 0) as tier,
                        COALESCE(SUM(a.duration_seconds), 0) as total
                    FROM activity_sessions a
                    LEFT JOIN categories c ON a.category_id = c.id
                    WHERE a.started_at >= ? AND a.started_at < ? AND a.is_idle = 0 AND a.ended_at IS NOT NULL
                    GROUP BY hour, tier
                    ORDER BY hour, tier
                    """,
                arguments: [start, end]
            )
            return rows.map { (hour: $0["hour"], tier: $0["tier"], seconds: $0["total"]) }
        }
    }

    func delete(id: Int64) throws {
        try dbPool.write { db in
            try ActivitySession.filter(ActivitySession.Columns.id == id).deleteAll(db)
        }
    }

    // Returns (startOfDay, startOfNextDay) as UTC ISO strings for the given date.
    private func dayBoundsISO(for date: Date) -> (start: String, end: String) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        fmt.timeZone = TimeZone(identifier: "UTC")!
        return (fmt.string(from: start), fmt.string(from: end))
    }
}
