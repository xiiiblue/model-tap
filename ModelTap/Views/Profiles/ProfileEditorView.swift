import SwiftUI

struct ProfileEditorView: View {
    @Binding var editor: ProfileEditorState?
    @State private var isKeyVisible = true
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("接口配置") {
                    TextField("配置名称", text: binding(\.name))
                        .multilineTextAlignment(.leading)
                    TextField("Base URL", text: binding(\.baseURL))
                        .textContentType(.URL)
                        .multilineTextAlignment(.leading)
                    HStack {
                        if isKeyVisible {
                            TextField("API Key（可选）", text: binding(\.apiKey))
                                .multilineTextAlignment(.leading)
                        } else {
                            SecureField("API Key（可选）", text: binding(\.apiKey))
                                .multilineTextAlignment(.leading)
                        }
                        Button { isKeyVisible.toggle() } label: { Image(systemName: isKeyVisible ? "eye.slash" : "eye") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(isKeyVisible ? "隐藏 API Key" : "显示 API Key")
                    }
                    TextField("备注（可选）", text: binding(\.notes), axis: .vertical)
                        .lineLimit(2...4)
                        .multilineTextAlignment(.leading)
                }
                Section {
                    Label("API Key 只会保存到 macOS Keychain，不会写入 SwiftData。", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editor?.profile == nil ? "新增配置" : "编辑配置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { editor = nil } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: onSave).keyboardShortcut(.defaultAction) }
            }
        }
        .frame(minWidth: 450, minHeight: 350)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<ProfileEditorState, T>) -> Binding<T> {
        Binding(get: { editor![keyPath: keyPath] }, set: { editor![keyPath: keyPath] = $0 })
    }
}
