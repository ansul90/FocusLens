import SwiftUI

// MARK: - Status enums

private enum ConnectionStatus {
    case idle, testing, success, failure(String)
}

private enum ReclassifyStatus {
    case idle, running, done(found: Int, updated: Int), failure(String)
}

private enum OllamaTestStatus {
    case idle, testing, success(String), failure(String)
}

// MARK: - View

struct AISettingsView: View {
    @Environment(TodayAggregate.self) private var aggregate
    @State private var geminiSettings = GeminiSettings()
    @State private var ollamaSettings = OllamaSettings()
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var reclassifyStatus: ReclassifyStatus = .idle
    @State private var ollamaTestStatus: OllamaTestStatus = .idle

    private let classifier = BrowserClassifier()

    var body: some View {
        Form {
            ollamaSection
            geminiSection
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Ollama section

    private var ollamaSection: some View {
        Section {
            Toggle("Enable local agent (Ollama)", isOn: $ollamaSettings.isEnabled)

            if ollamaSettings.isEnabled {
                LabeledContent("Model") {
                    TextField("e.g. gemma4", text: $ollamaSettings.modelName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }

                LabeledContent("Host") {
                    TextField("http://localhost:11434", text: $ollamaSettings.host)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                HStack {
                    Button("Test Ollama") { runOllamaTest() }
                        .disabled(isOllamaTestInFlight)

                    ollamaTestIndicator
                }

                Text("Install [Ollama](https://ollama.com), then run: `ollama pull \(ollamaSettings.modelName.isEmpty ? "gemma4" : ollamaSettings.modelName)`")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .tint(.accentColor)
            }
        } header: {
            Label("Local AI (Ollama)", systemImage: "cpu")
        }
    }

    // MARK: - Gemini section

    private var geminiSection: some View {
        Section {
            Toggle("Enable Gemini browser classification", isOn: $geminiSettings.isEnabled)

            if geminiSettings.isEnabled {
                Section("API Key") {
                    SecureField("Gemini API key", text: $geminiSettings.apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Connection") {
                    HStack {
                        Button("Test Connection") { runConnectionTest() }
                            .disabled(!geminiSettings.hasValidKey || isTestInFlight)
                        connectionIndicator
                    }
                }

                Section("Classification") {
                    HStack {
                        Button("Reclassify Now") { runReclassify() }
                            .disabled(!geminiSettings.hasValidKey || isReclassifyInFlight)
                        reclassifyIndicator
                    }
                    Text("Re-runs Gemini on all browser sessions still categorised as \"Browser\".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Cloud AI (Gemini)", systemImage: "cloud")
        }
    }

    // MARK: - Computed helpers

    private var isTestInFlight: Bool {
        if case .testing = connectionStatus { return true }
        return false
    }

    private var isReclassifyInFlight: Bool {
        if case .running = reclassifyStatus { return true }
        return false
    }

    private func reclassifyLabel(found: Int, updated: Int) -> String {
        if updated > 0 { return "Reclassified \(updated) session\(updated == 1 ? "" : "s")" }
        if found > 0 { return "Checked \(found) session\(found == 1 ? "" : "s") — all already categorised" }
        return "Nothing to reclassify"
    }

    private var isOllamaTestInFlight: Bool {
        if case .testing = ollamaTestStatus { return true }
        return false
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        switch connectionStatus {
        case .idle: EmptyView()
        case .testing: ProgressView().controlSize(.small)
        case .success:
            Label("Connection successful", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var reclassifyIndicator: some View {
        switch reclassifyStatus {
        case .idle: EmptyView()
        case .running: ProgressView().controlSize(.small)
        case .done(let found, let updated):
            Label(
                reclassifyLabel(found: found, updated: updated),
                systemImage: updated > 0 ? "checkmark.circle.fill" : "checkmark.circle"
            )
            .foregroundStyle(updated > 0 ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var ollamaTestIndicator: some View {
        switch ollamaTestStatus {
        case .idle: EmptyView()
        case .testing: ProgressView().controlSize(.small)
        case .success(let info):
            Label(info, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failure(let msg):
            Label(msg, systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    // MARK: - Actions

    private func runOllamaTest() {
        ollamaTestStatus = .testing
        let snapshot = ollamaSettings
        Task { @MainActor in
            let client = OllamaClient(settings: snapshot)
            do {
                let models = try await client.availableModels()
                let model = snapshot.modelName
                if models.contains(where: { $0.lowercased().hasPrefix(model.split(separator: ":").first.map(String.init)?.lowercased() ?? model) }) {
                    ollamaTestStatus = .success("Connected · \(model) available")
                } else {
                    let list = models.prefix(3).joined(separator: ", ")
                    ollamaTestStatus = .failure("Model '\(model)' not found. Installed: \(list.isEmpty ? "(none)" : list)")
                }
            } catch OllamaError.unreachable {
                ollamaTestStatus = .failure("Ollama not reachable. Run: ollama serve")
            } catch {
                ollamaTestStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func runConnectionTest() {
        connectionStatus = .testing
        let snapshot = geminiSettings
        Task { @MainActor in
            do {
                let client = GeminiClient(settings: snapshot)
                _ = try await client.classify(GeminiBatchRequest(items: [.init(id: 0, title: "GitHub")]))
                connectionStatus = .success
            } catch {
                connectionStatus = .failure(humanReadable(error))
            }
        }
    }

    private func runReclassify() {
        reclassifyStatus = .running
        Task { @MainActor in
            do {
                let result = try await classifier.classifyPending()
                reclassifyStatus = .done(found: result.found, updated: result.updated)
                if result.updated > 0 {
                    await aggregate.refreshStats()
                }
            } catch {
                reclassifyStatus = .failure(humanReadable(error))
            }
        }
    }

    private func humanReadable(_ error: Error) -> String {
        switch error {
        case GeminiError.missingKey:
            return "API key is missing or AI is disabled."
        case GeminiError.httpStatus(let code):
            return "Server returned HTTP \(code). Check your API key."
        case GeminiError.invalidResponse:
            return "Invalid response from server."
        case GeminiError.decoding(let inner):
            return "Failed to decode response: \(inner.localizedDescription)"
        default:
            return error.localizedDescription
        }
    }
}
