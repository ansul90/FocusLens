import SwiftUI
import os

struct CategorySettingsView: View {
    @State private var categories: [Category] = []
    @State private var selectedCategory: Category? = nil
    @State private var rules: [CategoryRule] = []
    @State private var showAddCategory = false
    @State private var showAddRule = false
    @State private var newCategoryName = ""
    @State private var newCategoryColor = "#5B8CFF"
    @State private var newCategoryScore = 0
    @State private var newRuleType: RuleMatchType = .appBundle
    @State private var newRuleValue = ""
    @State private var newRulePriority = 50
    @State private var errorMessage: String?

    @State private var store = CategoryStore()

    private let logger = Logger(subsystem: "com.focuslens.app", category: "CategorySettings")

    var body: some View {
        HStack(spacing: 0) {
            categoryList
            Divider()
            ruleList
        }
        .onAppear { loadCategories() }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        ), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
    }

    // MARK: - Left: category list

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selectedCategory) {
                ForEach(categories) { category in
                    HStack {
                        Circle()
                            .fill(Color(hex: category.colorHex) ?? .gray)
                            .frame(width: 10, height: 10)
                        Text(category.name)
                        Spacer()
                        Text(scoreLabel(category.productivityScore))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(category as Category?)
                }
                .onDelete { offsets in
                    for i in offsets {
                        guard let id = categories[i].id else { continue }
                        do {
                            try store.deleteCategory(id: id)
                        } catch {
                            errorMessage = "Failed to delete category: \(error.localizedDescription)"
                        }
                    }
                    loadCategories()
                }
            }
            .frame(width: 200)

            HStack {
                Button("Add Category") { showAddCategory = true }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .padding(8)
                Spacer()
            }
            .background(.background)
        }
        .sheet(isPresented: $showAddCategory) { addCategorySheet }
        .onChange(of: selectedCategory) { _, cat in
            guard let cat else { rules = []; return }
            do {
                rules = try store.fetchRules(for: cat.id ?? 0)
            } catch {
                logger.error("Failed to fetch rules: \(error.localizedDescription)")
                rules = []
            }
        }
    }

    // MARK: - Right: rules for selected category

    private var ruleList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cat = selectedCategory {
                List {
                    ForEach(rules) { rule in
                        HStack {
                            Text(rule.matchType.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Text(rule.matchValue)
                                .lineLimit(1)
                            Spacer()
                            Text("P\(rule.priority)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets {
                            guard let id = rules[i].id else { continue }
                            do {
                                try store.deleteRule(id: id)
                            } catch {
                                errorMessage = "Failed to delete rule: \(error.localizedDescription)"
                            }
                        }
                        do {
                            rules = try store.fetchRules(for: cat.id ?? 0)
                        } catch {
                            logger.error("Failed to reload rules: \(error.localizedDescription)")
                            rules = []
                        }
                    }
                }
                HStack {
                    Button("Add Rule") { showAddRule = true }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .padding(8)
                    Spacer()
                }
                .background(.background)
                .sheet(isPresented: $showAddRule) { addRuleSheet(for: cat) }
            } else {
                Spacer()
                Text("Select a category")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .frame(minWidth: 280)
    }

    // MARK: - Add category sheet

    private var addCategorySheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Category").font(.headline)
            LabeledContent("Name") {
                TextField("e.g. Research", text: $newCategoryName)
            }
            LabeledContent("Color (hex)") {
                TextField("#5B8CFF", text: $newCategoryColor)
            }
            LabeledContent("Productivity") {
                Picker("", selection: $newCategoryScore) {
                    Text("Very Distracting (-2)").tag(-2)
                    Text("Distracting (-1)").tag(-1)
                    Text("Neutral (0)").tag(0)
                    Text("Productive (+1)").tag(1)
                    Text("Very Productive (+2)").tag(2)
                }
                .pickerStyle(.menu)
            }
            HStack {
                Spacer()
                Button("Cancel") { showAddCategory = false }
                Button("Add") {
                    let cat = Category(
                        id: nil,
                        name: newCategoryName,
                        colorHex: newCategoryColor,
                        productivityScore: newCategoryScore
                    )
                    do {
                        try store.insert(cat)
                        loadCategories()
                        newCategoryName = ""
                        newCategoryColor = "#5B8CFF"
                        newCategoryScore = 0
                        showAddCategory = false
                    } catch {
                        errorMessage = "Failed to add category: \(error.localizedDescription)"
                    }
                }
                .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    // MARK: - Add rule sheet

    private func addRuleSheet(for category: Category) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Rule for \(category.name)").font(.headline)
            LabeledContent("Match Type") {
                Picker("", selection: $newRuleType) {
                    Text("App Bundle ID").tag(RuleMatchType.appBundle)
                    Text("Window Title Contains").tag(RuleMatchType.windowTitleContains)
                    Text("Window Title Regex").tag(RuleMatchType.windowTitleRegex)
                }
                .pickerStyle(.menu)
            }
            LabeledContent("Value") {
                TextField("e.g. com.apple.Safari", text: $newRuleValue)
            }
            LabeledContent("Priority") {
                Stepper("\(newRulePriority)", value: $newRulePriority, in: 1...100)
            }
            HStack {
                Spacer()
                Button("Cancel") { showAddRule = false }
                Button("Add") {
                    let rule = CategoryRule(
                        id: nil,
                        categoryId: category.id ?? 0,
                        matchType: newRuleType,
                        matchValue: newRuleValue,
                        priority: newRulePriority
                    )
                    do {
                        try store.insert(rule)
                        rules = (try? store.fetchRules(for: category.id ?? 0)) ?? []
                        newRuleValue = ""
                        newRuleType = .appBundle
                        newRulePriority = 50
                        showAddRule = false
                    } catch {
                        errorMessage = "Failed to add rule: \(error.localizedDescription)"
                    }
                }
                .disabled(newRuleValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    // MARK: - Helpers

    private func loadCategories() {
        do {
            categories = try store.fetchAllCategories()
        } catch {
            logger.error("Failed to load categories: \(error.localizedDescription)")
            categories = []
        }
    }

    private func scoreLabel(_ score: Int) -> String {
        switch score {
        case 2: return "+2 ★★"
        case 1: return "+1 ★"
        case 0: return "0"
        case -1: return "-1"
        case -2: return "-2"
        default: return "\(score)"
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
