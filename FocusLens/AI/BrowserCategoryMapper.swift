import Foundation
import os

struct BrowserCategoryMapper {
    private let categories: [Category]
    private let logger = Logger(subsystem: "com.focuslens.app", category: "BrowserCategoryMapper")

    init(existing categories: [Category]) {
        self.categories = categories
    }

    /// Returns the category ID for the given Gemini label.
    /// Resolution: case-insensitive name match against the live category list.
    /// On miss, logs a warning with the offending label and the allowed list,
    /// then returns nil so the caller leaves the session in "Browser" — the
    /// session will then surface in the Unclassified view for manual triage.
    /// `tier` is unused for resolution but accepted for API compatibility with
    /// callers that might log it.
    func resolve(label: String, tier: Int) -> Int64? {
        if let match = categories.first(where: {
            $0.name.caseInsensitiveCompare(label) == .orderedSame
        }) {
            return match.id
        }

        let allowed = categories.map(\.name).joined(separator: ", ")
        logger.warning(
            "Gemini emitted unknown category '\(label, privacy: .public)' (tier \(tier)); allowed list was [\(allowed, privacy: .public)]. Session left in Browser."
        )
        return nil
    }
}
