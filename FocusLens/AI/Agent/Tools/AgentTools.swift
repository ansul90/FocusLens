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

// MARK: - GetActivityTool

struct GetActivityTool: AgentTool {
    let name = "get_activity"
    let description = "Returns top apps, category time breakdown, and productivity score (0-100) for a date or date range. Use for any question about time spent, top apps, categories, or productivity."
    let argsDescription = #"start: "yyyy-MM-dd" or "today"/"yesterday"/"this_week"/"last_week" | end: "yyyy-MM-dd" (optional, defaults to same day as start)"#

    private let dbPool: DatabasePool

    init(dbPool: DatabasePool = DatabaseManager.shared.dbPool) {
        self.dbPool = dbPool
    }

    func run(args: [String: Any]) async -> String {
        guard let rawStart = args["start"] as? String else {
            return toolError("Missing required argument: start")
        }

        let rawEnd = args["end"] as? String
        let range: DateRange
        if let end = rawEnd {
            let (s, _) = dayBoundsISO(for: resolveDate(rawStart))
            let (_, e) = dayBoundsISO(for: resolveDate(end))
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

        let lower = rawDate.lowercased().trimmingCharacters(in: .whitespaces)
        if lower == "this_week" || lower == "last_week" {
            return toolError("query_sessions only accepts single dates (e.g. today, yesterday, 2026-05-08). Use get_activity for week ranges.")
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

// MARK: - ClassifyAppTool

struct ClassifyAppTool: AgentTool {
    let name = "classify_app"
    let description = "Classifies an app as productive, neutral, or distracting using AI. Checks a local cache first; on a cache miss it calls Gemini and stores the result. Requires Gemini API key in Settings → AI."
    let argsDescription = #"app_name: string"#

    private let gemini: any GeminiClassifying
    private let insights: AppInsightsStore
    private let categoryStore: CategoryStore

    init(
        gemini: any GeminiClassifying = GeminiClient(),
        insights: AppInsightsStore = AppInsightsStore(),
        categoryStore: CategoryStore = CategoryStore()
    ) {
        self.gemini = gemini
        self.insights = insights
        self.categoryStore = categoryStore
    }

    func run(args: [String: Any]) async -> String {
        guard let appName = args["app_name"] as? String, !appName.isEmpty else {
            return toolError("Missing required argument: app_name")
        }

        // Cache hit
        if let cached = try? await insights.fetch(appName: appName) {
            struct Out: Encodable {
                let app_name: String; let verdict: String; let summary: String; let cached: Bool
            }
            return toolJSON(Out(app_name: cached.appName, verdict: cached.verdict, summary: cached.summary, cached: true))
        }

        // Cache miss — classify via Gemini
        let request = GeminiBatchRequest(items: [GeminiBatchRequest.Item(id: 0, title: appName)])
        let allowedCategories: [String] = (try? categoryStore.fetchAllCategories().compactMap {
            $0.id != nil ? $0.name : nil
        }) ?? []
        do {
            let response = try await gemini.classify(request, allowedCategories: allowedCategories)
            guard let classification = response.classifications.first else {
                return toolError("Gemini returned no classification for '\(appName)'")
            }
            let verdict: String
            switch classification.tier {
            case 1...2:   verdict = "productive"
            case (-2)...(-1): verdict = "distracting"
            default:      verdict = "neutral"
            }
            let summary = "\(classification.category) app, productivity tier \(classification.tier)"
            try? await insights.upsert(appName: appName, verdict: verdict, summary: summary)

            struct Out: Encodable {
                let app_name: String; let verdict: String; let category: String
                let tier: Int; let cached: Bool
            }
            return toolJSON(Out(
                app_name: appName, verdict: verdict,
                category: classification.category, tier: classification.tier, cached: false
            ))
        } catch GeminiError.missingKey {
            return toolError("Gemini API not configured — set your API key in Settings → AI.")
        } catch {
            return toolError("Classification failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Shared date helpers

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
