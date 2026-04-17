import Testing
@testable import FocusLens

@Suite("CategorizationEngine")
struct CategorizationEngineTests {

    // Helper to make rules quickly
    private func rule(id: Int64, categoryId: Int64, type: RuleMatchType, value: String, priority: Int) -> CategoryRule {
        CategoryRule(id: id, categoryId: categoryId, matchType: type, matchValue: value, priority: priority)
    }

    @Test("app_bundle exact match wins")
    func appBundleMatch() {
        let rules = [rule(id: 1, categoryId: 10, type: .appBundle, value: "com.apple.Safari", priority: 50)]
        let match = CategorizationEngine.bestMatch(rules: rules, bundleId: "com.apple.Safari", windowTitle: nil)
        #expect(match?.categoryId == 10)
    }

    @Test("no match returns nil")
    func noMatch() {
        let rules = [rule(id: 1, categoryId: 10, type: .appBundle, value: "com.apple.Safari", priority: 50)]
        let match = CategorizationEngine.bestMatch(rules: rules, bundleId: "com.google.Chrome", windowTitle: nil)
        #expect(match == nil)
    }

    @Test("higher priority wins over lower priority")
    func priorityWins() {
        let rules = [
            rule(id: 1, categoryId: 10, type: .appBundle, value: "com.apple.Safari", priority: 10),
            rule(id: 2, categoryId: 20, type: .appBundle, value: "com.apple.Safari", priority: 90),
        ]
        let match = CategorizationEngine.bestMatch(rules: rules, bundleId: "com.apple.Safari", windowTitle: nil)
        #expect(match?.categoryId == 20)
    }

    @Test("window_title_contains case-insensitive match")
    func windowTitleContains() {
        let rules = [rule(id: 1, categoryId: 10, type: .windowTitleContains, value: "github", priority: 50)]
        let match = CategorizationEngine.bestMatch(rules: rules, bundleId: "com.google.Chrome", windowTitle: "GitHub - ansul90/FocusLens")
        #expect(match?.categoryId == 10)
    }

    @Test("window_title_contains no match when title is nil")
    func windowTitleNilNoMatch() {
        let rules = [rule(id: 1, categoryId: 10, type: .windowTitleContains, value: "github", priority: 50)]
        let match = CategorizationEngine.bestMatch(rules: rules, bundleId: "com.google.Chrome", windowTitle: nil)
        #expect(match == nil)
    }

    @Test("window_title_regex match")
    func windowTitleRegex() {
        let rules = [rule(id: 1, categoryId: 10, type: .windowTitleRegex, value: "\\bYouTube\\b", priority: 50)]
        let match = CategorizationEngine.bestMatch(rules: rules, bundleId: "com.google.Chrome", windowTitle: "YouTube - Never Gonna Give You Up")
        #expect(match?.categoryId == 10)
    }

    @Test("window_title_regex invalid pattern returns nil (no crash)")
    func windowTitleRegexInvalidPattern() {
        let rules = [rule(id: 1, categoryId: 10, type: .windowTitleRegex, value: "[invalid(", priority: 50)]
        let match = CategorizationEngine.bestMatch(rules: rules, bundleId: "com.google.Chrome", windowTitle: "anything")
        #expect(match == nil)
    }

    @Test("app_bundle beats window_title_contains at equal priority")
    func appBundleTieBreak() {
        let rules = [
            rule(id: 1, categoryId: 10, type: .windowTitleContains, value: "Safari", priority: 50),
            rule(id: 2, categoryId: 20, type: .appBundle, value: "com.apple.Safari", priority: 50),
        ]
        let match = CategorizationEngine.bestMatch(rules: rules, bundleId: "com.apple.Safari", windowTitle: "Safari - Apple")
        #expect(match?.categoryId == 20)
    }

    @Test("empty rules returns nil")
    func emptyRules() {
        let match = CategorizationEngine.bestMatch(rules: [], bundleId: "com.apple.Safari", windowTitle: nil)
        #expect(match == nil)
    }
}
