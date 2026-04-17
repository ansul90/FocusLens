import Foundation
import GRDB

enum RuleMatchType: String, Codable, Sendable {
    case appBundle = "app_bundle"
    case windowTitleContains = "window_title_contains"
    case windowTitleRegex = "window_title_regex"
}

struct CategoryRule: Codable, Identifiable, Hashable, Sendable {
    var id: Int64?
    let categoryId: Int64
    let matchType: RuleMatchType
    let matchValue: String
    let priority: Int

    enum CodingKeys: String, CodingKey {
        case id
        case categoryId = "category_id"
        case matchType = "match_type"
        case matchValue = "match_value"
        case priority
    }
}

extension CategoryRule: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "category_rules"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let categoryId = Column(CodingKeys.categoryId)
        static let matchType = Column(CodingKeys.matchType)
        static let matchValue = Column(CodingKeys.matchValue)
        static let priority = Column(CodingKeys.priority)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
