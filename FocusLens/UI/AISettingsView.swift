import SwiftUI

// MARK: - Connection status

private enum ConnectionStatus {
    case idle
    case testing
    case success
    case failure(String)
}

// MARK: - View

struct AISettingsView: View {
    @State private var settings = GeminiSettings()
    @State private var status: ConnectionStatus = .idle

    var body: some View {
        Form {
            Section("Gemini AI") {
                Toggle("Enable AI browser classification", isOn: $settings.isEnabled)
            }

            if settings.isEnabled {
                Section("API Key") {
                    SecureField("Gemini API key", text: $settings.apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Connection") {
                    HStack {
                        Button("Test Connection") {
                            runConnectionTest()
                        }
                        .disabled(!settings.hasValidKey || isTestInFlight)

                        statusIndicator
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Computed helpers

    private var isTestInFlight: Bool {
        if case .testing = status { return true }
        return false
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView()
                .controlSize(.small)
        case .success:
            Label("Connection successful", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    // MARK: - Actions

    private func runConnectionTest() {
        status = .testing
        let snapshot = settings
        Task { @MainActor in
            do {
                let client = GeminiClient(settings: snapshot)
                let request = GeminiBatchRequest(items: [.init(id: 0, title: "GitHub")])
                _ = try await client.classify(request)
                status = .success
            } catch {
                status = .failure(humanReadable(error))
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
