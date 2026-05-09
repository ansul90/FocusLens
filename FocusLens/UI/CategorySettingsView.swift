import SwiftUI
import os

struct CategorySettingsView: View {

    // MARK: - State

    @State private var categories: [Category] = []
    @State private var selectedCategory: Category?
    @State private var rules: [CategoryRule] = []

    // Inline edit fields (synced when selection changes)
    @State private var editName = ""
    @State private var editColor: Color = .blue
    @State private var editScore = 0

    // Add-category popover
    @State private var showAddCategory = false
    @State private var newCatName = ""
    @State private var newCatColor: Color = Color(hex: "#5B8CFF") ?? .blue
    @State private var newCatScore = 0

    // Add-rule inline form
    @State private var showAddRuleForm = false
    @State private var newRuleType: RuleMatchType = .appBundle
    @State private var newRuleValue = ""
    @State private var newRulePriority = 50
    @State private var rulePreviewCount: Int?

    // Confirmation + errors
    @State private var ruleToDelete: CategoryRule?
    @State private var errorMessage: String?

    private let store = CategoryStore()
    private let svc = RuleAuthoringService()
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "CategorySettings")

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
            Divider()
            if let cat = selectedCategory {
                detailPane(cat)
            } else {
                placeholderPane
            }
        }
        .onAppear { reload() }
        .confirmationDialog(
            "Delete Rule?",
            isPresented: Binding(get: { ruleToDelete != nil }, set: { if !$0 { ruleToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { confirmDeleteRule() }
            Button("Cancel", role: .cancel) { ruleToDelete = nil }
        } message: {
            if let r = ruleToDelete {
                Text("\"\(r.matchValue)\" will be removed and affected sessions re-evaluated.")
            }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            List(selection: $selectedCategory) {
                ForEach(categories) { cat in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: cat.colorHex) ?? .gray)
                            .frame(width: 10, height: 10)
                        Text(cat.name)
                            .lineLimit(1)
                        Spacer()
                        Text(scoreText(cat.productivityScore))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .tag(cat as Category?)
                }
            }
            .onChange(of: selectedCategory) { _, cat in
                syncEditState(to: cat)
                reloadRules()
                showAddRuleForm = false
                resetRuleForm()
            }

            Divider()
            HStack {
                Button {
                    showAddCategory = true
                } label: {
                    Label("Add Category", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .padding(8)
                .popover(isPresented: $showAddCategory, arrowEdge: .bottom) {
                    addCategoryPopover
                }
                Spacer()
            }
        }
        .frame(width: 200)
    }

    // MARK: - Placeholder

    private var placeholderPane: some View {
        VStack(spacing: 8) {
            Image(systemName: "tag")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Select a category")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail pane

    private func detailPane(_ cat: Category) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                categoryEditSection(cat)
                Divider()
                rulesSection(cat)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Category edit section

    private func categoryEditSection(_ cat: Category) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category").font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Name").foregroundStyle(.secondary)
                    TextField("Category name", text: $editName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Color").foregroundStyle(.secondary)
                    HStack {
                        ColorPicker("", selection: $editColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 44)
                        Text(editColor.hexString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Spacer()
                    }
                }
                GridRow {
                    Text("Score").foregroundStyle(.secondary)
                    scoreSegmentedControl(selected: $editScore)
                }
            }

            HStack {
                Spacer()
                Button("Save Changes") { saveCategory(cat) }
                    .disabled(!hasEdits(for: cat))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Rules section

    private func rulesSection(_ cat: Category) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Rules").font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showAddRuleForm.toggle()
                        if !showAddRuleForm { resetRuleForm() }
                    }
                } label: {
                    Label(
                        showAddRuleForm ? "Cancel" : "Add Rule",
                        systemImage: showAddRuleForm ? "xmark.circle" : "plus.circle"
                    )
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(showAddRuleForm ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            }

            if rules.isEmpty {
                Text("No rules. Add one to route sessions automatically.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(rules) { rule in
                    ruleRow(rule)
                }
            }

            if showAddRuleForm, let catId = cat.id {
                addRuleForm(categoryId: catId)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func ruleRow(_ rule: CategoryRule) -> some View {
        HStack(spacing: 8) {
            Text(rule.matchType.displayName)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())

            Text(rule.matchValue)
                .font(.callout)
                .lineLimit(1)

            Spacer()

            Text("P\(rule.priority)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Button(role: .destructive) {
                ruleToDelete = rule
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.7))
        }
        .padding(.vertical, 3)
    }

    // MARK: - Add rule form

    private func addRuleForm(categoryId: Int64) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Match").foregroundStyle(.secondary)
                    Picker("", selection: $newRuleType) {
                        Text("App Bundle ID").tag(RuleMatchType.appBundle)
                        Text("Title Contains").tag(RuleMatchType.windowTitleContains)
                        Text("Title Regex").tag(RuleMatchType.windowTitleRegex)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: newRuleType) { _, _ in computeRulePreview(for: categoryId) }
                }
                GridRow {
                    Text("Value").foregroundStyle(.secondary)
                    TextField(
                        newRuleType == .appBundle ? "com.example.App" : "keyword or regex",
                        text: $newRuleValue
                    )
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: newRuleValue) { _, _ in computeRulePreview(for: categoryId) }
                }
                GridRow {
                    Text("Priority").foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Stepper("", value: $newRulePriority, in: 1...200)
                            .labelsHidden()
                        Text("\(newRulePriority)")
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
                Spacer()
                Button("Add Rule") { addRule(categoryId: categoryId) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(newRuleValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Add category popover

    private var addCategoryPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Category").font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Name").foregroundStyle(.secondary)
                    TextField("e.g. Research", text: $newCatName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
                GridRow {
                    Text("Color").foregroundStyle(.secondary)
                    ColorPicker("", selection: $newCatColor, supportsOpacity: false)
                        .labelsHidden()
                }
                GridRow {
                    Text("Score").foregroundStyle(.secondary)
                    scoreSegmentedControl(selected: $newCatScore)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { showAddCategory = false; resetNewCatForm() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { createCategory() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(newCatName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    // MARK: - Shared sub-view

    private func scoreSegmentedControl(selected: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            ForEach([-2, -1, 0, 1, 2], id: \.self) { s in
                Button(scoreText(s)) {
                    selected.wrappedValue = s
                }
                .buttonStyle(.bordered)
                .tint(selected.wrappedValue == s ? scoreColor(s) : .clear)
                .controlSize(.mini)
            }
        }
    }

    // MARK: - Actions

    private func reload() {
        do {
            categories = try store.fetchAllCategories()
        } catch {
            logger.error("Failed to load categories: \(error.localizedDescription)")
        }
    }

    private func reloadRules() {
        guard let id = selectedCategory?.id else { rules = []; return }
        rules = (try? store.fetchRules(for: id)) ?? []
    }

    private func syncEditState(to cat: Category?) {
        guard let cat else {
            editName = ""; editColor = .blue; editScore = 0
            return
        }
        editName = cat.name
        editColor = Color(hex: cat.colorHex) ?? .blue
        editScore = cat.productivityScore
    }

    private func hasEdits(for cat: Category) -> Bool {
        let nameChanged = editName.trimmingCharacters(in: .whitespaces) != cat.name
        let colorChanged = editColor.hexString.caseInsensitiveCompare(cat.colorHex) != .orderedSame
        let scoreChanged = editScore != cat.productivityScore
        return nameChanged || colorChanged || scoreChanged
    }

    private func saveCategory(_ cat: Category) {
        let updated = Category(
            id: cat.id,
            name: editName.trimmingCharacters(in: .whitespaces),
            colorHex: editColor.hexString,
            productivityScore: editScore
        )
        do {
            try store.update(updated)
            reload()
            selectedCategory = categories.first { $0.id == updated.id }
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func createCategory() {
        let cat = Category(
            id: nil,
            name: newCatName.trimmingCharacters(in: .whitespaces),
            colorHex: newCatColor.hexString,
            productivityScore: newCatScore
        )
        do {
            let saved = try store.insert(cat)
            reload()
            showAddCategory = false
            selectedCategory = saved
            resetNewCatForm()
        } catch {
            errorMessage = "Failed to add category: \(error.localizedDescription)"
        }
    }

    private func addRule(categoryId: Int64) {
        let value = newRuleValue.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        let rule = CategoryRule(
            id: nil, categoryId: categoryId,
            matchType: newRuleType, matchValue: value, priority: newRulePriority
        )
        do {
            _ = try svc.applyRule(rule)
            reloadRules()
            showAddRuleForm = false
            resetRuleForm()
        } catch {
            errorMessage = "Failed to add rule: \(error.localizedDescription)"
        }
    }

    private func confirmDeleteRule() {
        guard let rule = ruleToDelete, let id = rule.id else { ruleToDelete = nil; return }
        do {
            _ = try svc.deleteRule(id: id)
            reloadRules()
        } catch {
            errorMessage = "Failed to delete rule: \(error.localizedDescription)"
        }
        ruleToDelete = nil
    }

    private func computeRulePreview(for categoryId: Int64) {
        let value = newRuleValue.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { rulePreviewCount = nil; return }
        let rule = CategoryRule(
            id: nil, categoryId: categoryId,
            matchType: newRuleType, matchValue: value, priority: newRulePriority
        )
        rulePreviewCount = try? svc.previewRule(rule)
    }

    private func resetRuleForm() {
        newRuleType = .appBundle; newRuleValue = ""; newRulePriority = 50; rulePreviewCount = nil
    }

    private func resetNewCatForm() {
        newCatName = ""; newCatColor = Color(hex: "#5B8CFF") ?? .blue; newCatScore = 0
    }

    // MARK: - Formatters

    private func scoreText(_ s: Int) -> String {
        switch s {
        case 2: return "+2"; case 1: return "+1"; case 0: return "0"
        case -1: return "-1"; case -2: return "-2"; default: return "\(s)"
        }
    }

    private func scoreColor(_ s: Int) -> Color {
        switch s {
        case 2: return .green
        case 1: return Color(hex: "#8BC34A") ?? .green
        case 0: return .gray
        case -1: return .orange
        case -2: return .red
        default: return .gray
        }
    }
}

extension RuleMatchType {
    var displayName: String {
        switch self {
        case .appBundle: return "Bundle ID"
        case .windowTitleContains: return "Title has"
        case .windowTitleRegex: return "Title regex"
        }
    }
}
