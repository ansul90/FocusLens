import SwiftUI

struct MenuBarView: View {
    let aggregate: TodayAggregate
    let tracker: ActivityTracker

    @Environment(\.openWindow) private var openWindow
    @State private var showingQuitConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            topAppsSection
            Divider()
            controlsSection
        }
        .frame(width: 280)
        .alert("Quit FocusLens?", isPresented: $showingQuitConfirmation) {
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current session will be saved before quitting.")
        }
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
                ForEach(Array(aggregate.topApps.prefix(5)), id: \.appName) { app in
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
                if aggregate.topApps.count > 5 {
                    Button("Open Dashboard for details") {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: "dashboard")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var controlsSection: some View {
        HStack(spacing: 0) {
            toolbarButton(systemImage: "square.grid.2x2", tooltip: "Dashboard") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "dashboard")
            }
            Divider().frame(height: 16)
            toolbarButton(
                systemImage: aggregate.isPaused ? "play.fill" : "pause.fill",
                tooltip: aggregate.isPaused ? "Resume" : "Pause"
            ) {
                Task {
                    if aggregate.isPaused { await tracker.resume() }
                    else { await tracker.pause() }
                }
            }
            Divider().frame(height: 16)
            toolbarButton(systemImage: "power", tooltip: "Quit FocusLens") {
                showingQuitConfirmation = true
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func toolbarButton(
        systemImage: String,
        tooltip: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(maxWidth: .infinity)
                .frame(height: 20)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
