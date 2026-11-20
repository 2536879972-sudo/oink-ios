import Foundation

/// 模型预设：点一下自动填好 Base URL 与模型名
struct ModelPreset: Identifiable {
    let id: String
    let name: String
    let base: String
    let model: String

    static let all: [ModelPreset] = [
        ModelPreset(
            id: "ds-v3",
            name: "DeepSeek V3",
            base: "https://api.deepseek.com/v1",
            model: "deepseek-chat"
        ),
        ModelPreset(
            id: "ds-r1",
            name: "DeepSeek R1（推理）",
            base: "https://api.deepseek.com/v1",
            model: "deepseek-reasoner"
        ),
        ModelPreset(
            id: "or-claude",
            name: "Claude 3.5 Sonnet（写得好）",
            base: "https://openrouter.ai/api/v1",
            model: "anthropic/claude-3.5-sonnet"
        ),
        ModelPreset(
            id: "or-dolphin",
            name: "Dolphin 8x7B（无审核）",
            base: "https://openrouter.ai/api/v1",
            model: "cognitivecomputations/dolphin-mixtral-8x7b"
        ),
        ModelPreset(
            id: "or-gpt4o",
            name: "GPT-4o（均衡）",
            base: "https://openrouter.ai/api/v1",
            model: "openai/gpt-4o"
        ),
    ]
}
