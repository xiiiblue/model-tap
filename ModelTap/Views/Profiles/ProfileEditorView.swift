import SwiftUI
import AppKit

struct ProfileEditorView: View {
    @Binding var editor: ProfileEditorState?
    @State private var isKeyVisible = true
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("接口配置") {
                    fieldRow("配置名称") {
                        LeadingAlignedTextField(text: binding(\.name))
                    }
                    fieldRow("Base URL") {
                        LeadingAlignedTextField(text: binding(\.baseURL))
                    }
                    fieldRow("API Key（可选）") {
                        HStack {
                            if isKeyVisible {
                                LeadingAlignedTextField(text: binding(\.apiKey))
                            } else {
                                LeadingAlignedTextField(text: binding(\.apiKey), isSecure: true)
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

private struct LeadingAlignedTextField: NSViewRepresentable {
    @Binding var text: String
    var isSecure = false

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField: NSTextField = isSecure ? NSSecureTextField() : NSTextField()
        textField.alignment = .left
        textField.isBezeled = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.delegate = context.coordinator
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.alignment = .left
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private var parent: LeadingAlignedTextField

        init(_ parent: LeadingAlignedTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }
    }
}
