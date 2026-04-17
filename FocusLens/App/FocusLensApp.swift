import SwiftUI

@main
struct FocusLensApp: App {
    @State private var aggregate = TodayAggregate()
    private let tracker = ActivityTracker()
    private let categorizationEngine = CategorizationEngine()
    private let browserClassifier = BrowserClassifier()

    var body: some Scene {
        MenuBarExtra("FocusLens", systemImage: "eye") {
            MenuBarView(aggregate: aggregate, tracker: tracker)
                .task {
                    await tracker.setCallbacks(
                        onSessionEnded: { [aggregate, categorizationEngine] in
                            Task.detached {
                                try? categorizationEngine.batchCategorize()
                                // Gemini classification on session-end disabled; runs at app launch only
//                                if GeminiSettings().hasValidKey {
//                                    try? await browserClassifier.classifyPending()
//                                }
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
                        // Gemini classification on app-launch disabled; runs only on manual Reclassify Now
//                        if GeminiSettings().hasValidKey {
//                            try? await browserClassifier.classifyPending()
//                        }
                        await aggregate.refreshStats()
                    }
                }
        }
        .menuBarExtraStyle(.window)

        Window("Dashboard", id: "dashboard") {
            DashboardView()
        }
        .defaultSize(width: 680, height: 500)
        .environment(aggregate)

        Window("Settings", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 540, height: 420)
    }
}
