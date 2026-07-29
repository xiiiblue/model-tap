import SwiftUI
import AppKit
import SwiftData

struct ProfileEditorView: View {
    @Query(sort: \ProfileFolder.name) private var folders: [ProfileFolder]
    @Binding var editor: ProfileEditorState?
    @State private var isKeyVisible = false
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    fieldRow("配置名称") {
                        LeadingAlignedTextField(text: binding(\.name, defaultValue: ""))
                    }
                    fieldRow("文件夹") {
                        Picker("", selection: binding(\.folderID, defaultValue: nil)) {
                            Text("未分类").tag(Optional<UUID>.none)
                            ForEach(folders) { folder in
                                Text(folder.name).tag(Optional(folder.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                Section("接口配置") {
                    fieldRow("Base URL") {
                        LeadingAlignedTextField(text: binding(\.baseURL, defaultValue: ""))
                    }
                    fieldRow("API格式") {
                        Menu {
                            ForEach(APIFormat.allCases, id: \.self) { format in
                                Button {
                                    editor?.apiFormat = format
                                } label: {
                                    HStack {
                                        Text(format.title)
                                        if editor?.apiFormat == format {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(editor?.apiFormat.title ?? APIFormat.openAI.title)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .accessibilityLabel("API格式")
                    }
                    fieldRow("API Key（可选）") {
                        HStack {
                            if isKeyVisible {
                                LeadingAlignedTextField(text: binding(\.apiKey, defaultValue: ""))
                            } else {
                                LeadingAlignedTextField(text: binding(\.apiKey, defaultValue: ""), isSecure: true)
                            }
                            Button { isKeyVisible.toggle() } label: { Image(systemName: isKeyVisible ? "eye.slash" : "eye") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(isKeyVisible ? "隐藏 API Key" : "显示 API Key")
                        }
                    }
                }

                Section("备注（可选）") {
                    LeadingAlignedTextEditor(text: binding(\.notes, defaultValue: ""))
                        .frame(minHeight: 110, idealHeight: 130, maxHeight: 180)
                }
            }
            .formStyle(.grouped)
            .scrollIndicators(.hidden)
            .navigationTitle(editor?.profile == nil ? "新增配置" : "编辑配置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { editor = nil } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: onSave).keyboardShortcut(.defaultAction) }
            }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 480, idealHeight: 520)
    }

    private func binding<T>(
        _ keyPath: WritableKeyPath<ProfileEditorState, T>,
        defaultValue: T
    ) -> Binding<T> {
        Binding(
            get: { editor?[keyPath: keyPath] ?? defaultValue },
            set: { editor?[keyPath: keyPath] = $0 }
        )
    }

    @ViewBuilder
    private func fieldRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .frame(width: 108, alignment: .leading)
                .padding(.top, 3)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
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

private struct LeadingAlignedTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.alignment = .left
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.drawsBackground = false
        textView.focusRingType = .none
        textView.textContainerInset = NSSize(width: 0, height: 6)
        textView.textContainer?.lineFragmentPadding = 2
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if textView.string != text {
            textView.string = text
        }
        textView.alignment = .left
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LeadingAlignedTextEditor

        init(_ parent: LeadingAlignedTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
