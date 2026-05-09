import Testing
@testable import FocusLens

@Suite("BrowserCategoryMapper")
struct BrowserCategoryMapperTests {

    private func cat(id: Int64, name: String, score: Int = 0) -> Category {
        Category(id: id, name: name, colorHex: "#000000", productivityScore: score)
    }

    @Test("exact case-insensitive name match returns correct id")
    func exactMatchCaseInsensitive() {
        let cats = [cat(id: 1, name: "Development", score: 2), cat(id: 2, name: "Browser")]
        let mapper = BrowserCategoryMapper(existing: cats)
        #expect(mapper.resolve(label: "development", tier: 0) == 1)
        #expect(mapper.resolve(label: "DEVELOPMENT", tier: 0) == 1)
        #expect(mapper.resolve(label: "Development", tier: 0) == 1)
    }

    @Test("returns nil when label not in category list")
    func unknownLabelReturnsNil() {
        let cats = [cat(id: 1, name: "Development", score: 2), cat(id: 2, name: "Browser")]
        let mapper = BrowserCategoryMapper(existing: cats)
        #expect(mapper.resolve(label: "Reddit", tier: -1) == nil)
        #expect(mapper.resolve(label: "Entertainment", tier: -2) == nil)
    }

    @Test("empty category list returns nil")
    func emptyListReturnsNil() {
        let mapper = BrowserCategoryMapper(existing: [])
        #expect(mapper.resolve(label: "Browser", tier: 0) == nil)
    }

    @Test("returns nil when matched category has no id")
    func nilIdMatchReturnsNil() {
        let noId = Category(id: nil, name: "News", colorHex: "#000", productivityScore: 0)
        let mapper = BrowserCategoryMapper(existing: [noId])
        #expect(mapper.resolve(label: "News", tier: 0) == nil)
    }

    @Test("Browser is a valid match target — caller decides skip semantics")
    func browserMatchReturnsItsId() {
        let cats = [cat(id: 14, name: "Browser")]
        let mapper = BrowserCategoryMapper(existing: cats)
        #expect(mapper.resolve(label: "Browser", tier: 0) == 14)
    }
}
