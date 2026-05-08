import Foundation
import GRDB

enum Migration005_FixBrowserRules {
    static let identifier = "v5_fix_browser_rules"

    // Browser bundle IDs that must always map to the Browser category, never Development or other.
    private static let browserBundles: [String] = [
        "com.google.Chrome",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.apple.Safari",
        "ai.perplexity.comet",
    ]

    static func migrate(_ db: Database) throws {
        guard let browserCategoryId = try Int64.fetchOne(
            db, sql: "SELECT id FROM categories WHERE name = 'Browser' COLLATE NOCASE"
        ) else { return }

        for bundle in browserBundles {
            // Remove any rules that point this bundle at a non-Browser category.
            try db.execute(
                sql: """
                DELETE FROM category_rules
                WHERE match_type = 'app_bundle'
                  AND match_value = ?
                  AND category_id != ?
                """,
                arguments: [bundle, browserCategoryId]
            )

            // Ensure a Browser rule exists for this bundle.
            let exists = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*) FROM category_rules
                WHERE match_type = 'app_bundle'
                  AND match_value = ?
                  AND category_id = ?
                """,
                arguments: [bundle, browserCategoryId]
            ) ?? 0
            if exists == 0 {
                try db.execute(
                    sql: """
                    INSERT INTO category_rules (category_id, match_type, match_value, priority)
                    VALUES (?, 'app_bundle', ?, 100)
                    """,
                    arguments: [browserCategoryId, bundle]
                )
            }

            // Re-tag any sessions for this bundle that were mis-categorized as non-Browser
            // (excluding Media, which the AI classifier may have correctly assigned).
            try db.execute(
                sql: """
                UPDATE activity_sessions
                SET category_id = ?
                WHERE app_bundle_id = ?
                  AND category_id != ?
                  AND category_id NOT IN (
                      SELECT id FROM categories WHERE name = 'Media' COLLATE NOCASE
                  )
                  AND category_id IS NOT NULL
                """,
                arguments: [browserCategoryId, bundle, browserCategoryId]
            )
        }
    }
}
