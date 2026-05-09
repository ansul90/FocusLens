import SwiftUI
import GRDB
import os

struct SessionBrowserView: View {

    // MARK: - Row models

    struct WindowRow: Identifiable {
        var id: String { "\(appBundleId)|\(windowTitle)" }
        let appBundleId: String
        let appName: String
        let windowTitle: String
        let categoryId: Int64?
        let sessionCount: Int
        let pendingCount: Int
        let totalSeconds: Double
        let latestEndedAt: Date?
    }

    struct AppGroup: Identifiable {
        var id: String { appBundleId }
        let appBundleId: String
        let appName: String
        let windows: [WindowRow]
        var sessionCount: Int { windows.reduce(0) { $0 + $1.sessionCount } }
        var totalSeconds: Double { windows.reduce(0) { $0 + $1.totalSeconds } }
    }

    private static let resolvedRowLimit = 20

    private static let dbDateFormatter = DateUtils.dbTimestampFormatter()

    private static let resolvedDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    // MARK: - State

    @State private var allGroups: [AppGroup] = []
    @State private var resolvedRows: [WindowRow] = []
    @State private var ignoredRows: [WindowRow] = []
    @State private var ignoredKeys: Set<String> = []
    @State private var categories: [Category] = []
    @State private var categoriesById: [Int64: Category] = [:]
    @State private var browserCategoryId: Int64?
    @State private var searchText = ""
    @State private var showIgnored = false
    @State private var errorMessage: String?

    // Create Rule inline form
    @State private var creatingRuleFor: WindowRow?
    @State private var newRuleCategoryId: Int64?
    @State private var newRulePriority = 50
    @State private var rulePreviewCount: Int?

    // Never Track confirmation
    @State private var neverTrackTarget: WindowRow?
    @State private var neverTrackSessionCount = 0

