import SwiftUI

@main
struct FocusLensApp: App {
    @State private var aggregate = TodayAggregate()
    private let tracker = ActivityTracker()
    private let categorizationEngine = CategorizationEngine()
    private let browserClassifier = BrowserClassifier()

    @State private var askViewModel: AskViewModel = {
        let client = OllamaClient()
        let registry = ToolRegistry(tools: AgentRunner.defaultTools())
        let runner = AgentRunner(llm: client, registry: registry)
        return AskViewModel(runner: runner, ollamaClient: client)
    }()

    var body: some Scene {
        MenuBarExtra("FocusLens", systemImage: "eye") {
            MenuBarView(aggregate: aggregate, tracker: tracker)
                .task {
                    await tracker.setCallbacks(
                        onSessionEnded: { [aggregate, categorizationEngine] in
                            Task.detached {
                                try? categorizationEngine.batchCategorize()
                                await aggregate.refreshStats()
                            }
                        },
                        onStateChanged: { [aggregate] name, paused in
                            Task { @MainActor in
                                aggregate.currentAppName = name
                                aggregate.isPaused = paused
                            }
                        }
                    )
                    LoginItemManager.registerAtLogin()
                    await tracker.start()
                    Task.detached { [aggregate, categorizationEngine] in
                        try? categorizationEngine.batchCategorize()
                        await aggregate.refreshStats()
                    }
                }
        }
        .menuBarExtraStyle(.window)

        Window("Dashboard", id: "dashboard") {
            DashboardView()
        }
        .defaultSize(width: 680, height: 540)
        .environment(aggregate)
        .environment(askViewModel)

        Window("Settings", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 540, height: 420)
        .environment(aggregate)
    }
}
