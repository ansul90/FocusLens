import Foundation

struct BrowserCategoryMapper {
    private let categories: [Category]

    init(existing categories: [Category]) {
        self.categories = categories
    }

    /// Returns the category ID for the given Gemini label + tier.
    /// Resolution order:
    ///   1. Exact case-insensitive name match → use that category's ID
    ///   2. No exact match → find the best non-Browser category whose productivityScore
    ///      is closest to `tier` (ties broken by lower score)
    ///   3. If no non-Browser candidate exists → return nil (caller keeps "Browser")
    func resolve(label: String, tier: Int) -> Int64? {
        // 1. Exact name match (Browser included — caller decides whether to skip it)
        if let match = categories.first(where: {
            $0.name.caseInsensitiveCompare(label) == .orderedSame
        }) {
            return match.id
        }

        // 2. Nearest tier match among non-Browser categories; ties broken by lower score
        let nonBrowser = categories.filter {
            $0.name.caseInsensitiveCompare("Browser") != .orderedSame
        }
        let scored = nonBrowser.compactMap { cat -> (Int64, Int, Int)? in
            guard let id = cat.id else { return nil }
            return (id, abs(cat.productivityScore - tier), cat.productivityScore)
        }
        if let best = scored.min(by: { $0.1 != $1.1 ? $0.1 < $1.1 : $0.2 < $1.2 }) {
            return best.0
        }

        // 3. No non-Browser candidates — return nil so caller keeps existing category
        return nil
    }
}
