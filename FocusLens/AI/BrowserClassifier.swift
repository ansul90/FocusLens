import Foundation
import GRDB
import os

// MARK: - Protocol for testability

protocol GeminiClassifying {
    func classify(_ input: GeminiBatchRequest, allowedCategories: [String]) async throws -> GeminiBatchResponse
}

extension GeminiClient: GeminiClassifying {}

struct ClassificationResult: Sendable {
    let found: Int    // sessions matching the DB query
    let updated: Int  // sessions actually reclassified to a non-Browser category
}

// MARK: - BrowserClassifier

struct BrowserClassifier {
    private let client: any GeminiClassifying
    private let categoryStore: CategoryStore
    private let dbPool: DatabasePool
    private let logger = Logger(subsystem: "com.focuslens.app", category: "BrowserClassifier")

    init(
        client: any GeminiClassifying = GeminiClient(),
        categoryStore: CategoryStore = CategoryStore(),
        dbPool: DatabasePool = DatabaseManager.shared.dbPool
    ) {
        self.client = client
        self.categoryStore = categoryStore
        self.dbPool = dbPool
    }

    /// Fetches all browser sessions currently assigned to the "Browser" category
    /// that have a non-nil/non-empty window title, classifies them via Gemini,
    /// and updates their category_id in the database.
    /// Returns the number of sessions updated.
    @discardableResult
    func classifyPending() async throws -> ClassificationResult {
        // 1. Load all categories; find "Browser" category ID
        let categories = try categoryStore.fetchAllCategories()
        guard let browserCategory = categories.first(where: {
            $0.name.caseInsensitiveCompare("Browser") == .orderedSame
        }), let browserCategoryId = browserCategory.id else {
            logger.info("No 'Browser' category found; skipping AI classification")
            return ClassificationResult(found: 0, updated: 0)
        }

        // 2. Fetch browser sessions with category_id = Browser and non-nil window title
        let sessions: [ActivitySession] = try await dbPool.read { db in
            try ActivitySession
                .filter(ActivitySession.Columns.endedAt != nil)
                .filter(ActivitySession.Columns.isIdle == false)
                .filter(ActivitySession.Columns.categoryId == browserCategoryId)
                .filter(ActivitySession.Columns.windowTitle != nil)
                .filter(sql: "window_title != ''")
                .fetchAll(db)
        }

        guard !sessions.isEmpty else { return ClassificationResult(found: 0, updated: 0) }

        // 3. Filter out any sessions whose app already has an authoritative override —
        //    those should never have reached the Browser queue, but guard here just in case.
        let overriddenBundleIds: Set<String> = {
            let overrides = (try? categoryStore.fetchAllOverrides()) ?? []
            return Set(overrides.map { $0.appBundleId })
        }()
        let eligibleSessions = sessions.filter { !overriddenBundleIds.contains($0.appBundleId) }
        guard !eligibleSessions.isEmpty else { return ClassificationResult(found: sessions.count, updated: 0) }

        // 4. Build mapper and snapshot the allowed-category list for this batch
        let mapper = BrowserCategoryMapper(existing: categories)
        let allowedCategoryNames = categories.compactMap { $0.id != nil ? $0.name : nil }

        // 5. Process in batches
        var totalUpdated = 0
        let chunks = stride(from: 0, to: eligibleSessions.count, by: AppConstants.AI.maxBatchSize).map {
            Array(eligibleSessions[$0..<min($0 + AppConstants.AI.maxBatchSize, eligibleSessions.count)])
        }

        for chunk in chunks {
            let batchItems = chunk.enumerated().map { (index, session) in
                GeminiBatchRequest.Item(id: index, title: session.windowTitle ?? "")
            }
            let batchRequest = GeminiBatchRequest(items: batchItems)

            let response: GeminiBatchResponse
            do {
                response = try await client.classify(batchRequest, allowedCategories: allowedCategoryNames)
            } catch {
                logger.error("Gemini classification failed for chunk: \(error.localizedDescription)")
                continue  // skip chunk on error; sessions stay as "Browser"
            }

            // Map Gemini classifications back to session IDs
            let classificationMap = Dictionary(
                uniqueKeysWithValues: response.classifications.map { ($0.id, $0) }
            )

            let chunkUpdated: Int = try await dbPool.write { db in
                var count = 0
                for (index, session) in chunk.enumerated() {
                    guard let sessionId = session.id,
                          let classification = classificationMap[index],
                          let newCategoryId = mapper.resolve(
                              label: classification.category, tier: classification.tier
                          ),
                          newCategoryId != browserCategoryId
                    else { continue }

                    try db.execute(
                        sql: "UPDATE activity_sessions SET category_id = ? WHERE id = ?",
                        arguments: [newCategoryId, sessionId]
                    )
                    count += 1
                }
                return count
            }
            totalUpdated += chunkUpdated

            logger.info("BrowserClassifier: classified \(chunkUpdated) sessions in chunk")
        }

        logger.info("BrowserClassifier: \(sessions.count) found, \(eligibleSessions.count) eligible, \(totalUpdated) updated")
        return ClassificationResult(found: sessions.count, updated: totalUpdated)
    }
}
