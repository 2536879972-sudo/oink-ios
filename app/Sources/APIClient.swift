import Foundation

// MARK: - 数据模型

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    var role: String          // "user" / "assistant" / "system"
    var content: String
    var images: [Data]?       // 图片（JPEG）

    init(id: UUID = UUID(), role: String, content: String, images: [Data]? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.images = images
    }
}

// MARK: - 错误

enum APIError: LocalizedError {
    case badURL
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .badURL:               return "接口地址无效，检查 Base URL"
        case .http(let c, let b):   return "HTTP \(c)\n\(b.prefix(400))"
        case .badResponse:          return "服务器返回格式异常"
        }
    }
}

// MARK: - 线格式

/// 支持纯文本或多模态 parts 的 content
private enum WireContent: Encodable {
    case text(String)
    case parts([Part])

    struct Part: Encodable {
        let type: String          // "text" / "image_url"
        let text: String?
        let image_url: ImageURL?

        struct ImageURL: Encodable {
            let url: String
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let t):   try c.encode(t)
        case .parts(let ps): try c.encode(ps)
        }
    }
}

private struct WireMessage: Encodable {
    let role: String
    let content: WireContent
}

private struct WireRequest: Encodable {
    let model: String
    let messages: [WireMessage]
    let stream: Bool
    let temperature: Double
}

private struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
            let reasoning_content: String?
        }
        let delta: Delta?
        let finish_reason: String?
    }
    let choices: [Choice]
}

// MARK: - 客户端

struct APIClient {

    func streamChat(baseURL: String,
                    apiKey: String,
                    model: String,
                    messages: [ChatMessage],
                    temperature: Double = 0.7) -> AsyncThrowingStream<String, Error> {

        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = Self.endpoint(from: baseURL) else { throw APIError.badURL }

                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.timeoutInterval = 180
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

                    let wire: [WireMessage] = messages.map { m in
                        if let imgs = m.images, !imgs.isEmpty {
                            var parts: [WireContent.Part] = []
                            let txt = m.content.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !txt.isEmpty {
                                parts.append(.init(type: "text", text: txt, image_url: nil))
                            }
                            for d in imgs {
                                let b64 = d.base64EncodedString()
                                parts.append(.init(
                                    type: "image_url",
                                    text: nil,
                                    image_url: .init(url: "data:image/jpeg;base64,\(b64)")
                                ))
                            }
                            return WireMessage(role: m.role, content: .parts(parts))
                        } else {
                            return WireMessage(role: m.role, content: .text(m.content))
                        }
                    }

                    let payload = WireRequest(
                        model: model,
                        messages: wire,
                        stream: true,
                        temperature: temperature
                    )
                    req.httpBody = try JSONEncoder().encode(payload)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)

                    guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }
                    guard (200..<300).contains(http.statusCode) else {
                        var raw = ""
                        for try await line in bytes.lines { raw += line }
                        throw APIError.http(http.statusCode, raw)
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let body = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if body.isEmpty { continue }
                        if body == "[DONE]" { break }
                        guard let data = body.data(using: .utf8) else { continue }
                        if let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                           let text = chunk.choices.first?.delta?.content,
                           !text.isEmpty {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func endpoint(from base: String) -> URL? {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        if !s.hasSuffix("/chat/completions") { s += "/chat/completions" }
        return URL(string: s)
    }
}
