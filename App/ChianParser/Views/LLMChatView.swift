import SwiftUI

struct LLMChatView: View {
    @State private var viewModel: LLMChatViewModel
    @Environment(AppContainer.self) private var container

    init(llm: any LLMServiceProtocol) {
        _viewModel = State(wrappedValue: LLMChatViewModel(llm: llm))
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            messageList
            Divider()
            inputBar
        }
        .navigationTitle("LLM Test Chat")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if case .downloading(let p) = viewModel.llmState {
                    ProgressView(value: p)
                        .frame(width: 100)
                }
            }
        }
    }

    // MARK: - Subviews

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(viewModel.llmState.statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if case .idle = viewModel.llmState {
                Button("Load Model") { viewModel.loadModel() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) {
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Type a message…", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .onSubmit {
                    if viewModel.canSend { viewModel.send() }
                }

            Button {
                viewModel.send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(viewModel.canSend ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSend)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(12)
        .background(.bar)
    }

    private var statusColor: Color {
        switch viewModel.llmState {
        case .ready:                     return .green
        case .generating:                return .yellow
        case .error:                     return .red
        case .downloading, .loading:     return .blue
        case .idle:                      return .secondary
        }
    }
}

// MARK: - MessageBubble

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
                Text(message.role == .user ? "You" : "Gemma 4 E2B")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(message.text.isEmpty ? "…" : message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.role == .user ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Preview

#Preview {
    LLMChatView(llm: PreviewLLMService())
        .frame(width: 500, height: 600)
        .environment(AppContainer())
}

@MainActor
private final class PreviewLLMService: LLMServiceProtocol {
    var state: LLMState = .ready
    func loadModel() {}
    func generate(prompt: String) async throws -> String { "Preview response" }
    func generateStreaming(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { c in c.yield("Preview response"); c.finish() }
    }
}
