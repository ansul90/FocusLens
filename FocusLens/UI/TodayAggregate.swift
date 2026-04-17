import Foundation
import Observation

@Observable
@MainActor
final class TodayAggregate {
    private(set) var topApps: [(appName: String, appBundleId: String, totalSeconds: Double)] = []
    private(set) var totalActiveSeconds: Double = 0
    var currentAppName: String = ""
    var isPaused: Bool = false

    private let store: ActivitySessionStore

    init(store: ActivitySessionStore = .init()) {
        self.store = store
    }

    func refreshStats() {
        topApps = (try? store.fetchTodayTopApps(limit: 10)) ?? []
        totalActiveSeconds = (try? store.fetchTodayActiveSeconds()) ?? 0
    }
}
