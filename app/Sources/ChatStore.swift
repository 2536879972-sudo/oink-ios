import Foundation
import SwiftUI

@MainActor
final class ChatStore: ObservableObject {

    // MARK: 会话

    @Published var messages: [ChatMessage] = []
    @Published var input: String = ""
    @Published var isStreaming: Bool = false
    @Published var errorText: String?

    // MARK: 配置（改了就落盘）

    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: "cfg.baseURL") }
    }
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "cfg.model") }
    }
    @Published var apiKey: String {
        didSet { SecureStore.set(apiKey, key: "apiKey") }
    }
    @Published var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: "cfg.systemPrompt") }
    }

    private let client = APIClient()
    private var task: Task<Void, Never>?
    private let maxHistory = 24

    init() {
        let d = UserDefaults.standard
        baseURL = d.string(forKey: "cfg.baseURL") ?? "https://api.deepseek.com/v1"
        model = d.string(forKey: "cfg.model") ?? "deepseek-chat"
        systemPrompt = d.string(forKey: "cfg.systemPrompt") ?? "你是小码酱，技术问题直接给可运行的结果。"
        apiKey = SecureStore.get(key: "apiKey") ?? ""
    }

    // MARK: 发送

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorText = "先在设置里填 API Key"
            return
        }

        errorText = nil
        input = ""
        messages.append(ChatMessage(role: "user", content: text))

        let placeholder = ChatMessage(role: "assistant", content: "")
        messages.append(placeholder)

        // 带上 system prompt + 最近 N 条，防止上下文撑爆
        var history: [ChatMessage] = []
        let sp = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sp.isEmpty {
            history.append(ChatMessage(role: "system", content: sp))
        }
        history.append(contentsOf: messages.dropLast().suffix(maxHistory))

        let key = apiKey
        let base = baseURL
        let mdl = model
        isStreaming = true

        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await delta in self.client.streamChat(
                    baseURL: base,
                    apiKey: key,
                    model: mdl,
                    messages: history
                ) {
                    if let idx = self.messages.firstIndex(where: { $0.id == placeholder.id }) {
                        self.messages[idx].content += delta
                    }
                }
            } catch {
                if !(error is CancellationError) {
                    self.errorText = error.localizedDescription
                }
            }

            if let idx = self.messages.firstIndex(where: { $0.id == placeholder.id }),
               self.messages[idx].content.isEmpty {
                self.messages.remove(at: idx)
            }
            self.isStreaming = false
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isStreaming = false
    }

    func clear() {
        stop()
        messages.removeAll()
        errorText = nil
    }

    func retryLast() {
        guard let lastUser = messages.last(where: { $0.role == "user" }) else { return }
        if let idx = messages.lastIndex(where: { $0.role == "assistant" }) {
            messages.removeSubrange(idx...)
        }
        input = lastUser.content
        if let idx = messages.lastIndex(where: { $0.role == "user" }) {
            messages.remove(at: idx)
        }
        send()
    }
}
