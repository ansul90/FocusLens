import Testing
import Foundation
import GRDB
@testable import FocusLens

// MARK: - Fake clients

struct FakeGeminiClient: GeminiClassifying {
    let response: GeminiBatchResponse

    func classify(_ input: GeminiBatchRequest, allowedCategories: [String]) async throws -> GeminiBatchResponse {
        response
    }
}

struct FailingGeminiClient: GeminiClassifying {
    func classify(_ input: GeminiBatchRequest, allowedCategories: [String]) async throws -> GeminiBatchResponse {
        throw GeminiError.httpStatus(503)
    }
}

// MARK: - GeminiClassification JSON helper

private func makeClassification(id: Int, category: String, tier: Int) throws -> GeminiClassification {
    let json = "{\"id\":\(id),\"category\":\"\(category)\",\"tier\":\(tier)}"
    return try JSONDecoder().decode(GeminiClassification.self, from: json.data(using: .utf8)!)
}

// MARK: - Database helpers

// DatabasePool requires WAL mode which is not supported on :memory:.
// Use a unique temp-file path for each test pool instead.
private func makeTestPool() throws -> DatabasePool {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("focuslens-test-\(UUID().uuidString).sqlite")
    let pool = try DatabasePool(path: url.path)
    var migrator = DatabaseMigrator()
    migrator.registerMigration(Migration001_Sessions.identifier, migrate: Migration001_Sessions.migrate)
    migrator.registerMigration(Migration002_Categories.identifier, migrate: Migration002_Categories.migrate)
    try migrator.migrate(pool)
    return pool
}

private func insertCategory(_ pool: DatabasePool, name: String, score: Int) throws -> Int64 {
    try pool.write { db in
        try db.execute(
            sql: "INSERT INTO categories (name, color_hex, is_productive) VALUES (?, '#000000', ?)",
            arguments: [name, score]
        )
        return db.lastInsertedRowID
    }
}

private func insertSession(
    _ pool: DatabasePool,
    bundleId: String,
    title: String?,
    categoryId: Int64?
) throws -> Int64 {
    try pool.write { db in
        try db.execute(
            sql: """
                INSERT INTO activity_sessions
                  (app_bundle_id, app_name, window_title, started_at, ended_at, duration_seconds, is_idle, category_id)
                VALUES (?, ?, ?, '2026-01-01 09:00:00.000', '2026-01-01 09:05:00.000', 300, 0, ?)
                """,
            arguments: [bundleId, "App", title, categoryId]
        )
        return db.lastInsertedRowID
    }
}

private func fetchCategoryId(_ pool: DatabasePool, sessionId: Int64) throws -> Int64? {
    try pool.read { db in
        let row = try Row.fetchOne(
            db,
            sql: "SELECT category_id FROM activity_sessions WHERE id = ?",
            arguments: [sessionId]
        )
        return row?["category_id"]
    }
}

// MARK: - Tests

@Suite("BrowserClassifier")
struct BrowserClassifierTests {

    @Test("classifyPending updates browser sessions with non-nil titles")
    func classifyPendingUpdatesBrowserSessions() async throws {
        let pool = try makeTestPool()
        let browserId = try insertCategory(pool, name: "Browser", score: 0)
        let devId = try insertCategory(pool, name: "Development", score: 2)
        // A distinct category for Xcode so its "unchanged" assertion can't accidentally pass
        let codingId = try insertCategory(pool, name: "Coding", score: 2)

        // Browser session with title → should be reclassified to Development
        let sessionId = try insertSession(
            pool,
            bundleId: "com.google.Chrome",
            title: "GitHub - foo/bar",
            categoryId: browserId
        )
        // Xcode session (not a browser bundle) → must NOT be touched by classifier
        let xcodeId = try insertSession(
            pool,
            bundleId: "com.apple.dt.Xcode",
            title: "Xcode",
            categoryId: codingId
        )

        let classification = try makeClassification(id: 0, category: "Development", tier: 2)
        let fakeResponse = GeminiBatchResponse(classifications: [classification])
        let fakeClient = FakeGeminiClient(response: fakeResponse)
        let store = CategoryStore(dbPool: pool)
        let classifier = BrowserClassifier(client: fakeClient, categoryStore: store, dbPool: pool)

        let result = try await classifier.classifyPending()
        #expect(result.found == 1)
        #expect(result.updated == 1)
        #expect(try fetchCategoryId(pool, sessionId: sessionId) == devId)
        #expect(try fetchCategoryId(pool, sessionId: xcodeId) == codingId) // unchanged — distinct from devId
    }

    @Test("classifyPending skips sessions with nil window_title")
    func classifyPendingSkipsNilTitle() async throws {
        let pool = try makeTestPool()
        let browserId = try insertCategory(pool, name: "Browser", score: 0)
        let sessionId = try insertSession(
            pool,
            bundleId: "com.google.Chrome",
            title: nil,
            categoryId: browserId
        )
        let fakeClient = FakeGeminiClient(response: GeminiBatchResponse(classifications: []))
        let store = CategoryStore(dbPool: pool)
        let classifier = BrowserClassifier(client: fakeClient, categoryStore: store, dbPool: pool)

        let result = try await classifier.classifyPending()
        #expect(result.found == 0)
        #expect(result.updated == 0)
        #expect(try fetchCategoryId(pool, sessionId: sessionId) == browserId)
    }

    @Test("classifyPending returns 0 when no Browser category exists")
    func classifyPendingReturnZeroWhenNoBrowserCategory() async throws {
        let pool = try makeTestPool()
        let fakeClient = FakeGeminiClient(response: GeminiBatchResponse(classifications: []))
        let store = CategoryStore(dbPool: pool)
        let classifier = BrowserClassifier(client: fakeClient, categoryStore: store, dbPool: pool)
        let result = try await classifier.classifyPending()
        #expect(result.found == 0)
        #expect(result.updated == 0)
    }

    @Test("classifyPending continues when client throws for a chunk")
    func classifyPendingContinuesOnChunkError() async throws {
        let pool = try makeTestPool()
        let browserId = try insertCategory(pool, name: "Browser", score: 0)
        let sessionId = try insertSession(
            pool,
            bundleId: "com.google.Chrome",
            title: "GitHub",
            categoryId: browserId
        )
        let failClient = FailingGeminiClient()
        let store = CategoryStore(dbPool: pool)
        let classifier = BrowserClassifier(client: failClient, categoryStore: store, dbPool: pool)

        let result = try await classifier.classifyPending()
        #expect(result.found == 1)
        #expect(result.updated == 0) // chunk failed, session untouched
        #expect(try fetchCategoryId(pool, sessionId: sessionId) == browserId)
    }
}
