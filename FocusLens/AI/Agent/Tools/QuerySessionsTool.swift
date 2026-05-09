import Foundation
import GRDB

struct QuerySessionsTool: AgentTool {
    let name = "query_sessions"
    let description = "Fetches individual activity sessions for a date. Optionally filter by category name or app name substring. Returns app name, window title, duration, and category."
    let argsDescription = #"date: "yyyy-MM-dd" or "today"/"yesterday" | category_name: string (optional) | app_name: string (optional) | limit: int (optional, default 20)"#

    private let dbPool: DatabasePool

    init(dbPool: DatabasePool = DatabaseManager.shared.dbPool) {
        self.dbPool = dbPool
    }

    func run(args: [String: Any]) async -> String {
        guard let rawDate = args["date"] as? String else {
            return toolError("Missing required argument: date")
        }

        let lower = rawDate.lowercased().trimmingCharacters(in: .whitespaces)
        if lower == "this_week" || lower == "last_week" {
            return toolError("query_sessions only accepts single dates (e.g. today, yesterday, 2026-05-08). Use get_activity for week ranges.")
        }

        let date = resolveDate(rawDate)
        let categoryFilter = args["category_name"] as? String
        let appFilter = args["app_name"] as? String
        let limit = (args["limit"] as? Int) ?? 20

        let (start, end) = DateUtils.dayBoundsISO(for: date)

        do {
            struct SessionOut: Encodable {
                let app: String
                let window_title: String
                let duration_minutes: Double
                let category: String
            }

            let rows = try await dbPool.read { db in
                var sql = """
                    SELECT a.app_name, a.window_title, a.duration_seconds, COALESCE(c.name, 'Uncategorized') as cat_name
                    FROM activity_sessions a
                    LEFT JOIN categories c ON a.category_id = c.id
                    WHERE a.started_at >= ? AND a.started_at < ?
                      AND a.is_idle = 0 AND a.ended_at IS NOT NULL
                    """
                var arguments: [DatabaseValueConvertible] = [start, end]

                if let cat = categoryFilter {
                    sql += " AND LOWER(c.name) LIKE ?"
                    arguments.append("%\(cat.lowercased())%")
                }
                if let app = appFilter {
                    sql += " AND LOWER(a.app_name) LIKE ?"
                    arguments.append("%\(app.lowercased())%")
                }
                sql += " ORDER BY a.duration_seconds DESC LIMIT ?"
                arguments.append(limit)

                return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            }

            let out = rows.map { row -> SessionOut in
                let secs = (row["duration_seconds"] as? Double) ?? 0
                return SessionOut(
                    app: row["app_name"] ?? "",
                    window_title: row["window_title"] ?? "(no title)",
                    duration_minutes: (secs / 60).rounded(digits: 1),
                    category: row["cat_name"] ?? "Uncategorized"
                )
            }
            struct Wrapper: Encodable {
                let date: String
                let count: Int
                let sessions: [SessionOut]
            }
            return toolJSON(Wrapper(date: rawDate, count: out.count, sessions: out))
        } catch {
            return toolError("Query failed: \(error.localizedDescription)")
        }
    }
}
