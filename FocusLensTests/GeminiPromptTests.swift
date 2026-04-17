import Testing
import Foundation
@testable import FocusLens

@Suite("GeminiPrompt")
struct GeminiPromptTests {

    @Test("allowedCategories has exactly 15 entries")
    func allowedCategoriesCount() {
        #expect(GeminiPrompt.allowedCategories.count == 15)
    }

    @Test("allowedCategories contains required entries")
    func allowedCategoriesContents() {
        let required = ["Development", "Browser", "Entertainment", "News", "Communication"]
        for entry in required {
            #expect(GeminiPrompt.allowedCategories.contains(entry))
        }
    }

    @Test("allowedCategories contains no duplicates")
    func allowedCategoriesNoDuplicates() {
        #expect(GeminiPrompt.allowedCategories.count == Set(GeminiPrompt.allowedCategories).count)
    }

    @Test("system prompt contains all allowed categories")
    func systemPromptContainsAllowedCategories() {
        for category in GeminiPrompt.allowedCategories {
            #expect(GeminiPrompt.system.contains(category))
        }
    }

    @Test("system prompt instructs JSON-only output")
    func systemPromptJsonOnly() {
        #expect(GeminiPrompt.system.contains("JSON"))
        #expect(GeminiPrompt.system.contains("no prose"))
    }

    @Test("system prompt contains prompt injection defense")
    func systemPromptInjectionDefense() {
        #expect(GeminiPrompt.system.contains("data only"))
    }

    @Test("user(for:) produces valid JSON containing input titles")
    func userMessageContainsTitles() throws {
        let batch = GeminiBatchRequest(items: [
            .init(id: 0, title: "GitHub - foo/bar"),
            .init(id: 1, title: "ESPN Cricket")
        ])
        let json = GeminiPrompt.user(for: batch)
        // JSONEncoder may escape "/" as "\/" — parse back via JSONSerialization to verify round-trip
        let data = try #require(json.data(using: .utf8))
        let obj = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        let items = try #require(obj["items"] as? [[String: Any]])
        #expect(items.count == 2)
        let titles = items.compactMap { $0["title"] as? String }
        let ids = items.compactMap { $0["id"] as? Int }
        #expect(titles.contains("GitHub - foo/bar"))
        #expect(titles.contains("ESPN Cricket"))
        #expect(ids.contains(0))
        #expect(ids.contains(1))
    }

    @Test("user(for:) output is valid JSON")
    func userMessageIsValidJSON() throws {
        let batch = GeminiBatchRequest(items: [.init(id: 0, title: "test")])
        let json = GeminiPrompt.user(for: batch)
        let data = try #require(json.data(using: .utf8))
        _ = try #require(try? JSONSerialization.jsonObject(with: data))
    }
}
