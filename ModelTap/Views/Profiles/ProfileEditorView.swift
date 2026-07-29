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
            VStack(spacing: 0) {
                editorContent
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                Spacer(minLength: 0)
            }
            .navigationTitle(editor?.profile == nil ? "新增配置" : "编辑配置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if #available(macOS 26.0, *) {
                        Button("取消") { editor = nil }
                            .buttonStyle(.glass)
                    } else {
                        Button("取消") { editor = nil }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if #available(macOS 26.0, *) {
                        Button("保存", action: onSave)
                            .buttonStyle(.glassProminent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(!canSave)
                    } else {
                        Button("保存", action: onSave)
                            .keyboardShortcut(.defaultAction)
                            .disabled(!canSave)
                    }
                }
            }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 590, idealHeight: 610)
    }

    @ViewBuilder
    private var editorContent: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 22) {
                editorSections
            }
        } else {
            editorSections
        }
    }

    private var editorSections: some View {
        VStack(alignment: .leading, spacing: 22) {
            editorSection("基本信息") {
                VStack(spacing: 0) {
                    fieldRow("配置名称") {
                        LeadingAlignedTextField(
                            text: binding(\.name, defaultValue: "")
                        )
                        .accessibilityLabel("配置名称")
                    }
                    rowDivider
                    fieldRow("文件夹") {
                        Picker(
                            "文件夹",
                            selection: binding(
                                \.folderID,
                                defaultValue: Optional<UUID>.none
                            )
                        ) {
                            Text("未分类")
                                .tag(Optional<UUID>.none)
                            ForEach(folders) { folder in
                                Text(folder.name)
                                    .tag(Optional(folder.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("文件夹")
                    }
                }
            }

            editorSection("接口配置") {
                VStack(spacing: 0) {
                    fieldRow("Base URL") {
                        LeadingAlignedTextField(
                            text: binding(\.baseURL, defaultValue: "")
                        )
                        .accessibilityLabel("Base URL")
                    }
                    rowDivider
                    fieldRow("API格式") {
                        Picker(
                            "API格式",
                            selection: binding(
                                \.apiFormat,
                                defaultValue: APIFormat.openAI
                            )
                        ) {
                            ForEach(APIFormat.allCases, id: \.self) { format in
                                Text(format.title)
                                    .tag(format)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("API格式")
                    }
                    rowDivider
                    fieldRow("API Key（可选）") {
                        HStack(spacing: 8) {
                            if isKeyVisible {
                                LeadingAlignedTextField(
                                    text: binding(\.apiKey, defaultValue: "")
                                )
                            } else {
                                LeadingAlignedTextField(
                                    text: binding(\.apiKey, defaultValue: ""),
                                    isSecure: true
                                )
                            }
                            Button {
                                isKeyVisible.toggle()
                            } label: {
                                Image(
                                    systemName: isKeyVisible
                                        ? "eye.slash"
                                        : "eye"
                                )
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(
                                isKeyVisible
                                    ? "隐藏API Key"
                                    : "显示API Key"
                            )
                        }
                        .accessibilityElement(children: .contain)
                    }
                }
            }

            editorSection("备注（可选）") {
                LeadingAlignedTextEditor(
                    text: binding(\.notes, defaultValue: "")
                )
                .frame(height: 138)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .accessibilityLabel("备注")
            }
        }
    }

    private var rowDivider: some View {
        Divider()
            .padding(.horizontal, 16)
    }

    private func editorSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.leading, 4)
            editorCard(content: content)
        }
    }

    @ViewBuilder
    private func editorCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(macOS 26.0, *) {
            content()
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
        } else {
            content()
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.primary.opacity(0.08))
                }
        }
    }

    private var canSave: Bool {
        guard let editor else { return false }
        return !editor.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !editor.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
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
        textField.maximumNumberOfLines = 1
        textField.lineBreakMode = .byClipping
        textField.cell?.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
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
        nsView.maximumNumberOfLines = 1
        nsView.lineBreakMode = .byClipping
        nsView.cell?.usesSingleLineMode = true
        nsView.cell?.wraps = false
        nsView.cell?.isScrollable = true
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
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
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
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
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
