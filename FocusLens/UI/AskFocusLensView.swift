import SwiftUI

// MARK: - Main view

struct AskFocusLensView: View {
    @State var viewModel: AskViewModel

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            conversationArea
            Divider()
            inputArea
        }
        .task { await viewModel.checkAvailability() }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.ollamaAvailable ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if !viewModel.entries.isEmpty {
                Button("Clear") { viewModel.clear() }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Conversation

    private var conversationArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if viewModel.entries.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.entries) { entry in
                            MessageBubble(entry: entry)
                                .id(entry.id)
                        }
                        if viewModel.isRunning {
                            thinkingIndicator
                        }
                    }
                }
                .padding(12)
            }
            .onChange(of: viewModel.entries.count) { _, _ in
                if let last = viewModel.entries.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: viewModel.isRunning) { _, running in
                if running, let last = viewModel.entries.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask about your activity")
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(AskViewModel.sampleQueries, id: \.self) { query in
                Button {
                    Task { await viewModel.sendSample(query) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(query)
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isRunning || !viewModel.ollamaAvailable)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Thinking...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Input

    private var inputArea: some View {
        HStack(spacing: 8) {
            TextField("Ask about your activity...", text: $viewModel.inputText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await viewModel.send() } }
                .disabled(viewModel.isRunning || !viewModel.ollamaAvailable)

            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty
                      || viewModel.isRunning
                      || !viewModel.ollamaAvailable)
        }
        .padding(10)
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    let entry: ConversationEntry
    @State private var showTrace = false

    var body: some View {
        VStack(alignment: entry.sender == .user ? .trailing : .leading, spacing: 4) {
            HStack {
                if entry.sender == .user { Spacer(minLength: 40) }
                Text(entry.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(entry.sender == .user
                                ? Color.accentColor.opacity(0.15)
                                : Color.secondary.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 10))
                    .textSelection(.enabled)
                if entry.sender == .agent { Spacer(minLength: 40) }
            }

            if let reportURL = entry.reportURL {
                Link(destination: reportURL) {
                    Label("View Report", systemImage: "chart.bar.xaxis")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            if entry.sender == .agent && !entry.trace.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showTrace.toggle() }
                } label: {
                    Label(showTrace ? "Hide trace" : "\(entry.trace.count) step\(entry.trace.count == 1 ? "" : "s")",
                          systemImage: showTrace ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if showTrace {
                    TraceView(steps: entry.trace)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

// MARK: - Trace view

private struct TraceView: View {
    let steps: [TraceStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(steps) { step in
                Group {
                    switch step.kind {
                    case .llmRaw(let text):
                        TraceRow(icon: "cpu", label: "LLM", content: text, color: .blue)
                    case .toolCall(let name, _, let result):
                        TraceRow(icon: "wrench.and.screwdriver", label: name, content: result, color: .orange)
                    case .parseError(let text):
                        TraceRow(icon: "exclamationmark.triangle", label: "Parse error", content: text, color: .red)
                    }
                }
            }
        }
        .padding(.leading, 8)
    }
}

private struct TraceRow: View {
    let icon: String
    let label: String
    let content: String
    let color: Color
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.1)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: icon).foregroundStyle(color)
                    Text(label).bold()
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if expanded {
                Text(content)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                    .textSelection(.enabled)
            }
        }
    }
}
