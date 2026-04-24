import Foundation
import GRDB

// MARK: - CurrentTimeTool

struct CurrentTimeTool: AgentTool {
    let name = "current_time"
    let description = "Returns the current date and time, plus convenient labels like today and yesterday. Call this first when the user's question involves relative dates."
    let argsDescription = "none"

    func run(args: [String: Any]) async -> String {
        let now = Date()
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: now)
        let yesterday = fmt.string(from: cal.date(byAdding: .day, value: -1, to: now)!)
        let weekAgo = fmt.string(from: cal.date(byAdding: .day, value: -7, to: now)!)

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "yyyy-MM-dd HH:mm"
        timeFmt.timeZone = TimeZone.current

        struct Out: Encodable {
            let now: String
            let today: String
            let yesterday: String
            let week_ago: String
            let timezone: String
        }
        return toolJSON(Out(
            now: timeFmt.string(from: now),
            today: today,
            yesterday: yesterday,
            week_ago: weekAgo,
            timezone: TimeZone.current.identifier
        ))
    }
}

// MARK: - ListCategoriesTool

struct ListCategoriesTool: AgentTool {
    let name = "list_categories"
    let description = "Lists all productivity categories with their names and productivity tiers (+2 very productive to -2 very distracting)."
    let argsDescription = "none"

    private let dbPool: DatabasePool

    init(dbPool: DatabasePool = DatabaseManager.shared.dbPool) {
        self.dbPool = dbPool
    }

    func run(args: [String: Any]) async -> String {
        do {
            let categories = try await dbPool.read { db in
                try Category.fetchAll(db)
            }
            struct CatOut: Encodable {
                let id: Int64?
                let name: String
                let tier: Int
            }
            let out = categories.map { CatOut(id: $0.id, name: $0.name, tier: $0.productivityScore) }
            return toolJSON(out)
        } catch {
            return toolError("Failed to fetch categories: \(error.localizedDescription)")
        }
    }
}

