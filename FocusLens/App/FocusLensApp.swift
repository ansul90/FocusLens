import SwiftUI
import os

@main
struct FocusLensApp: App {
    @State private var aggregate = TodayAggregate()
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

    var body: some Scene {
        MenuBarExtra("FocusLens", systemImage: "eye") {
            MenuBarView(aggregate: aggregate, tracker: tracker)
        }
        .menuBarExtraStyle(.window)
        .task {
            // Scene-level task fires at app launch, not when the popover is opened.
            // View-level .task on MenuBarView only runs when the user clicks the icon,
            // leaving the tracker dormant if the app is relaunched without interaction.
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
        .task {
            await runReclassifyLoop()
        }

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

    @MainActor
    private func runReclassifyLoop() async {
        let settings = GeminiSettings()
        guard settings.isEnabled, !settings.apiKey.isEmpty else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(AppConstants.AI.reclassifyIntervalSeconds))
            guard !Task.isCancelled else { break }
            do {
                let result = try await browserClassifier.classifyPending()
                if result.updated > 0 {
                    logger.info("Auto-reclassify: \(result.updated) sessions updated")
                    await aggregate.refreshStats()
                }
            } catch {
                logger.error("Auto-reclassify failed: \(error.localizedDescription)")
            }
        }
    }
}
