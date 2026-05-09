import SwiftUI
import GRDB
import os

// MARK: - Tab container for the Categories section

struct CategoriesTabView: View {
    enum Tab { case categories, unclassified, overrides }

    @State private var tab: Tab = .categories
    @State private var unclassifiedCount = 0
    @State private var overridesCount = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Picker("", selection: $tab) {
                    Text("Categories").tag(Tab.categories)
                    Text(unclassifiedCount > 0
                         ? "Unclassified (\(unclassifiedCount))"
                         : "Unclassified").tag(Tab.unclassified)
                    Text(overridesCount > 0
                         ? "Overrides (\(overridesCount))"
                         : "Overrides").tag(Tab.overrides)
                }
                .pickerStyle(.segmented)
                .frame(width: 440)
                Spacer()
            }
            .padding(.vertical, 8)
            Divider()
            switch tab {
            case .categories:   CategorySettingsView()
            case .unclassified: UnclassifiedSessionsView()
            case .overrides:    OverridesView()
            }
        }
        .onAppear { refreshCounts() }
        .onChange(of: tab) { _, _ in refreshCounts() }
    }

    private func refreshCounts() {
        let pool = DatabaseManager.shared.dbPool
        unclassifiedCount = (try? pool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM activity_sessions WHERE category_id IS NULL AND is_idle = 0 AND ended_at IS NOT NULL"
            ) ?? 0
        }) ?? 0
        overridesCount = (try? pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM category_overrides") ?? 0
        }) ?? 0
    }
}

// MARK: - Unclassified sessions view

struct UnclassifiedSessionsView: View {

    struct AppGroup: Identifiable {
        var id: String { appBundleId }
        let appBundleId: String
        let appName: String
        let sessions: [ActivitySession]
        var sessionCount: Int { sessions.count }
        var totalDuration: Double { sessions.compactMap { $0.durationSeconds }.reduce(0, +) }
        var previewTitles: [String] {
            Array(
                sessions
                    .compactMap { $0.windowTitle }
                    .filter { !$0.isEmpty }
                    .uniqued()
                    .prefix(2)
            )
        }
    }

    @State private var groups: [AppGroup] = []
    @State private var categories: [Category] = []
    @State private var errorMessage: String?

    private let store = CategoryStore()
    private let svc = RuleAuthoringService()
    private let dbPool = DatabaseManager.shared.dbPool
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Unclassified")

    var body: some View {
        VStack(spacing: 0) {
            statsBar
            Divider()
            if groups.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .onAppear { reload() }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sub-views

    private var statsBar: some View {
        HStack {
            let total = groups.reduce(0) { $0 + $1.sessionCount }
            Text(total == 0
                 ? "All sessions classified"
                 : "\(groups.count) apps · \(total) sessions need a category")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Refresh") { reload() }
                .controlSize(.small)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("All sessions are classified")
                .fontWeight(.medium)
            Text("New unclassified sessions will appear here for review.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sessionList: some View {
        List {
            ForEach(groups) { group in
                groupRow(group)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        .listStyle(.inset)
    }

    private func groupRow(_ group: AppGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.appName)
                        .fontWeight(.medium)
                    Text(group.appBundleId)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(group.sessionCount) session\(group.sessionCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(DurationFormatter.string(from: group.totalDuration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // Window title preview
            if !group.previewTitles.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(group.previewTitles, id: \.self) { title in
                        Label(title, systemImage: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    let remaining = group.sessionCount - group.previewTitles.count
                    if remaining > 0 {
                        Text("+ \(remaining) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Action buttons
            HStack(spacing: 8) {
                categoryPickerMenu(
                    label: "Override App",
                    systemImage: "lock.shield",
                    categories: categories
                ) { cat in
                    overrideApp(group.appBundleId, with: cat)
                }

                Spacer()
            }
        }
    }

    private func categoryPickerMenu(
        label: String,
        systemImage: String,
        categories: [Category],
        onSelect: @escaping (Category) -> Void
    ) -> some View {
        Menu {
            if categories.isEmpty {
                Text("No categories").foregroundStyle(.secondary)
            } else {
                ForEach(categories) { cat in
                    Button {
                        onSelect(cat)
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(hex: cat.colorHex) ?? .gray)
                                .frame(width: 8, height: 8)
                            Text(cat.name)
                        }
                    }
                }
            }
        } label: {
            Label(label, systemImage: systemImage)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Actions

    private func reload() {
        do {
            categories = try store.fetchAllCategories()
            let sessions: [ActivitySession] = try dbPool.read { db in
                try ActivitySession
                    .filter(ActivitySession.Columns.categoryId == nil)
                    .filter(ActivitySession.Columns.isIdle == false)
                    .filter(ActivitySession.Columns.endedAt != nil)
                    .order(ActivitySession.Columns.startedAt.desc)
                    .fetchAll(db)
            }
            let grouped = Dictionary(grouping: sessions, by: { $0.appBundleId })
            groups = grouped
                .map { bundleId, sessions in
                    AppGroup(
                        appBundleId: bundleId,
                        appName: sessions.first?.appName ?? bundleId,
                        sessions: sessions
                    )
                }
                .sorted { $0.sessionCount > $1.sessionCount }
        } catch {
            logger.error("Failed to load unclassified sessions: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    private func overrideApp(_ bundleId: String, with category: Category) {
        guard let catId = category.id else { return }
        do {
            _ = try svc.applyOverride(appBundleId: bundleId, categoryId: catId)
            logger.info("Override set: \(bundleId) → \(category.name)")
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Sequence helper

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
