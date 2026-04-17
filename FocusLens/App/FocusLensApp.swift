import SwiftUI

@main
struct FocusLensApp: App {
    @State private var aggregate = TodayAggregate()
    private let tracker = ActivityTracker()

    var body: some Scene {
        MenuBarExtra("FocusLens", systemImage: "eye") {
            MenuBarView(aggregate: aggregate, tracker: tracker)
        }
        .menuBarExtraStyle(.window)
        .task {
            await tracker.setCallbacks(
                onSessionEnded: { [aggregate] in
                    Task { @MainActor in aggregate.refreshStats() }
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
        }
    }
}
