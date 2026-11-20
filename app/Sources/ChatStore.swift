import Foundation
import SwiftUI

// MARK: - 会话模型

struct Conversation: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String = "新对话"
    var messages: [ChatMessage] = []
    var createdAt: Date = Date()

    var preview: String {
        messages.first(where: { $0.role == "user" })?.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(30).description ?? "空对话"
    }
}

// MARK: - 聊天状态

@MainActor
final class ChatStore: ObservableObject {

    // 会话列表
    @Published var conversations: [Conversation] = []
    @Published var currentId: UUID?
    @Published var isStreaming = false
    @Published var errorText: String?
    @Published var input: String = ""

    // 待发送的图片（JPEG data）
    @Published var pendingImage: Data?

    // 配置（变更即落盘）
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
    @Published var temperature: Double {
        didSet { UserDefaults.standard.set(temperature, forKey: "cfg.temperature") }
    }

    private let client = APIClient()
    private var task: Task<Void, Never>?
    private let maxHistory = 24
    private let storeKey = "store.conversations.v1"

    // MARK: 初始化

    init() {
        let d = UserDefaults.standard
        baseURL = d.string(forKey: "cfg.baseURL") ?? "https://api.deepseek.com/v1"
        model = d.string(forKey: "cfg.model") ?? "deepseek-chat"
        systemPrompt = d.string(forKey: "cfg.systemPrompt") ?? "你是一个有帮助的助手，回答简洁准确。"
        temperature = d.object(forKey: "cfg.temperature") as? Double ?? 0.7
        apiKey = SecureStore.get(key: "apiKey") ?? ""

        loadConversations()
        if conversations.isEmpty {
            conversations = [Conversation()]
            currentId = conversations[0].id
        } else {
            currentId = conversations.first?.id
        }
    }

    // MARK: 当前会话

    var current: Conversation? {
        guard let id = currentId else { return nil }
        return conversations.first(where: { $0.id == id })
    }

    var messages: [ChatMessage] {
        current?.messages ?? []
    }

    var currentTitle: String {
        current?.title ?? "新对话"
    }

    // MARK: 会话管理

    func newChat() {
        stop()
        let c = Conversation()
        conversations.insert(c, at: 0)
        currentId = c.id
        persist()
    }

    func select(_ id: UUID) {
        stop()
        currentId = id
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if currentId == id {
            currentId = conversations.first?.id
        }
        if conversations.isEmpty {
            newChat()
        }
        persist()
    }

    func clearCurrent() {
        guard let id = currentId,
              let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        stop()
        conversations[idx].messages.removeAll()
        conversations[idx].title = "新对话"
        persist()
    }

    // MARK: 发送（文字 / 图片）

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let img = pendingImage
        guard !text.isEmpty || img != nil, !isStreaming else { return }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorText = "先在设置里填 API Key"
            return
        }
        guard let id = currentId,
              let idx = conversations.firstIndex(where: { $0.id == id }) else { return }

        errorText = nil
        input = ""
        pendingImage = nil

        // 用户消息
        var userMsg = ChatMessage(role: "user", content: text)
        if let img {
            userMsg.images = [img]
        }
        conversations[idx].messages.append(userMsg)

        // 标题
        if conversations[idx].title == "新对话" {
            let t = text.isEmpty ? "图片消息" : text
            conversations[idx].title = String(t.prefix(20))
        }

        // 占位
        let placeholder = ChatMessage(role: "assistant", content: "")
        conversations[idx].messages.append(placeholder)
        persist()

        // 构造历史
        var history: [ChatMessage] = []
        let sp = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sp.isEmpty { history.append(ChatMessage(role: "system", content: sp)) }
        let msgs = conversations[idx].messages.dropLast()
        history.append(contentsOf: msgs.suffix(maxHistory))

        let key = apiKey
        let base = baseURL
        let mdl = model
        let temp = temperature
        isStreaming = true

        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await delta in self.client.streamChat(
                    baseURL: base,
                    apiKey: key,
                    model: mdl,
                    messages: history,
                    temperature: temp
                ) {
                    if let ci = self.conversations.firstIndex(where: { $0.id == id }),
                       let mi = self.conversations[ci].messages.firstIndex(where: { $0.id == placeholder.id }) {
                        self.conversations[ci].messages[mi].content += delta
                    }
                }
            } catch {
                if !(error is CancellationError) {
                    self.errorText = error.localizedDescription
                }
            }
            // 清理空回复
            if let ci = self.conversations.firstIndex(where: { $0.id == id }),
               let mi = self.conversations[ci].messages.firstIndex(where: { $0.id == placeholder.id }),
               self.conversations[ci].messages[mi].content.isEmpty {
                self.conversations[ci].messages.remove(at: mi)
            }
            self.isStreaming = false
            self.persist()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isStreaming = false
    }

    // MARK: 持久化

    private func persist() {
        if let data = try? JSONEncoder().encode(conversations) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
        if let id = currentId {
            UserDefaults.standard.set(id.uuidString, forKey: "store.currentId")
        }
    }

    private func loadConversations() {
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let list = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = list
        }
        if let s = UserDefaults.standard.string(forKey: "store.currentId"),
           let id = UUID(uuidString: s) {
            currentId = id
        }
    }

    // MARK: 导出

    func exportMarkdown() -> String {
        var md = "# 哀世界 对话导出\n\n导出时间：\(Date().formatted())\n\n"
        for c in conversations {
            md += "---\n\n## \(c.title)\n\n"
            for m in c.messages {
                md += (m.role == "user" ? "**我：**" : "**AI：**") + "\n\n"
                if let imgs = m.images, !imgs.isEmpty {
                    md += "_[含 \(imgs.count) 张图片]_\n\n"
                }
                md += (m.content) + "\n\n"
            }
        }
        return md
    }
}
