import Foundation
import GRDB
import os

// MARK: - Protocol for testability

protocol GeminiClassifying {
    func classify(_ input: GeminiBatchRequest) async throws -> GeminiBatchResponse
}

extension GeminiClient: GeminiClassifying {}

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
    func classifyPending() async throws -> Int {
        // 1. Load all categories; find "Browser" category ID
        let categories = try categoryStore.fetchAllCategories()
        guard let browserCategory = categories.first(where: {
            $0.name.caseInsensitiveCompare("Browser") == .orderedSame
        }), let browserCategoryId = browserCategory.id else {
            logger.info("No 'Browser' category found; skipping AI classification")
            return 0
        }

        // 2. Fetch browser sessions with category_id = Browser and non-nil window title
        let sessions: [ActivitySession] = try await dbPool.read { db in
            try ActivitySession
                .filter(ActivitySession.Columns.endedAt != nil)
                .filter(ActivitySession.Columns.isIdle == false)
                .filter(ActivitySession.Columns.categoryId == browserCategoryId)
                .filter(BrowserBundleIds.all.contains(ActivitySession.Columns.appBundleId))
                .filter(ActivitySession.Columns.windowTitle != nil)
                .filter(sql: "window_title != ''")
                .fetchAll(db)
        }

        guard !sessions.isEmpty else { return 0 }

        // 3. Build mapper
        let mapper = BrowserCategoryMapper(existing: categories)

        // 4. Process in batches
        var totalUpdated = 0
        let chunks = stride(from: 0, to: sessions.count, by: AppConstants.AI.maxBatchSize).map {
            Array(sessions[$0..<min($0 + AppConstants.AI.maxBatchSize, sessions.count)])
        }

        for chunk in chunks {
            let batchItems = chunk.enumerated().map { (index, session) in
                GeminiBatchRequest.Item(id: index, title: session.windowTitle ?? "")
            }
            let batchRequest = GeminiBatchRequest(items: batchItems)

            let response: GeminiBatchResponse
            do {
                response = try await client.classify(batchRequest)
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

        logger.info("BrowserClassifier: total \(totalUpdated) sessions updated")
        return totalUpdated
    }
}
