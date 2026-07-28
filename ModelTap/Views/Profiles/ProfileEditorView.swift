import SwiftUI

struct ProfileEditorView: View {
    @Binding var editor: ProfileEditorState?
    @State private var isKeyVisible = true
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("接口配置") {
                    fieldRow("配置名称") {
                        TextField("", text: binding(\.name))
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.leading)
                    }
                    fieldRow("Base URL") {
                        TextField("", text: binding(\.baseURL))
                            .textFieldStyle(.plain)
                            .textContentType(.URL)
                            .multilineTextAlignment(.leading)
                    }
                    fieldRow("API Key（可选）") {
                        HStack {
                            if isKeyVisible {
                                TextField("", text: binding(\.apiKey))
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.leading)
                            } else {
                                SecureField("", text: binding(\.apiKey))
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.leading)
                            }
                            Button { isKeyVisible.toggle() } label: { Image(systemName: isKeyVisible ? "eye.slash" : "eye") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(isKeyVisible ? "隐藏 API Key" : "显示 API Key")
                        }
                    }
                    fieldRow("备注（可选）") {
                        TextField("", text: binding(\.notes), axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(2...4)
                            .multilineTextAlignment(.leading)
                    }
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

    @ViewBuilder
    private func fieldRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 120, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
