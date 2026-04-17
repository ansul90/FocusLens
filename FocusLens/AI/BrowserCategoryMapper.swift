import Foundation

struct BrowserCategoryMapper {
    private let categories: [Category]
    private let browserFallbackId: Int64?

    init(existing categories: [Category]) {
        self.categories = categories
        // Pre-find the "Browser" category for fast fallback
        self.browserFallbackId = categories.first(where: {
            $0.name.caseInsensitiveCompare("Browser") == .orderedSame
        })?.id
    }

    /// Returns the category ID for the given Gemini label + tier.
    /// Resolution order:
    ///   1. Exact case-insensitive name match → use that category's ID
    ///   2. No exact match → find the existing category whose productivityScore
    ///      is closest to `tier` (ties broken by lower score)
    ///   3. If categories list is empty → return nil
    ///   4. "Browser" category always used as the ultimate fallback when
    ///      all else fails and browserFallbackId is non-nil
    func resolve(label: String, tier: Int) -> Int64? {
        // 1. Exact name match
        if let match = categories.first(where: {
            $0.name.caseInsensitiveCompare(label) == .orderedSame
        }) {
            return match.id
        }

        // 2. Nearest tier match; ties broken by lower productivityScore
        let scored = categories.compactMap { cat -> (Int64, Int, Int)? in
            guard let id = cat.id else { return nil }
            return (id, abs(cat.productivityScore - tier), cat.productivityScore)
        }
        if let best = scored.min(by: { $0.1 != $1.1 ? $0.1 < $1.1 : $0.2 < $1.2 }) {
            return best.0
        }

        // 3. Empty list or no valid IDs, fallback to Browser
        return browserFallbackId
    }
}
