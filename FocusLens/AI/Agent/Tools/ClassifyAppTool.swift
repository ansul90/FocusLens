import Foundation

struct ClassifyAppTool: AgentTool {
    let name = "classify_app"
    let description = "Classifies an app as productive, neutral, or distracting using AI. Checks a local cache first; on a cache miss it calls Gemini and stores the result. Requires Gemini API key in Settings → AI."
    let argsDescription = #"app_name: string"#

    private let gemini: any GeminiClassifying
    private let insights: AppInsightsStore
    private let categoryStore: CategoryStore

    init(
        gemini: any GeminiClassifying = GeminiClient(),
        insights: AppInsightsStore = AppInsightsStore(),
        categoryStore: CategoryStore = CategoryStore()
    ) {
        self.gemini = gemini
        self.insights = insights
        self.categoryStore = categoryStore
    }

    func run(args: [String: Any]) async -> String {
        guard let appName = args["app_name"] as? String, !appName.isEmpty else {
            return toolError("Missing required argument: app_name")
        }

        // Cache hit
        if let cached = try? await insights.fetch(appName: appName) {
            struct Out: Encodable {
                let app_name: String; let verdict: String; let summary: String; let cached: Bool
            }
            return toolJSON(Out(app_name: cached.appName, verdict: cached.verdict, summary: cached.summary, cached: true))
        }

        // Cache miss — classify via Gemini
        let request = GeminiBatchRequest(items: [GeminiBatchRequest.Item(id: 0, title: appName)])
        let allowedCategories: [String] = (try? categoryStore.fetchAllCategories().compactMap {
            $0.id != nil ? $0.name : nil
        }) ?? []
        do {
            let response = try await gemini.classify(request, allowedCategories: allowedCategories)
            guard let classification = response.classifications.first else {
                return toolError("Gemini returned no classification for '\(appName)'")
            }
            let verdict: String
            switch classification.tier {
            case 1...2:   verdict = "productive"
            case (-2)...(-1): verdict = "distracting"
            default:      verdict = "neutral"
            }
            let summary = "\(classification.category) app, productivity tier \(classification.tier)"
            try? await insights.upsert(appName: appName, verdict: verdict, summary: summary)

            struct Out: Encodable {
                let app_name: String; let verdict: String; let category: String
                let tier: Int; let cached: Bool
            }
            return toolJSON(Out(
                app_name: appName, verdict: verdict,
                category: classification.category, tier: classification.tier, cached: false
            ))
        } catch GeminiError.missingKey {
            return toolError("Gemini API not configured — set your API key in Settings → AI.")
        } catch {
            return toolError("Classification failed: \(error.localizedDescription)")
        }
    }
}
