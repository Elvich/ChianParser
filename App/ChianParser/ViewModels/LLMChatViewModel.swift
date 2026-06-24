import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var text: String

    enum Role {
        case user, assistant
    }
}

@MainActor
@Observable
final class LLMChatViewModel {

    private(set) var messages: [ChatMessage] = []
    var inputText: String = ""
    var isStreaming: Bool = false

    private let llm: any LLMServiceProtocol

    var llmState: LLMState { llm.state }
    var canSend: Bool { llm.state.isReady && !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isStreaming }

    init(llm: any LLMServiceProtocol) {
        self.llm = llm
    }

    // MARK: - Actions

    func loadModel() {
        llm.loadModel()
    }

    func send() {
        let prompt = inputText.trimmingCharacters(in: .whitespaces)
        guard !prompt.isEmpty, llm.state.isReady else { return }

        inputText = ""
        messages.append(ChatMessage(role: .user, text: prompt))

        let placeholder = ChatMessage(role: .assistant, text: "")
        messages.append(placeholder)
        let assistantIndex = messages.endIndex - 1

        isStreaming = true

        Task {
            defer { isStreaming = false }

            do {
                for try await piece in llm.generateStreaming(prompt: prompt) {
                    messages[assistantIndex].text += piece
                }
            } catch {
                messages[assistantIndex].text = "Error: \(error.localizedDescription)"
            }
        }
    }
}
