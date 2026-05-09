import SwiftUI
import GRDB
import os

struct OverridesView: View {

    struct DisplayRow: Identifiable {
        let id: Int64
        let appBundleId: String
        let appName: String
        let categoryId: Int64
        let categoryName: String
        let categoryColorHex: String
        let sessionCount: Int
        let createdAt: Date
    }

    @State private var rows: [DisplayRow] = []
    @State private var categories: [Category] = []
    @State private var toDelete: DisplayRow?
    @State private var errorMessage: String?

    private let store = CategoryStore()
    private let svc = RuleAuthoringService()
    private let dbPool = DatabaseManager.shared.dbPool
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Overrides")

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    private static let dbDateFormatter = DateUtils.dbTimestampFormatter()

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            statsBar
            Divider()
            if rows.isEmpty { emptyState } else { overrideList }
        }
        .onAppear { reload() }
        .confirmationDialog(
            "Remove Override?",
            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove Override", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) { toDelete = nil }
        } message: {
            if let r = toDelete {
                Text("""
                    The override for "\(r.appName)" will be removed. \
                    \(r.sessionCount) session\(r.sessionCount == 1 ? "" : "s") \
                    will be re-evaluated against rules.
                    """)
            }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
    }

    // MARK: - Sub-views

    private var statsBar: some View {
        HStack {
            Text(rows.isEmpty
                 ? "No active overrides"
                 : "\(rows.count) active override\(rows.count == 1 ? "" : "s")")
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
            Image(systemName: "lock.open")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No app overrides set")
                .fontWeight(.medium)
            Text("Use \"Override App\" in the Unclassified tab to pin an app permanently to a category.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var overrideList: some View {
        List {
            ForEach(rows) { row in
                overrideRow(row)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        .listStyle(.inset)
    }

    private func overrideRow(_ row: DisplayRow) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // App info
            VStack(alignment: .leading, spacing: 3) {
                Text(row.appName).fontWeight(.medium)
                Text(row.appBundleId)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("Set \(Self.displayDateFormatter.string(from: row.createdAt))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Arrow + category badge
            HStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Circle()
                    .fill(Color(hex: row.categoryColorHex) ?? .gray)
                    .frame(width: 8, height: 8)
                Text(row.categoryName)
                    .font(.callout)
            }

            // Session count
            Text("\(row.sessionCount)")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())
                .help("\(row.sessionCount) sessions from this app")

            // Change category
            Menu {
                Label("Change to:", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                Divider()
                ForEach(categories.filter { $0.id != row.categoryId }) { cat in
                    Button {
                        changeCategory(for: row, to: cat)
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
                Image(systemName: "pencil.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Change override category")

            // Remove
            Button(role: .destructive) { toDelete = row } label: {
                Image(systemName: "trash")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.7))
            .help("Remove override — sessions will be re-evaluated")
        }
    }

    // MARK: - Data

    private func reload() {
        do {
            categories = try store.fetchAllCategories()
            rows = try dbPool.read { db in
                let rawRows = try Row.fetchAll(db, sql: """
                    SELECT
                        o.id,
                        o.app_bundle_id,
                        o.category_id,
                        o.created_at,
                        c.name      AS category_name,
                        c.color_hex,
                        COALESCE(
                            (SELECT app_name FROM activity_sessions
                             WHERE  app_bundle_id = o.app_bundle_id LIMIT 1),
                            o.app_bundle_id
                        )           AS app_name,
                        COALESCE(
                            (SELECT COUNT(*) FROM activity_sessions
                             WHERE  app_bundle_id = o.app_bundle_id
                               AND  is_idle = 0 AND ended_at IS NOT NULL),
                            0
                        )           AS session_count
                    FROM category_overrides o
                    JOIN categories c ON o.category_id = c.id
                    ORDER BY o.created_at DESC
                    """)
                return rawRows.compactMap { row -> DisplayRow? in
                    guard let id: Int64        = row["id"],
                          let bundleId: String = row["app_bundle_id"],
                          let catId: Int64     = row["category_id"],
                          let catName: String  = row["category_name"],
                          let colorHex: String = row["color_hex"] else { return nil }
                    let createdAtStr: String = row["created_at"] ?? ""
                    let createdAt = Self.dbDateFormatter.date(from: createdAtStr) ?? Date()
                    return DisplayRow(
                        id: id,
                        appBundleId: bundleId,
                        appName: row["app_name"] ?? bundleId,
                        categoryId: catId,
                        categoryName: catName,
                        categoryColorHex: colorHex,
                        sessionCount: row["session_count"] ?? 0,
                        createdAt: createdAt
                    )
                }
            }
        } catch {
            logger.error("Failed to load overrides: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Actions

    private func changeCategory(for row: DisplayRow, to category: Category) {
        guard let catId = category.id else { return }
        do {
            _ = try svc.applyOverride(appBundleId: row.appBundleId, categoryId: catId)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmDelete() {
        guard let row = toDelete else { return }
        do {
            _ = try svc.deleteOverride(id: row.id)
            toDelete = nil
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
