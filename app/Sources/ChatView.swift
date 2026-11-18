import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var showSettings = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if store.messages.isEmpty {
                            EmptyStateView()
                                .padding(.top, 60)
                        }

                        ForEach(store.messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }

                        if store.isStreaming {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("思考中…")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .id("__typing__")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: store.messages.count) { _ in scrollToBottom(proxy) }
                .onChange(of: store.isStreaming) { _ in scrollToBottom(proxy) }
                .onChange(of: store.messages.last?.content) { _ in scrollToBottom(proxy) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationTitle("小码酱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.clear()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(store.messages.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(store)
            }
            .alert("出错了", isPresented: Binding(
                get: { store.errorText != nil },
                set: { if !$0 { store.errorText = nil } }
            )) {
                Button("重试") { store.errorText = nil; store.retryLast() }
                Button("知道了", role: .cancel) { store.errorText = nil }
            } message: {
                Text(store.errorText ?? "")
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            if store.isStreaming {
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("__typing__", anchor: .bottom)
                }
            } else if let last = store.messages.last {
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("说点什么…", text: $store.input, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if store.isStreaming {
                Button {
                    store.stop()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("停止")
            } else {
                Button {
                    store.send()
                    inputFocused = true
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(store.input.isEmpty ? Color.secondary : Color.accentColor)
                }
                .disabled(store.input.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("发送")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - 气泡

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 44) }

            Text(message.content.isEmpty ? " " : message.content)
                .font(.system(size: 16))
                .foregroundStyle(isUser ? Color.white : Color.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(isUser ? Color.accentColor : Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = message.content
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                }

            if !isUser { Spacer(minLength: 44) }
        }
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    @EnvironmentObject private var store: ChatStore

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("已连接到 \(store.model)")
                .font(.headline)
            Text("API 走 \(store.baseURL)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if store.apiKey.isEmpty {
                Text("点右上角齿轮填 API Key")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
