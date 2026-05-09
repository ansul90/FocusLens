import Foundation
import GRDB

struct GetActivityTool: AgentTool {
    let name = "get_activity"
    let description = "Returns top apps, category time breakdown, and productivity score (0-100) for a date or date range. Use for any question about time spent, top apps, categories, or productivity."
    let argsDescription = #"date: "yyyy-MM-dd" or "today"/"yesterday"/"this_week"/"last_week" | end: "yyyy-MM-dd" (optional, defaults to same day as date)"#

    private let dbPool: DatabasePool

    init(dbPool: DatabasePool = DatabaseManager.shared.dbPool) {
        self.dbPool = dbPool
    }

    func run(args: [String: Any]) async -> String {
        guard let rawStart = args["date"] as? String else {
            return toolError("Missing required argument: date")
        }

        let rawEnd = args["end"] as? String
        let range: DateRange
        if let end = rawEnd {
            let (s, _) = DateUtils.dayBoundsISO(for: resolveDate(rawStart))
            let (_, e) = DateUtils.dayBoundsISO(for: resolveDate(end))
            range = DateRange(start: s, end: e)
        } else {
            range = buildDateRange(rawStart)
        }

        do {
            let (appRows, catRows, tierRows) = try await dbPool.read { db -> ([Row], [Row], [Row]) in
                let apps = try Row.fetchAll(db, sql: """
                    SELECT a.app_name,
                           COALESCE(SUM(a.duration_seconds), 0) as total,
                           COALESCE(c.is_productive, 0) as tier,
                           COALESCE(c.name, 'Uncategorized') as category
                    FROM activity_sessions a
                    LEFT JOIN categories c ON a.category_id = c.id
                    WHERE a.started_at >= ? AND a.started_at < ?
                      AND a.is_idle = 0 AND a.ended_at IS NOT NULL
                    GROUP BY a.app_bundle_id, a.app_name ORDER BY total DESC LIMIT 10
                    """, arguments: [range.start, range.end])

                let cats = try Row.fetchAll(db, sql: """
                    SELECT COALESCE(c.name, 'Uncategorized') as label,
                           COALESCE(SUM(a.duration_seconds), 0) as total
                    FROM activity_sessions a
                    LEFT JOIN categories c ON a.category_id = c.id
                    WHERE a.started_at >= ? AND a.started_at < ?
                      AND a.is_idle = 0 AND a.ended_at IS NOT NULL
                    GROUP BY c.id ORDER BY total DESC
                    """, arguments: [range.start, range.end])

                let tiers = try Row.fetchAll(db, sql: """
                    SELECT COALESCE(c.is_productive, 0) as tier,
                           COALESCE(SUM(a.duration_seconds), 0) as total
                    FROM activity_sessions a
                    LEFT JOIN categories c ON a.category_id = c.id
                    WHERE a.started_at >= ? AND a.started_at < ?
                      AND a.is_idle = 0 AND a.ended_at IS NOT NULL
                    GROUP BY tier
                    """, arguments: [range.start, range.end])

                return (apps, cats, tiers)
            }

            var weightedSum: Double = 0
            var totalSecs: Double = 0
            for row in tierRows {
                let tier = (row["tier"] as? Int) ?? (row["tier"] as? Int64).map(Int.init) ?? 0
                let secs = (row["total"] as? Double) ?? 0
                weightedSum += Double(tier) * secs
                totalSecs += secs
            }
            let score = totalSecs > 0
                ? max(0, min(100, Int(((weightedSum / totalSecs) + 2.0) / 4.0 * 100)))
                : 50

            struct AppEntry: Encodable {
                let rank: Int; let app: String; let minutes: Double
                let tier: Int; let category: String
            }
            struct CatEntry: Encodable { let category: String; let minutes: Double }
            struct Out: Encodable {
                let date_range: String
                let score: Int
                let total_active_minutes: Double
                let top_apps: [AppEntry]
                let categories: [CatEntry]
            }

            let apps = appRows.enumerated().map { idx, row in
                let tier = (row["tier"] as? Int) ?? (row["tier"] as? Int64).map(Int.init) ?? 0
                return AppEntry(
                    rank: idx + 1,
                    app: row["app_name"] ?? "?",
                    minutes: ((row["total"] as? Double ?? 0) / 60).rounded(digits: 1),
                    tier: tier,
                    category: row["category"] ?? "Uncategorized"
                )
            }
            let cats = catRows.map { row in
                CatEntry(category: row["label"] ?? "?",
                         minutes: ((row["total"] as? Double ?? 0) / 60).rounded(digits: 1))
            }

            let label = rawEnd != nil ? "\(rawStart) to \(rawEnd!)" : rawStart
            return toolJSON(Out(
                date_range: label,
                score: score,
                total_active_minutes: (totalSecs / 60).rounded(digits: 1),
                top_apps: apps,
                categories: cats
            ))
        } catch {
            return toolError("Query failed: \(error.localizedDescription)")
        }
    }
}
