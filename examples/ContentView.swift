import SwiftUI

@main
struct ToolApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("输入") {
                    TextField("内容", text: $input, axis: .vertical)
                        .lineLimit(3...8)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("结果") {
                    if output.isEmpty {
                        Text("—").foregroundStyle(.secondary)
                    } else {
                        Text(output)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                Section {
                    Button {
                        busy = true
                        output = transform(input)
                        busy = false
                    } label: {
                        HStack {
                            Text("执行")
                            Spacer()
                            if busy { ProgressView() }
                        }
                    }
                    .disabled(input.isEmpty || busy)

                    Button("复制结果") {
                        UIPasteboard.general.string = output
                    }
                    .disabled(output.isEmpty)
                }
            }
            .navigationTitle("工具")
        }
    }

    private func transform(_ s: String) -> String {
        // 换成你的实际逻辑：解析、转换、查表、请求网络……
        s.uppercased()
    }
}
