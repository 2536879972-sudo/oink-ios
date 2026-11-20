import SwiftUI
import PhotosUI

struct ChatView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var showSettings = false
    @State private var showSessions = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isRecording = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if store.messages.isEmpty {
                            EmptyStateView().padding(.top, 50)
                        }

                        ForEach(store.messages) { msg in
                            MessageBubble(message: msg).id(msg.id)
                        }

                        if store.isStreaming {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("思考中…").font(.footnote).foregroundStyle(.secondary)
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
            .navigationTitle(store.currentTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSessions = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            store.clearCurrent()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(store.messages.isEmpty)

                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(store)
            }
            .sheet(isPresented: $showSessions) {
                SessionListView().environmentObject(store)
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPicker { data in
                    store.pendingImage = data
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { data in
                    store.pendingImage = data
                }
            }
            .alert("出错了", isPresented: Binding(
                get: { store.errorText != nil },
                set: { if !$0 { store.errorText = nil } }
            )) {
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

    // MARK: 输入栏

    private var composer: some View {
        VStack(spacing: 6) {
            // 图片预览
            if let img = store.pendingImage, let ui = UIImage(data: img) {
                HStack {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Button {
                            store.pendingImage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white, .red)
                        }
                        .offset(x: 6, y: -6)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            HStack(alignment: .bottom, spacing: 6) {
                // 相册
                Button { showPhotoPicker = true } label: {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
                // 拍照
                Button { showCamera = true } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }

                TextField("说点什么…", text: $store.input, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

                // 语音
                Button {
                    isRecording.toggle()
                } label: {
                    Image(systemName: isRecording ? "waveform.circle.fill" : "mic.circle")
                        .font(.system(size: 26))
                        .foregroundStyle(isRecording ? .red : .secondary)
                }
                .accessibilityLabel("语音输入")
                .onChange(of: isRecording) { v in
                    if v { startVoice() } else { stopVoice() }
                }

                // 发送 / 停止
                if store.isStreaming {
                    Button { store.stop() } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.red)
                    }
                } else {
                    Button {
                        store.send()
                        inputFocused = true
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .background(.bar)
    }

    private var canSend: Bool {
        !store.input.trimmingCharacters(in: .whitespaces).isEmpty || store.pendingImage != nil
    }

    // MARK: 语音

    @StateObject private var speech = SpeechInput()

    private func startVoice() {
        speech.start { text in
            store.input = (store.input + " " + text).trimmingCharacters(in: .whitespaces)
            isRecording = false
        }
    }

    private func stopVoice() {
        speech.stop()
    }
}

// MARK: - 气泡

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 44) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                // 图片
                if let imgs = message.images, !imgs.isEmpty {
                    ForEach(Array(imgs.enumerated()), id: \.offset) { _, d in
                        if let ui = UIImage(data: d) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }

                // 文字
                if !message.content.isEmpty {
                    Text(message.content)
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
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("开始聊天")
                .font(.headline)
            Text("文字 · 图片 · 语音")
                .font(.caption)
                .foregroundStyle(.secondary)
            if store.apiKey.isEmpty {
                Text("点右上角齿轮填 API Key")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 会话列表

struct SessionListView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.conversations, id: \.id) { (c: Conversation) in
                    Button {
                        store.select(c.id)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(c.title).font(.body).lineLimit(1)
                                Text(c.preview)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if c.id == store.currentId {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.accent)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.delete(c.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.newChat()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}
