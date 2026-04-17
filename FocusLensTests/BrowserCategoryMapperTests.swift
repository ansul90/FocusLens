import Testing
@testable import FocusLens

@Suite("BrowserCategoryMapper")
struct BrowserCategoryMapperTests {

    // Helper: make a Category with an id
    private func cat(id: Int64, name: String, score: Int) -> Category {
        Category(id: id, name: name, colorHex: "#000000", productivityScore: score)
    }

    @Test("exact case-insensitive name match returns correct id")
    func exactMatchCaseInsensitive() {
        let cats = [cat(id: 1, name: "Development", score: 2), cat(id: 2, name: "Browser", score: 0)]
        let mapper = BrowserCategoryMapper(existing: cats)
        #expect(mapper.resolve(label: "development", tier: 0) == 1)
        #expect(mapper.resolve(label: "DEVELOPMENT", tier: 0) == 1)
    }

    @Test("no exact match falls back to nearest tier")
    func nearestTierFallback() {
        let cats = [cat(id: 1, name: "Development", score: 2), cat(id: 2, name: "Media", score: -1)]
        let mapper = BrowserCategoryMapper(existing: cats)
        // tier = -2, nearest score is -1 (Media)
        #expect(mapper.resolve(label: "Entertainment", tier: -2) == 2)
    }

    @Test("tie-breaking: lower score wins")
    func tieBrokenByLowerScore() {
        // score -1 and +1 are equidistant from tier 0
        let cats = [cat(id: 1, name: "Productive", score: 1), cat(id: 2, name: "Distracting", score: -1)]
        let mapper = BrowserCategoryMapper(existing: cats)
        // lower score (-1) should win on tie
        #expect(mapper.resolve(label: "Unknown", tier: 0) == 2)
    }

    @Test("empty categories returns nil")
    func emptyListReturnsNil() {
        let mapper = BrowserCategoryMapper(existing: [])
        #expect(mapper.resolve(label: "Browser", tier: 0) == nil)
    }

    @Test("categories with nil ids are skipped in tier fallback")
    func nilIdCategoriesSkipped() {
        let noId = Category(id: nil, name: "NoId", colorHex: "#000", productivityScore: 0)
        let withId = cat(id: 5, name: "HasId", score: 1)
        let mapper = BrowserCategoryMapper(existing: [noId, withId])
        #expect(mapper.resolve(label: "Nonexistent", tier: 0) == 5)
    }

    @Test("Browser fallback used when all non-Browser categories have nil ids")
    func browserFallback() {
        // nil-id categories are skipped in tier fallback (step 2), so step 3 (browserFallbackId) fires
        let nilId = Category(id: nil, name: "Misc", colorHex: "#000", productivityScore: 0)
        let browser = cat(id: 3, name: "Browser", score: 0)
        let mapper = BrowserCategoryMapper(existing: [nilId, browser])
        #expect(mapper.resolve(label: "News", tier: 0) == 3)
    }
}
