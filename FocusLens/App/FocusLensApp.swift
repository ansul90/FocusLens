import SwiftUI
import os

@main
struct FocusLensApp: App {
    @State private var aggregate = TodayAggregate()
    @State private var rangeAggregate = RangeAggregate()
    private let tracker = ActivityTracker()
    private let categorizationEngine = CategorizationEngine()
    private let browserClassifier = BrowserClassifier()
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "FocusLensApp")

    @State private var askViewModel: AskViewModel = {
        let client = OllamaClient()
        let registry = ToolRegistry(tools: AgentRunner.defaultTools())
        let runner = AgentRunner(llm: client, registry: registry)
        return AskViewModel(runner: runner, ollamaClient: client)
    }()

    init() {
        // MenuBarExtra does not support .task — start async work here instead.
        // _aggregate and _askViewModel use State's wrappedValue which is safe to
        // access in App.init() because App-level @State is initialized exactly once.
        let agg = _aggregate.wrappedValue
        let rangeAgg = _rangeAggregate.wrappedValue
        let vm = _askViewModel.wrappedValue
        let catEngine = categorizationEngine
        let t = tracker
        let browser = browserClassifier

        Task { @MainActor in
            await t.setCallbacks(
                onSessionEnded: {
                    Task.detached {
                        try? catEngine.batchCategorize()
                        await agg.refreshStats()
                        await rangeAgg.refreshStats()
                    }
                },
                onStateChanged: { name, paused in
                    Task { @MainActor in
                        agg.currentAppName = name
                        agg.isPaused = paused
                    }
                }
            )
            LoginItemManager.registerAtLogin()
            await t.start()
            Task.detached {
                try? catEngine.batchCategorize()
                await agg.refreshStats()
                await rangeAgg.refreshStats()
            }
            Task { await vm.startMCP() }
        }

        Task { @MainActor in
            let settings = GeminiSettings()
            guard settings.isEnabled, !settings.apiKey.isEmpty else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(AppConstants.AI.reclassifyIntervalSeconds))
                guard !Task.isCancelled else { break }
                do {
                    let result = try await browser.classifyPending()
                    if result.updated > 0 {
                        Logger(subsystem: AppConstants.bundleIdentifier, category: "FocusLensApp")
                            .info("Auto-reclassify: \(result.updated) sessions updated")
                        await agg.refreshStats()
                    }
                } catch {
                    Logger(subsystem: AppConstants.bundleIdentifier, category: "FocusLensApp")
                        .error("Auto-reclassify failed: \(error.localizedDescription)")
                }
            }
        }
    }

    var body: some Scene {
        MenuBarExtra("FocusLens", systemImage: "eye") {
            MenuBarView(aggregate: aggregate, tracker: tracker)
        }
        .menuBarExtraStyle(.window)

        Window("Dashboard", id: "dashboard") {
            DashboardView()
        }
        .defaultSize(width: 760, height: 540)
        .environment(aggregate)
        .environment(rangeAggregate)
        .environment(askViewModel)
    }
}
