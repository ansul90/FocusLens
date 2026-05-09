import Foundation
import GRDB

enum Migration009_BumpLearningScore {
    static let identifier = "v9_bump_learning_score"

    static func migrate(_ db: Database) throws {
        try db.execute(
            sql: "UPDATE categories SET is_productive = 2 WHERE name = ? COLLATE NOCASE",
            arguments: ["Learning"]
        )
    }
}