// MARK: - QuerySessionsTool

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

        let date = resolveDate(rawDate)
        let categoryFilter = args["category_name"] as? String
        let appFilter = args["app_name"] as? String
        let limit = (args["limit"] as? Int) ?? 20

        let (start, end) = dayBoundsISO(for: date)

        do {
            struct SessionOut: Encodable {
                let app: String
                let window_title: String
                let duration_minutes: Double
                let category_id: Int64?
            }

            let rows = try await dbPool.read { db in
                var sql = """
                    SELECT a.app_name, a.window_title, a.duration_seconds, a.category_id, c.name as cat_name
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
                    category_id: row["category_id"]
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

// MARK: - AggregateTimeTool

struct AggregateTimeTool: AgentTool {
    let name = "aggregate_time"
    let description = "Sums activity time grouped by category, app, or hour of day for a given date or named range. Returns totals in hours and minutes."
    let argsDescription = #"group_by: "category" or "app" or "hour" | date_range: "yyyy-MM-dd" or "today"/"yesterday"/"this_week""#

    private let dbPool: DatabasePool

    init(dbPool: DatabasePool = DatabaseManager.shared.dbPool) {
        self.dbPool = dbPool
    }

    func run(args: [String: Any]) async -> String {
        guard let groupBy = args["group_by"] as? String,
              ["category", "app", "hour"].contains(groupBy) else {
            return toolError("group_by must be 'category', 'app', or 'hour'")
        }
        guard let rawRange = args["date_range"] as? String else {
            return toolError("Missing required argument: date_range")
        }

        let dateRange = buildDateRange(rawRange)

        do {
            let rows = try await dbPool.read { db -> [(String, Double)] in
                switch groupBy {
                case "category":
                    let sql = """
                        SELECT COALESCE(c.name, 'Uncategorized') as label,
                               COALESCE(SUM(a.duration_seconds), 0) as total
                        FROM activity_sessions a
                        LEFT JOIN categories c ON a.category_id = c.id
                        WHERE a.started_at >= ? AND a.started_at < ?
                          AND a.is_idle = 0 AND a.ended_at IS NOT NULL
                        GROUP BY c.id
                        ORDER BY total DESC
                        """
                    return try Row.fetchAll(db, sql: sql, arguments: [dateRange.start, dateRange.end])
                        .map { ($0["label"] ?? "?", $0["total"] ?? 0) }

                case "app":
                    let sql = """
                        SELECT app_name as label,
                               COALESCE(SUM(duration_seconds), 0) as total
                        FROM activity_sessions
                        WHERE started_at >= ? AND started_at < ?
                          AND is_idle = 0 AND ended_at IS NOT NULL
                        GROUP BY app_bundle_id
                        ORDER BY total DESC
                        LIMIT 15
                        """
                    return try Row.fetchAll(db, sql: sql, arguments: [dateRange.start, dateRange.end])
                        .map { ($0["label"] ?? "?", $0["total"] ?? 0) }

                default: // "hour"
                    let sql = """
                        SELECT CAST(strftime('%H', started_at, 'localtime') AS INTEGER) || ':00' as label,
                               COALESCE(SUM(duration_seconds), 0) as total
                        FROM activity_sessions
                        WHERE started_at >= ? AND started_at < ?
                          AND is_idle = 0 AND ended_at IS NOT NULL
                        GROUP BY strftime('%H', started_at, 'localtime')
                        ORDER BY label
                        """
                    return try Row.fetchAll(db, sql: sql, arguments: [dateRange.start, dateRange.end])
                        .map { ($0["label"] ?? "?", $0["total"] ?? 0) }
                }
            }

            struct Entry: Encodable {
                let label: String
                let hours: Double
                let minutes: Double
            }
            let entries = rows.map { Entry(label: $0.0, hours: ($0.1 / 3600).rounded(digits: 2), minutes: ($0.1 / 60).rounded(digits: 1)) }
            struct Wrapper: Encodable {
                let group_by: String
                let date_range: String
                let data: [Entry]
            }
            return toolJSON(Wrapper(group_by: groupBy, date_range: rawRange, data: entries))
        } catch {
            return toolError("Aggregation failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - TopAppsTool

struct TopAppsTool: AgentTool {
    let name = "top_apps"
    let description = "Returns the top N apps ranked by time spent on a given date."
    let argsDescription = #"date: "yyyy-MM-dd" or "today"/"yesterday" | limit: int (optional, default 10)"#

    private let dbPool: DatabasePool

    init(dbPool: DatabasePool = DatabaseManager.shared.dbPool) {
        self.dbPool = dbPool
    }

    func run(args: [String: Any]) async -> String {
        guard let rawDate = args["date"] as? String else {
            return toolError("Missing required argument: date")
        }
        let limit = (args["limit"] as? Int) ?? 10
        let date = resolveDate(rawDate)
        let (start, end) = dayBoundsISO(for: date)

        do {
            struct AppOut: Encodable {
                let rank: Int
                let app: String
                let hours: Double
                let minutes: Double
            }
            let rows = try await dbPool.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT app_name, COALESCE(SUM(duration_seconds), 0) as total
                    FROM activity_sessions
                    WHERE started_at >= ? AND started_at < ?
                      AND is_idle = 0 AND ended_at IS NOT NULL
                    GROUP BY app_bundle_id
                    ORDER BY total DESC
                    LIMIT ?
                    """, arguments: [start, end, limit])
            }
            let out = rows.enumerated().map { idx, row -> AppOut in
                let secs = (row["total"] as? Double) ?? 0
                return AppOut(rank: idx + 1, app: row["app_name"] ?? "?",
                              hours: (secs / 3600).rounded(digits: 2),
                              minutes: (secs / 60).rounded(digits: 1))
            }
            struct Wrapper: Encodable { let date: String; let apps: [AppOut] }
            return toolJSON(Wrapper(date: rawDate, apps: out))
        } catch {
            return toolError("Query failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - ProductivityScoreTool

struct ProductivityScoreTool: AgentTool {
    let name = "productivity_score"
    let description = "Returns the 0-100 weighted productivity score for a date, plus the time breakdown by productive/neutral/distracting."
    let argsDescription = #"date: "yyyy-MM-dd" or "today"/"yesterday""#

    private let dbPool: DatabasePool

    init(dbPool: DatabasePool = DatabaseManager.shared.dbPool) {
        self.dbPool = dbPool
    }

    func run(args: [String: Any]) async -> String {
        guard let rawDate = args["date"] as? String else {
            return toolError("Missing required argument: date")
        }
        let date = resolveDate(rawDate)
        let (start, end) = dayBoundsISO(for: date)

        do {
            let rows = try await dbPool.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT COALESCE(c.is_productive, 0) as tier,
                           COALESCE(SUM(a.duration_seconds), 0) as total
                    FROM activity_sessions a
                    LEFT JOIN categories c ON a.category_id = c.id
                    WHERE a.started_at >= ? AND a.started_at < ?
                      AND a.is_idle = 0 AND a.ended_at IS NOT NULL
                    GROUP BY tier
                    """, arguments: [start, end])
            }

            var weightedSum: Double = 0
            var totalSecs: Double = 0
            var tierMap: [Int: Double] = [:]

            for row in rows {
                let tier = (row["tier"] as? Int) ?? 0
                let secs = (row["total"] as? Double) ?? 0
                weightedSum += Double(tier) * secs
                totalSecs += secs
                tierMap[tier] = secs
            }

            let score = totalSecs > 0
                ? max(0, min(100, Int(((weightedSum / totalSecs) + 2.0) / 4.0 * 100)))
                : 50

            struct Out: Encodable {
                let date: String
                let score: Int
                let total_active_minutes: Double
                let very_productive_minutes: Double
                let productive_minutes: Double
                let neutral_minutes: Double
                let distracting_minutes: Double
                let very_distracting_minutes: Double
            }
            return toolJSON(Out(
                date: rawDate,
                score: score,
                total_active_minutes: (totalSecs / 60).rounded(digits: 1),
                very_productive_minutes: ((tierMap[2] ?? 0) / 60).rounded(digits: 1),
                productive_minutes: ((tierMap[1] ?? 0) / 60).rounded(digits: 1),
                neutral_minutes: ((tierMap[0] ?? 0) / 60).rounded(digits: 1),
                distracting_minutes: ((tierMap[-1] ?? 0) / 60).rounded(digits: 1),
                very_distracting_minutes: ((tierMap[-2] ?? 0) / 60).rounded(digits: 1)
            ))
        } catch {
            return toolError("Query failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - ComparePeriodsTool

struct ComparePeriodsTool: AgentTool {
    let name = "compare_periods"
    let description = "Compares productivity scores and category time between two dates or named ranges. Good for 'this week vs last week' or 'today vs yesterday' questions."
    let argsDescription = #"period_a: "yyyy-MM-dd" or "today"/"yesterday"/"this_week"/"last_week" | period_b: same format as period_a"#

    private let dbPool: DatabasePool

    init(dbPool: DatabasePool = DatabaseManager.shared.dbPool) {
        self.dbPool = dbPool
    }

    func run(args: [String: Any]) async -> String {
        guard let rawA = args["period_a"] as? String,
              let rawB = args["period_b"] as? String else {
            return toolError("Missing required arguments: period_a and period_b")
        }

        let rangeA = buildDateRange(rawA)
        let rangeB = buildDateRange(rawB)

        do {
            func fetchCategoryTotals(start: String, end: String) async throws -> [(String, Double)] {
                try await dbPool.read { db in
                    try Row.fetchAll(db, sql: """
                        SELECT COALESCE(c.name, 'Uncategorized') as label,
                               COALESCE(SUM(a.duration_seconds), 0) as total
                        FROM activity_sessions a
                        LEFT JOIN categories c ON a.category_id = c.id
                        WHERE a.started_at >= ? AND a.started_at < ?
                          AND a.is_idle = 0 AND a.ended_at IS NOT NULL
                        GROUP BY c.id ORDER BY total DESC
                        """, arguments: [start, end])
                    .map { ($0["label"] ?? "?", $0["total"] ?? 0.0) }
                }
            }

            async let totalsA = fetchCategoryTotals(start: rangeA.start, end: rangeA.end)
            async let totalsB = fetchCategoryTotals(start: rangeB.start, end: rangeB.end)

            let (a, b) = try await (totalsA, totalsB)

            let mapA = Dictionary(uniqueKeysWithValues: a)
            let mapB = Dictionary(uniqueKeysWithValues: b)
            let allKeys = Set(mapA.keys).union(mapB.keys).sorted()

            struct DiffRow: Encodable {
                let category: String
                let period_a_minutes: Double
                let period_b_minutes: Double
                let change_minutes: Double
                let change_pct: String
            }
            let diffs = allKeys.map { key -> DiffRow in
                let secsA = mapA[key] ?? 0
                let secsB = mapB[key] ?? 0
                let delta = secsA - secsB
                let pct: String
                if secsB > 0 { pct = String(format: "%+.0f%%", (delta / secsB) * 100) }
                else if secsA > 0 { pct = "+new" }
                else { pct = "0%" }
                return DiffRow(
                    category: key,
                    period_a_minutes: (secsA / 60).rounded(digits: 1),
                    period_b_minutes: (secsB / 60).rounded(digits: 1),
                    change_minutes: (delta / 60).rounded(digits: 1),
                    change_pct: pct
                )
            }.sorted { abs($0.change_minutes) > abs($1.change_minutes) }

            struct Wrapper: Encodable {
                let period_a: String; let period_b: String
                let comparison: [DiffRow]
            }
            return toolJSON(Wrapper(period_a: rawA, period_b: rawB, comparison: diffs))
        } catch {
            return toolError("Comparison failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Shared date helpers (file-private)

private let isoDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

struct DateRange { let start: String; let end: String }

func resolveDate(_ raw: String) -> Date {
    let lower = raw.lowercased().trimmingCharacters(in: .whitespaces)
    let cal = Calendar.current
    let now = Date()
    switch lower {
    case "today": return now
    case "yesterday": return cal.date(byAdding: .day, value: -1, to: now)!
    default: return isoDateFormatter.date(from: raw) ?? now
    }
}

func dayBoundsISO(for date: Date) -> (start: String, end: String) {
    let cal = Calendar.current
    let start = cal.startOfDay(for: date)
    let end = cal.date(byAdding: .day, value: 1, to: start)!
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    fmt.timeZone = TimeZone(identifier: "UTC")!
    return (fmt.string(from: start), fmt.string(from: end))
}

func buildDateRange(_ raw: String) -> DateRange {
    let lower = raw.lowercased().trimmingCharacters(in: .whitespaces)
    let cal = Calendar.current
    let now = Date()

    switch lower {
    case "this_week":
        let startOfWeek = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let start = cal.date(from: startOfWeek)!
        let end = cal.date(byAdding: .day, value: 7, to: start)!
        let (s, _) = dayBoundsISO(for: start)
        let (_, e) = dayBoundsISO(for: cal.date(byAdding: .day, value: -1, to: end)!)
        return DateRange(start: s, end: e)
    case "last_week":
        let startOfThisWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let startOfLastWeek = cal.date(byAdding: .day, value: -7, to: startOfThisWeek)!
        let (s, _) = dayBoundsISO(for: startOfLastWeek)
        let (_, e) = dayBoundsISO(for: cal.date(byAdding: .day, value: 6, to: startOfLastWeek)!)
        return DateRange(start: s, end: e)
    default:
        let date = resolveDate(raw)
        let (s, e) = dayBoundsISO(for: date)
        return DateRange(start: s, end: e)
    }
}

private extension Double {
    func rounded(digits: Int) -> Double {
        let multiplier = pow(10.0, Double(digits))
        return (self * multiplier).rounded() / multiplier
    }
}
