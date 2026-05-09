import Foundation
import GRDB

enum Migration007_ConsolidateCategories {
    static let identifier = "v7_consolidate_categories"

    // Categories to add if missing. Productivity scores are confirmed defaults.
    private static let newCategories: [(name: String, color: String, score: Int)] = [
        ("News",     "#FFC107",  0),
        ("Social",   "#E91E63", -1),
        ("Shopping", "#FF5722", -1),
        ("Finance",  "#795548",  0),
        ("Learning", "#9C27B0",  1),
    ]

    // Window-title rules that route meeting URLs to Communication.
    // Priority 110 beats existing app_bundle rules at priority 100 for browser apps.
    private static let meetingTitleRules: [String] = [
        "Google Meet",
        "meet.google.com",
        "Zoom Meeting",
        "– Zoom",
        "Microsoft Teams Meeting",
        "Webex",
    ]

    static func migrate(_ db: Database) throws {
        try mergeOrRename(db, fromName: "Dev Tools", toName: "Development")
        try mergeOrRename(db, fromName: "AI Tools",  toName: "Development")
        try mergeOrRename(db, fromName: "Media",     toName: "Entertainment")

        for cat in newCategories {
            try insertCategoryIfMissing(db, name: cat.name, colorHex: cat.color, score: cat.score)
        }

        for value in meetingTitleRules {
            try insertRuleIfMissing(
                db,
                categoryName: "Communication",
                matchType: "window_title_contains",
                matchValue: value,
                priority: 110
            )
        }
    }

    // MARK: - Helpers

    /// If both `fromName` and `toName` exist → merge `from` into `to` (rules + sessions),
    /// then delete `from`. If only `from` exists → rename it to `to`. Otherwise no-op.
    private static func mergeOrRename(_ db: Database, fromName: String, toName: String) throws {
        let fromId = try Int64.fetchOne(
            db,
            sql: "SELECT id FROM categories WHERE name = ? COLLATE NOCASE",
            arguments: [fromName]
        )
        guard let fromId else { return }

        let toId = try Int64.fetchOne(
            db,
            sql: "SELECT id FROM categories WHERE name = ? COLLATE NOCASE",
            arguments: [toName]
        )

        if let toId {
            try db.execute(
                sql: "UPDATE activity_sessions SET category_id = ? WHERE category_id = ?",
                arguments: [toId, fromId]
            )
            try db.execute(
                sql: "UPDATE category_rules SET category_id = ? WHERE category_id = ?",
                arguments: [toId, fromId]
            )
            try db.execute(
                sql: "DELETE FROM categories WHERE id = ?",
                arguments: [fromId]
            )
        } else {
            try db.execute(
                sql: "UPDATE categories SET name = ? WHERE id = ?",
                arguments: [toName, fromId]
            )
        }
    }

    private static func insertCategoryIfMissing(
        _ db: Database, name: String, colorHex: String, score: Int
    ) throws {
        let exists = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM categories WHERE name = ? COLLATE NOCASE",
            arguments: [name]
        ) ?? 0
        guard exists == 0 else { return }
        try db.execute(
            sql: "INSERT INTO categories (name, color_hex, is_productive) VALUES (?, ?, ?)",
            arguments: [name, colorHex, score]
        )
    }

    private static func insertRuleIfMissing(
        _ db: Database,
        categoryName: String,
        matchType: String,
        matchValue: String,
        priority: Int
    ) throws {
        guard let categoryId = try Int64.fetchOne(
            db,
            sql: "SELECT id FROM categories WHERE name = ? COLLATE NOCASE",
            arguments: [categoryName]
        ) else { return }

        let exists = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) FROM category_rules
                WHERE category_id = ? AND match_type = ? AND match_value = ?
                """,
            arguments: [categoryId, matchType, matchValue]
        ) ?? 0
        guard exists == 0 else { return }

        try db.execute(
            sql: """
                INSERT INTO category_rules (category_id, match_type, match_value, priority)
                VALUES (?, ?, ?, ?)
                """,
            arguments: [categoryId, matchType, matchValue, priority]
        )
    }
}
