import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
            CategorySettingsView()
                .tabItem { Label("Categories", systemImage: "tag") }
            NeverTrackTab()
                .tabItem { Label("Never Track", systemImage: "eye.slash") }
        }
        .frame(minWidth: 520, minHeight: 380)
        .padding(8)
    }
}

// MARK: - General tab

private struct GeneralSettingsTab: View {
    var body: some View {
        Form {
            Section("Tracking") {
                LabeledContent("Idle threshold") {
                    Text(DurationFormatter.string(from: AppConstants.idleThresholdSeconds))
                }
                LabeledContent("Minimum session") {
                    Text(DurationFormatter.string(from: AppConstants.minimumSessionSeconds))
                }
                Text("Edit AppConstants.swift to change thresholds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Never-Track tab

private struct NeverTrackTab: View {
    @State private var bundleIds: [String] = []
    @State private var newBundleId = ""
    private let store = NeverTrackStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                ForEach(bundleIds, id: \.self) { bundleId in
                    Text(bundleId)
                }
                .onDelete { offsets in
                    for i in offsets { try? store.remove(bundleId: bundleIds[i]) }
                    load()
                }
            }
            HStack {
                TextField("com.example.App", text: $newBundleId)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let trimmed = newBundleId.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    try? store.add(bundleId: trimmed)
                    newBundleId = ""
                    load()
                }
                .disabled(newBundleId.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .onAppear { load() }
    }

    private func load() {
        bundleIds = (try? store.fetchAll()) ?? []
    }
}
