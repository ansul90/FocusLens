import Foundation
import GRDB

struct ActivitySessionStore: Sendable {
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

    func close(id: Int64, at endDate: Date, windowTitle: String? = nil) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE activity_sessions
                    SET ended_at = ?,
                        duration_seconds = (julianday(?) - julianday(started_at)) * 86400,
                        window_title = COALESCE(?, window_title)
                    WHERE id = ?
                    """,
                arguments: [endDate, endDate, windowTitle, id]
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

    func fetchTopApps(for date: Date, limit: Int) throws -> [(appName: String, appBundleId: String, totalSeconds: Double)] {
        let (start, end) = dayBoundsISO(for: date)
        return try fetchTopApps(startISO: start, endISO: end, limit: limit)
    }

    func fetchTopApps(start: Date, end: Date, limit: Int) throws -> [(appName: String, appBundleId: String, totalSeconds: Double)] {
        let (s, e) = rangeBoundsISO(start: start, end: end)
        return try fetchTopApps(startISO: s, endISO: e, limit: limit)
    }

    func fetchActiveSeconds(for date: Date) throws -> Double {
        let (start, end) = dayBoundsISO(for: date)
        return try fetchActiveSeconds(startISO: start, endISO: end)
    }

    func fetchActiveSeconds(start: Date, end: Date) throws -> Double {
        let (s, e) = rangeBoundsISO(start: start, end: end)
        return try fetchActiveSeconds(startISO: s, endISO: e)
    }

    func fetchCategoryBreakdown(for date: Date) throws -> [(categoryId: Int64?, totalSeconds: Double)] {
        let (start, end) = dayBoundsISO(for: date)
        return try fetchCategoryBreakdown(startISO: start, endISO: end)
    }

    func fetchCategoryBreakdown(start: Date, end: Date) throws -> [(categoryId: Int64?, totalSeconds: Double)] {
        let (s, e) = rangeBoundsISO(start: start, end: end)
        return try fetchCategoryBreakdown(startISO: s, endISO: e)
    }

    func fetchHourlyCategoryBreakdown(for date: Date) throws -> [(hour: Int, colorHex: String, seconds: Double)] {
        let (start, end) = dayBoundsISO(for: date)
        return try dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        CAST(strftime('%H', a.started_at, 'localtime') AS INTEGER) as hour,
                        COALESCE(c.color_hex, '9E9E9E') as color_hex,
                        COALESCE(SUM(a.duration_seconds), 0) as total
                    FROM activity_sessions a
                    LEFT JOIN categories c ON a.category_id = c.id
                    WHERE a.started_at >= ? AND a.started_at < ?
                      AND a.is_idle = 0 AND a.ended_at IS NOT NULL
                    GROUP BY hour, a.category_id
                    ORDER BY hour, total DESC
                    """,
                arguments: [start, end]
            )
            return rows.map { (hour: $0["hour"], colorHex: $0["color_hex"], seconds: $0["total"]) }
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

    func fetchTopInterruptors(for date: Date, limit: Int) throws -> [(appName: String, appBundleId: String, totalSeconds: Double, tier: Int)] {
        let (start, end) = dayBoundsISO(for: date)
        return try fetchTopInterruptors(startISO: start, endISO: end, limit: limit)
    }

    func fetchTopInterruptors(start: Date, end: Date, limit: Int) throws -> [(appName: String, appBundleId: String, totalSeconds: Double, tier: Int)] {
        let (s, e) = rangeBoundsISO(start: start, end: end)
        return try fetchTopInterruptors(startISO: s, endISO: e, limit: limit)
    }

    func fetchTopWindowTitles(for date: Date, limit: Int) throws -> [(windowTitle: String, appName: String, appBundleId: String, totalSeconds: Double, tier: Int)] {
        let (start, end) = dayBoundsISO(for: date)
        return try dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT a.window_title, a.app_name, a.app_bundle_id,
                           COALESCE(SUM(a.duration_seconds), 0) as total,
                           COALESCE(c.is_productive, 0) as tier
                    FROM activity_sessions a
                    LEFT JOIN categories c ON a.category_id = c.id
                    WHERE a.started_at >= ? AND a.started_at < ?
                      AND a.is_idle = 0 AND a.ended_at IS NOT NULL
                      AND a.window_title IS NOT NULL
                      AND TRIM(a.window_title) <> ''
                    GROUP BY a.app_bundle_id, a.window_title
                    ORDER BY total DESC
                    LIMIT ?
                    """,
                arguments: [start, end, limit]
            )
            return rows.map { (windowTitle: $0["window_title"], appName: $0["app_name"], appBundleId: $0["app_bundle_id"], totalSeconds: $0["total"], tier: $0["tier"]) }
        }
    }

    func fetchDailyActiveSeconds(start: Date, end: Date) throws -> [(date: Date, seconds: Double)] {
        let (s, e) = rangeBoundsISO(start: start, end: end)
        return try dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        DATE(started_at, 'localtime') as day,
                        COALESCE(SUM(duration_seconds), 0) as total
                    FROM activity_sessions
                    WHERE started_at >= ? AND started_at < ?
                      AND is_idle = 0 AND ended_at IS NOT NULL
                    GROUP BY day
                    ORDER BY day
                    """,
                arguments: [s, e]
            )
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.timeZone = Calendar.current.timeZone
            return rows.compactMap { row -> (date: Date, seconds: Double)? in
                guard let dayStr: String = row["day"],
                      let date = fmt.date(from: dayStr) else { return nil }
                return (date: date, seconds: row["total"])
            }
        }
    }

    func fetchDailyActiveTierBreakdown(start: Date, end: Date) throws -> [(date: Date, tier: Int, seconds: Double)] {
        let (s, e) = rangeBoundsISO(start: start, end: end)
        return try dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        DATE(a.started_at, 'localtime') as day,
                        COALESCE(c.is_productive, 0) as tier,
                        COALESCE(SUM(a.duration_seconds), 0) as total
                    FROM activity_sessions a
                    LEFT JOIN categories c ON a.category_id = c.id
                    WHERE a.started_at >= ? AND a.started_at < ?
                      AND a.is_idle = 0 AND a.ended_at IS NOT NULL
                    GROUP BY day, tier
                    ORDER BY day, tier
                    """,
                arguments: [s, e]
            )
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.timeZone = Calendar.current.timeZone
            return rows.compactMap { row -> (date: Date, tier: Int, seconds: Double)? in
                guard let dayStr: String = row["day"],
                      let date = fmt.date(from: dayStr) else { return nil }
                return (date: date, tier: row["tier"], seconds: row["total"])
            }
        }
    }

    // MARK: - Private implementations

    private func dayBoundsISO(for date: Date) -> (start: String, end: String) { DateUtils.dayBoundsISO(for: date) }
    private func rangeBoundsISO(start: Date, end: Date) -> (start: String, end: String) { DateUtils.rangeBoundsISO(start: start, end: end) }

    private func fetchTopApps(startISO: String, endISO: String, limit: Int) throws -> [(appName: String, appBundleId: String, totalSeconds: Double)] {
        try dbPool.read { db in
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
                arguments: [startISO, endISO, limit]
            )
            return rows.map { (appName: $0["app_name"], appBundleId: $0["app_bundle_id"], totalSeconds: $0["total"]) }
        }
    }

    private func fetchActiveSeconds(startISO: String, endISO: String) throws -> Double {
        try dbPool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(SUM(duration_seconds), 0) as total
                    FROM activity_sessions
                    WHERE started_at >= ? AND started_at < ? AND is_idle = 0 AND ended_at IS NOT NULL
                    """,
                arguments: [startISO, endISO]
            )
            return row?["total"] ?? 0.0
        }
    }

    private func fetchCategoryBreakdown(startISO: String, endISO: String) throws -> [(categoryId: Int64?, totalSeconds: Double)] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT category_id, COALESCE(SUM(duration_seconds), 0) as total
                    FROM activity_sessions
                    WHERE started_at >= ? AND started_at < ? AND is_idle = 0 AND ended_at IS NOT NULL
                    GROUP BY category_id
                    ORDER BY total DESC
                    """,
                arguments: [startISO, endISO]
            )
            return rows.map { (categoryId: $0["category_id"], totalSeconds: $0["total"]) }
        }
    }

    private func fetchTopInterruptors(startISO: String, endISO: String, limit: Int) throws -> [(appName: String, appBundleId: String, totalSeconds: Double, tier: Int)] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT a.app_name, a.app_bundle_id,
                           COALESCE(SUM(a.duration_seconds), 0) as total,
                           COALESCE(c.is_productive, 0) as tier
                    FROM activity_sessions a
                    LEFT JOIN categories c ON a.category_id = c.id
                    WHERE a.started_at >= ? AND a.started_at < ?
                      AND a.is_idle = 0 AND a.ended_at IS NOT NULL
                      AND COALESCE(c.is_productive, 0) <= -1
                    GROUP BY a.app_bundle_id
                    ORDER BY total DESC
                    LIMIT ?
                    """,
                arguments: [startISO, endISO, limit]
            )
            return rows.map { (appName: $0["app_name"], appBundleId: $0["app_bundle_id"], totalSeconds: $0["total"], tier: $0["tier"]) }
        }
    }

    func updateWindowTitle(id: Int64, windowTitle: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "UPDATE activity_sessions SET window_title = ? WHERE id = ?",
                arguments: [windowTitle, id]
            )
        }
    }

    func delete(id: Int64) throws {
        try dbPool.write { db in
            try ActivitySession.filter(ActivitySession.Columns.id == id).deleteAll(db)
        }
    }

}