    private let store = CategoryStore()
    private let svc = RuleAuthoringService()
    private let ignoredStore = IgnoredTitleStore()
    private let neverTrackStore = NeverTrackStore()
    private let dbPool = DatabaseManager.shared.dbPool
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "SessionBrowser")

    // MARK: - Filtered data

    private var filteredGroups: [AppGroup] {
        guard !searchText.isEmpty else { return allGroups }
        return allGroups.compactMap { group in
            let matchedWindows = group.windows.filter {
                $0.appName.localizedCaseInsensitiveContains(searchText) ||
                $0.windowTitle.localizedCaseInsensitiveContains(searchText)
            }
            guard !matchedWindows.isEmpty else { return nil }
            return AppGroup(appBundleId: group.appBundleId, appName: group.appName, windows: matchedWindows)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            statsBar
            Divider()
            if allGroups.isEmpty && resolvedRows.isEmpty {
                emptyState
            } else {
                browserList
            }
        }
        .onAppear { reload() }
        .onChange(of: searchText) { _, _ in creatingRuleFor = nil }
        .confirmationDialog(
            neverTrackTarget.map { "Stop tracking \"\($0.windowTitle)\"?" } ?? "",
            isPresented: Binding(get: { neverTrackTarget != nil }, set: { if !$0 { neverTrackTarget = nil } }),
            titleVisibility: .visible
        ) {
            if let target = neverTrackTarget {
                Button("Never Track — Delete \(neverTrackSessionCount) Session\(neverTrackSessionCount == 1 ? "" : "s")", role: .destructive) {
                    applyNeverTrack(target)
                }
            }
            Button("Cancel", role: .cancel) { neverTrackTarget = nil }
        } message: {
            Text("Future sessions will be silently discarded. Past sessions will be permanently deleted.")
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
    }

    // MARK: - Sub-views

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            TextField("Search apps or window titles", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var statsBar: some View {
        HStack {
            let pendingCount = allGroups.reduce(0) { $0 + $1.windows.count }
            Text(pendingCount == 0
                 ? "All browser titles are classified"
                 : "\(pendingCount) title\(pendingCount == 1 ? "" : "s") need attention")
                .font(.caption)
                .foregroundStyle(pendingCount > 0 ? .primary : .secondary)
            Spacer()
            if !ignoredRows.isEmpty {
                Button(showIgnored ? "Hide Ignored" : "Show Ignored (\(ignoredRows.count))") {
                    showIgnored.toggle()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
            Button("Refresh") { reload() }
                .controlSize(.small)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            if browserCategoryId == nil {
                Text("No \"Browser\" category found")
                    .fontWeight(.medium)
                Text("Create a category named \"Browser\" to enable this view.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            } else if searchText.isEmpty {
                Text("No browser sessions yet")
                    .fontWeight(.medium)
                Text("Sessions from Chrome, Brave, Firefox, Safari and other browsers will appear here once recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            } else {
                Text("No results for \"\(searchText)\"")
                    .fontWeight(.medium)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var browserList: some View {
        List {
            if !allGroups.isEmpty {
                let pendingCount = allGroups.reduce(0) { $0 + $1.windows.count }
                Section {
                    if filteredGroups.isEmpty {
                        Text("No results for \"\(searchText)\"")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    } else {
                        ForEach(filteredGroups) { group in
                            appGroupRow(group)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                } header: {
                    Text("NEEDS ATTENTION — \(pendingCount) TITLE\(pendingCount == 1 ? "" : "S")")
                }
            }
            if !resolvedRows.isEmpty {
                Section {
                    ForEach(resolvedRows) { row in
                        resolvedRowView(row)
                    }
                } header: {
                    Text("CLASSIFIED — LAST \(resolvedRows.count)")
                }
            }
            if showIgnored && !ignoredRows.isEmpty {
                Section {
                    ForEach(ignoredRows) { row in
                        ignoredRowView(row)
                    }
                } header: {
                    Text("IGNORED (\(ignoredRows.count))")
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - App group row

    private func appGroupRow(_ group: AppGroup) -> some View {
        DisclosureGroup {
            ForEach(group.windows) { window in
                windowRow(window, in: group)
                    .padding(.leading, 8)
                    .padding(.vertical, 4)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.appName).fontWeight(.medium)
                    Text(group.appBundleId)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(group.sessionCount) session\(group.sessionCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(DurationFormatter.string(from: group.totalSeconds))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Resolved row (read-only)

    private func resolvedRowView(_ row: WindowRow) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.windowTitle)
                    .font(.callout)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(row.appName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    categoryBadge(for: row.categoryId)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(row.sessionCount) session\(row.sessionCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let date = row.latestEndedAt {
                    Text(Self.resolvedDateFormatter.string(from: date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private func ignoredRowView(_ row: WindowRow) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.windowTitle)
                    .font(.callout)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
                Text(row.appName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Un-ignore") {
                unignore(row)
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    // MARK: - Window row

    private func windowRow(_ window: WindowRow, in group: AppGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(window.windowTitle)
                        .font(.callout)
                        .lineLimit(2)
                    categoryBadge(for: window.categoryId)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(window.sessionCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(DurationFormatter.string(from: window.totalSeconds))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 8) {
                Button {
                    openCreateRule(for: window)
                } label: {
                    Label("Create Rule", systemImage: "plus.circle")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                reclassifyMenu(for: window)

                Button {
                    ignore(window)
                } label: {
                    Label("Ignore", systemImage: "eye.slash")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button {
                    prepareNeverTrack(window)
                } label: {
                    Label("Never Track", systemImage: "xmark.shield")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }

            if creatingRuleFor?.id == window.id {
                createRuleForm(for: window)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func categoryBadge(for categoryId: Int64?) -> some View {
        HStack(spacing: 4) {
            if let catId = categoryId, let cat = categoriesById[catId] {
                Circle()
                    .fill(Color(hex: cat.colorHex) ?? .gray)
                    .frame(width: 7, height: 7)
                Text(cat.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text("Unclassified")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func reclassifyMenu(for window: WindowRow) -> some View {
        Menu {
            ForEach(categories) { cat in
                Button {
                    reclassify(window, to: cat)
                } label: {
                    HStack {
                        Circle()
                            .fill(Color(hex: cat.colorHex) ?? .gray)
                            .frame(width: 8, height: 8)
                        Text(cat.name)
                    }
                }
            }
        } label: {
            Label("Reclassify", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Create Rule inline form

    private func createRuleForm(for window: WindowRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Match").foregroundStyle(.secondary).font(.caption)
                    Text("Title contains")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
                GridRow {
                    Text("Value").foregroundStyle(.secondary).font(.caption)
                    Text(window.windowTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                GridRow {
                    Text("Category").foregroundStyle(.secondary).font(.caption)
                    Menu {
                        ForEach(categories) { cat in
                            Button {
                                newRuleCategoryId = cat.id
                                computePreview(for: window)
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(Color(hex: cat.colorHex) ?? .gray)
                                        .frame(width: 8, height: 8)
                                    Text(cat.name)
                                }
                            }
                        }
                    } label: {
                        if let catId = newRuleCategoryId, let cat = categoriesById[catId] {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: cat.colorHex) ?? .gray)
                                    .frame(width: 8, height: 8)
                                Text(cat.name).font(.caption)
                                Image(systemName: "chevron.down").font(.caption2)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Text("Choose…").font(.caption).foregroundStyle(.secondary)
                                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                GridRow {
                    Text("Priority").foregroundStyle(.secondary).font(.caption)
                    HStack(spacing: 6) {
                        Stepper("", value: $newRulePriority, in: 1...200)
                            .labelsHidden()
                        Text("\(newRulePriority)")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 30)
                    }
                }
            }

            if let count = rulePreviewCount {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle.fill")
                    Text(count == 0 ? "No sessions match this pattern" : "~\(count) sessions will be reclassified")
                }
                .font(.caption)
                .foregroundStyle(count > 0 ? Color.accentColor : .secondary)
            }

            HStack {
                Button("Cancel") {
                    creatingRuleFor = nil
                    resetRuleForm()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Apply") { applyRule(for: window) }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(newRuleCategoryId == nil)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Data

    private func reload() {
        do {
            categories = try store.fetchAllCategories()
            categoriesById = Dictionary(uniqueKeysWithValues: categories.compactMap { c in
                guard let id = c.id else { return nil }
                return (id, c)
            })
            browserCategoryId = categories.first(where: {
                $0.name.caseInsensitiveCompare("Browser") == .orderedSame
            })?.id
            guard let browserId = browserCategoryId else {
                allGroups = []
                resolvedRows = []
                ignoredRows = []
                return
            }
            ignoredKeys = (try? ignoredStore.fetchAll()) ?? []
            let rows = try fetchWindowRows(browserCategoryId: browserId)
            let pending = rows.filter { $0.pendingCount > 0 }
            let notIgnored = pending.filter { !ignoredKeys.contains($0.id) }
            let isIgnored  = pending.filter {  ignoredKeys.contains($0.id) }
            allGroups  = groupByApp(notIgnored)
            ignoredRows = isIgnored
            resolvedRows = Array(
                rows.filter { $0.pendingCount == 0 }
                    .sorted { ($0.latestEndedAt ?? .distantPast) > ($1.latestEndedAt ?? .distantPast) }
                    .prefix(Self.resolvedRowLimit)
            )
        } catch {
            logger.error("Failed to load sessions: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    private func fetchWindowRows(browserCategoryId: Int64) throws -> [WindowRow] {
        try dbPool.read { db in
            let rawRows = try Row.fetchAll(db, sql: """
                SELECT
                    s.app_bundle_id,
                    MAX(s.app_name)      AS app_name,
                    s.window_title,
                    (SELECT s2.category_id FROM activity_sessions s2
                     WHERE s2.app_bundle_id = s.app_bundle_id
                       AND s2.window_title = s.window_title
                       AND s2.is_idle = 0 AND s2.ended_at IS NOT NULL
                     ORDER BY s2.ended_at DESC LIMIT 1) AS category_id,
                    COUNT(*)             AS session_count,
                    SUM(CASE WHEN s.category_id = ? THEN 1 ELSE 0 END) AS pending_count,
                    SUM(CASE WHEN s.duration_seconds IS NOT NULL
                             THEN s.duration_seconds ELSE 0 END) AS total_seconds,
                    MAX(s.ended_at)      AS latest_ended_at
                FROM activity_sessions s
                WHERE s.is_idle = 0
                  AND s.ended_at IS NOT NULL
                  AND s.window_title IS NOT NULL
                  AND s.window_title != ''
                  AND s.app_bundle_id IN (
                      SELECT match_value FROM category_rules
                      WHERE match_type = 'app_bundle' AND category_id = ?
                  )
                GROUP BY s.app_bundle_id, s.window_title
                ORDER BY s.app_bundle_id, session_count DESC
                """,
                arguments: [browserCategoryId, browserCategoryId])
            return rawRows.compactMap { row -> WindowRow? in
                guard let bundleId: String = row["app_bundle_id"],
                      let title: String    = row["window_title"] else { return nil }
                let endedAtStr: String? = row["latest_ended_at"]
                let latestEndedAt = endedAtStr.flatMap {
                    Self.dbDateFormatter.date(from: $0)
                }
                return WindowRow(
                    appBundleId: bundleId,
                    appName: row["app_name"] ?? bundleId,
                    windowTitle: title,
                    categoryId: row["category_id"],
                    sessionCount: row["session_count"] ?? 0,
                    pendingCount: row["pending_count"] ?? 0,
                    totalSeconds: row["total_seconds"] ?? 0,
                    latestEndedAt: latestEndedAt
                )
            }
        }
    }

    private func groupByApp(_ rows: [WindowRow]) -> [AppGroup] {
        let grouped = Dictionary(grouping: rows, by: \.appBundleId)
        return grouped
            .map { bundleId, windows in
                AppGroup(
                    appBundleId: bundleId,
                    appName: windows.first?.appName ?? bundleId,
                    windows: windows
                )
            }
            .sorted { $0.sessionCount > $1.sessionCount }
    }

    // MARK: - Actions

    private func ignore(_ window: WindowRow) {
        do {
            try ignoredStore.add(bundleId: window.appBundleId, title: window.windowTitle)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unignore(_ window: WindowRow) {
        do {
            try ignoredStore.remove(bundleId: window.appBundleId, title: window.windowTitle)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareNeverTrack(_ window: WindowRow) {
        do {
            let count = try dbPool.read { db in
                try Int.fetchOne(db,
                    sql: "SELECT COUNT(*) FROM activity_sessions WHERE app_bundle_id = ? AND window_title = ? AND is_idle = 0 AND ended_at IS NOT NULL",
                    arguments: [window.appBundleId, window.windowTitle]
                ) ?? 0
            }
            neverTrackSessionCount = count
            neverTrackTarget = window
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyNeverTrack(_ window: WindowRow) {
        do {
            try dbPool.write { db in
                try db.execute(
                    sql: "DELETE FROM activity_sessions WHERE app_bundle_id = ? AND window_title = ?",
                    arguments: [window.appBundleId, window.windowTitle]
                )
            }
            try neverTrackStore.addTitle(bundleId: window.appBundleId, title: window.windowTitle)
            try ignoredStore.remove(bundleId: window.appBundleId, title: window.windowTitle)
            neverTrackTarget = nil
            reload()
        } catch {
            neverTrackTarget = nil
            errorMessage = error.localizedDescription
        }
    }

    private func reclassify(_ window: WindowRow, to category: Category) {
        guard let catId = category.id else { return }
        do {
            try dbPool.write { db in
                try db.execute(
                    sql: """
                        UPDATE activity_sessions
                        SET category_id = ?
                        WHERE app_bundle_id = ? AND window_title = ?
                          AND is_idle = 0 AND ended_at IS NOT NULL
                        """,
                    arguments: [catId, window.appBundleId, window.windowTitle]
                )
            }
            logger.info("Reclassified \(window.appBundleId) | \(window.windowTitle) → \(category.name)")
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openCreateRule(for window: WindowRow) {
        if creatingRuleFor?.id == window.id {
            creatingRuleFor = nil
            resetRuleForm()
        } else {
            resetRuleForm()
            creatingRuleFor = window
        }
    }

    private func computePreview(for window: WindowRow) {
        guard let catId = newRuleCategoryId else { rulePreviewCount = nil; return }
        let rule = CategoryRule(
            id: nil, categoryId: catId,
            matchType: .windowTitleContains, matchValue: window.windowTitle,
            priority: newRulePriority
        )
        rulePreviewCount = try? svc.previewRule(rule)
    }

    private func applyRule(for window: WindowRow) {
        guard let catId = newRuleCategoryId else { return }
        let rule = CategoryRule(
            id: nil, categoryId: catId,
            matchType: .windowTitleContains, matchValue: window.windowTitle,
            priority: newRulePriority
        )
        do {
            _ = try svc.applyRule(rule)
            creatingRuleFor = nil
            resetRuleForm()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetRuleForm() {
        newRuleCategoryId = nil
        newRulePriority = 50
        rulePreviewCount = nil
    }
}
