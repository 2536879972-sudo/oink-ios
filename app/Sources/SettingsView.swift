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
                    ForEach(ModelPreset.all, id: \.id) { p in
                        Button {
                            store.baseURL = p.base
                            store.model = p.model
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(p.name)
                                        .foregroundStyle(.primary)
                                    Text(p.model)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.model == p.model && store.baseURL == p.base {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                } header: {
                    Text("快速切换")
                } footer: {
                    Text("点一下自动填好 Base URL 和模型名。Dolphin 无内容审核，需配合 OpenRouter。")
                }

                Section {
                    HStack {
                        Text("温度")
                        Spacer()
                        Text(String(format: "%.2f", store.temperature))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $store.temperature, in: 0.0...1.2, step: 0.05)
                    HStack(spacing: 10) {
                        ForEach([0.3, 0.7, 0.95, 1.1], id: \.self) { v in
                            Button(String(format: "%.2f", v)) {
                                store.temperature = v
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                } header: {
                    Text("参数")
                } footer: {
                    Text("越低越保守稳定，越高越发散。角色扮演建议 0.95~1.10，技术问答建议 0.3~0.7。")
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
                        store.clearCurrent()
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
