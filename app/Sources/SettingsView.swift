import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://api.deepseek.com/v1", text: $store.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))
                    TextField("deepseek-chat", text: $store.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("接口")
                } footer: {
                    Text("Base URL 填到 /v1 就行，App 自动补 /chat/completions。")
                }

                Section("API Key") {
                    SecureField("sk-…", text: $store.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }

                Section {
                    TextField("系统提示词", text: $store.systemPrompt, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("人格")
                } footer: {
                    Text("每次请求作为 system 消息发送。")
                }

                Section {
                    LabeledContent("实际请求地址") {
                        Text(APIClient.endpoint(from: store.baseURL)?.absoluteString ?? "无效")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    Button {
                        store.clear()
                        dismiss()
                    } label: {
                        Text("清空当前会话").foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
