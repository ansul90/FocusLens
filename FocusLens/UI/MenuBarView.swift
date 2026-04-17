import SwiftUI

struct MenuBarView: View {
    let aggregate: TodayAggregate
    let tracker: ActivityTracker

    @State private var tickCount = 0
    private let timer = Timer.publish(every: AppConstants.menuRefreshIntervalSeconds, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            topAppsSection
            Divider()
            controlsSection
        }
        .frame(width: 280)
        .onReceive(timer) { _ in tickCount += 1 }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(aggregate.currentAppName.isEmpty ? "No active app" : aggregate.currentAppName)
                .font(.headline)
            Text("Today: \(DurationFormatter.string(from: aggregate.totalActiveSeconds))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var topAppsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if aggregate.topApps.isEmpty {
                Text("No activity yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(aggregate.topApps.indices, id: \.self) { i in
                    let app = aggregate.topApps[i]
                    HStack {
                        Text(app.appName)
                            .lineLimit(1)
                        Spacer()
                        Text(DurationFormatter.string(from: app.totalSeconds))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var controlsSection: some View {
        HStack {
            Button(aggregate.isPaused ? "Resume" : "Pause") {
                Task {
                    if aggregate.isPaused {
                        await tracker.resume()
                    } else {
                        await tracker.pause()
                    }
                }
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
