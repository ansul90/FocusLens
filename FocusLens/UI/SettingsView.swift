import SwiftUI
import os

// MARK: - General tab

struct GeneralSettingsTab: View {
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

struct NeverTrackTab: View {
    @State private var bundleIds: [String] = []
    @State private var titleEntries: [(appBundleId: String, windowTitle: String)] = []
    @State private var newBundleId = ""
    @State private var store = NeverTrackStore()
    @State private var errorMessage: String?

    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "NeverTrack")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                Section {
                    ForEach(bundleIds, id: \.self) { bundleId in
                        Text(bundleId)
                            .font(.callout)
                    }
                    .onDelete { offsets in
                        for i in offsets {
                            do { try store.remove(bundleId: bundleIds[i]) }
                            catch { errorMessage = error.localizedDescription }
                        }
                        load()
                    }
                } header: {
                    Text("APPS")
                }

                Section {
                    if titleEntries.isEmpty {
                        Text("No titles blocked yet — use \"Never Track\" in Session Browser.")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(Array(titleEntries.enumerated()), id: \.offset) { _, entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.windowTitle)
                                    .font(.callout)
                                    .lineLimit(2)
                                Text(entry.appBundleId)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets {
                                let entry = titleEntries[i]
                                do { try store.removeTitle(bundleId: entry.appBundleId, title: entry.windowTitle) }
                                catch { errorMessage = error.localizedDescription }
                            }
                            load()
                        }
                    }
                } header: {
                    Text("TITLES")
                }
            }
            .listStyle(.inset)

            HStack {
                TextField("com.example.App", text: $newBundleId)
                    .textFieldStyle(.roundedBorder)
                Button("Add App") {
                    let trimmed = newBundleId.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    do {
                        try store.add(bundleId: trimmed)
                        newBundleId = ""
                        load()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .disabled(newBundleId.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .onAppear { load() }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        ), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
    }

    private func load() {
        do {
            bundleIds = try store.fetchAll()
            titleEntries = try store.fetchAllTitles()
        } catch {
            logger.error("Failed to load never-track list: \(error.localizedDescription)")
        }
    }
}
