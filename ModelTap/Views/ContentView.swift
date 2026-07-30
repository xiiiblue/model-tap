import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel: ContentViewModel
    @State private var isExporterPresented = false
    @State private var exportDocument = MarkdownBackupDocument(text: "")
    @State private var isImporterPresented = false
    @State private var pendingImport: ModelTapBackup?
    @State private var hasSelectedAPIKey = false
    @State private var selectedAPIKey = ""
    @State private var isSelectedAPIKeyVisible = false
    @State private var isManualModelPopoverPresented = false
    @State private var manualModelID = ""

    init(modelContext: ModelContext? = nil) {
        if let modelContext {
            _viewModel = StateObject(wrappedValue: ContentViewModel(modelContext: modelContext))
        } else {
            let container: ModelContainer
            do {
                container = try ModelContainer(for: APIProfile.self, ProfileFolder.self, ModelTestRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            } catch {
                fatalError("Preview model container creation failed")
            }
            _viewModel = StateObject(wrappedValue: ContentViewModel(modelContext: ModelContext(container)))
        }
    }

    var body: some View {
        NavigationSplitView {
            ProfileListView(
                selectedProfile: $viewModel.selectedProfile,
                searchText: $viewModel.searchText,
                onNew: viewModel.startNewProfile,
                onEdit: viewModel.edit,
                onDelete: viewModel.delete,
                onDuplicate: viewModel.duplicate,
                onCopyURL: copyURL,
                onCopyKey: copyKey,
                onCopyEnvironment: copyEnvironment,
                onCreateFolder: viewModel.createFolder,
                onRenameFolder: viewModel.renameFolder,
                onDeleteFolder: viewModel.deleteFolder,
                onMoveProfile: viewModel.move,
                onApplySort: viewModel.applySidebarSort
            )
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            detailView
        }
        .navigationTitle(viewModel.selectedProfile?.name ?? "ModelTap")
        .frame(minWidth: 900, minHeight: 560)
        .toolbar {
            if let profile = viewModel.selectedProfile {
                ToolbarItem(placement: .primaryAction) {
                    Button("编辑配置", systemImage: "pencil") {
                        viewModel.edit(profile)
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(
                        "导入配置备份",
                        systemImage: "square.and.arrow.down"
                    ) {
                        isImporterPresented = true
                    }
                    Button(
                        "导出配置备份",
                        systemImage: "square.and.arrow.up"
                    ) {
                        prepareExport()
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
                .help("导入或导出Markdown配置备份")
            }
        }
        .sheet(item: $viewModel.editor) { _ in
            ProfileEditorView(
                editor: $viewModel.editor,
                onSave: {
                    try viewModel.saveEditor()
                    loadSelectedAPIKey()
                }
            )
        }
        .alert(item: $viewModel.notice) { notice in Alert(title: Text(notice.message)) }
        .overlay(alignment: .bottom) {
            if let toast = viewModel.toast {
                CopyToast(message: toast.message)
                    .id(toast.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 24)
            }
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.toast)
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .modelTapMarkdown,
            defaultFilename: "ModelTap-Backup"
        ) { result in
            if case .failure(let error) = result {
                show(error)
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.modelTapMarkdown, .plainText],
            allowsMultipleSelection: false,
            onCompletion: handleImportSelection
        )
        .confirmationDialog(
            "导入配置备份？",
            isPresented: pendingImportBinding,
            titleVisibility: .visible
        ) {
            Button("替换当前全部数据", role: .destructive) {
                guard let backup = pendingImport else { return }
                pendingImport = nil
                viewModel.replaceAll(with: backup)
            }
            Button("取消", role: .cancel) {
                pendingImport = nil
            }
        } message: {
            if let backup = pendingImport {
                Text(
                    "将清空当前配置和测试记录，并导入\(backup.folders.count)个文件夹和\(backup.profiles.count)项配置。"
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .modelTapNewProfile)) { _ in viewModel.startNewProfile() }
        .onChange(of: viewModel.selectedProfile) { _, _ in
            viewModel.selectedProfileDidChange()
            loadSelectedAPIKey()
        }
        .task { loadSelectedAPIKey() }
    }

    @ViewBuilder private var detailView: some View {
        if let profile = viewModel.selectedProfile {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ConnectionOverview(
                        profile: profile,
                        hasAPIKey: hasSelectedAPIKey,
                        apiKey: selectedAPIKey,
                        isAPIKeyVisible: isSelectedAPIKeyVisible,
                        onToggleKeyVisibility: {
                            isSelectedAPIKeyVisible.toggle()
                        },
                        onCopyURL: { copyURL(profile) },
                        onCopyKey: { copyKey(profile) },
                        onCopyEnvironment: { copyEnvironment(profile) },
                        onCopyNotes: { copyNotes(profile) }
                    )

                    Divider()

                    modelWorkspace
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        } else {
            ContentUnavailableView("选择一个 API 配置", systemImage: "point.3.connected.trianglepath.dotted", description: Text("从左侧选择配置，或新建一个配置开始。"))
        }
    }

    private var modelWorkspace: some View {
        VStack(spacing: 0) {
            HStack {
                Text("模型与测试")
                    .font(.headline)
                Spacer()
                modelActionButtons
            }
            .padding(.vertical, 10)

            Divider()
            ModelListView(
                viewModel: viewModel,
                onManualInput: presentManualModelPopover
            )
        }
    }

    @ViewBuilder
    private var modelActionButtons: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    queryModelsButton
                        .buttonStyle(.glass)
                    manualInputButton
                        .buttonStyle(.glass)
                }
            }
        } else {
            HStack(spacing: 8) {
                queryModelsButton
                manualInputButton
            }
        }
    }

    private var queryModelsButton: some View {
        Button(
            "查询模型",
            systemImage: "arrow.clockwise",
            action: viewModel.discover
        )
        .disabled(
            viewModel.loadState == .loading
                || !viewModel.testingModelIDs.isEmpty
        )
    }

    private var manualInputButton: some View {
        Button("手动输入", systemImage: "plus") {
            presentManualModelPopover()
        }
        .popover(
            isPresented: $isManualModelPopoverPresented,
            arrowEdge: .top
        ) {
            manualModelPopover
        }
    }

    private var manualModelPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("手动输入模型")
                .font(.headline)
            TextField("模型ID", text: $manualModelID)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .onSubmit {
                    addManualModel(testAfterAdding: false)
                }
            HStack {
                Spacer()
                Button("添加") {
                    addManualModel(testAfterAdding: false)
                }
                .disabled(normalizedManualModelID.isEmpty)
                Button("添加并测试") {
                    addManualModel(testAfterAdding: true)
                }
                .buttonStyle(.borderedProminent)
                .disabled(normalizedManualModelID.isEmpty)
            }
        }
        .padding(18)
    }

    private var normalizedManualModelID: String {
        manualModelID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func presentManualModelPopover() {
        manualModelID = ""
        isManualModelPopoverPresented = true
    }

    private func addManualModel(testAfterAdding: Bool) {
        let modelID = normalizedManualModelID
        guard !modelID.isEmpty else { return }
        isManualModelPopoverPresented = false
        viewModel.addManualModel(
            id: modelID,
            testAfterAdding: testAfterAdding
        )
        manualModelID = ""
    }

    private func copyURL(_ profile: APIProfile) {
        Clipboard.copy(profile.baseURL)
        viewModel.showToast("Base URL已复制")
    }

    private func copyKey(_ profile: APIProfile) {
        do {
            let key = try viewModel.repository.apiKey(for: profile)
            guard !key.isEmpty else {
                viewModel.showToast("未设置API Key")
                return
            }
            Clipboard.copy(key, sensitive: true)
            viewModel.showToast("API Key已复制")
        } catch {
            show(error)
        }
    }

    private func copyEnvironment(_ profile: APIProfile) {
        do {
            let key = try viewModel.repository.apiKey(for: profile)
            Clipboard.copy(
                environmentExample(for: profile, apiKey: key),
                sensitive: !key.isEmpty
            )
            viewModel.showToast("环境变量已复制")
        } catch {
            show(error)
        }
    }

    private func copyNotes(_ profile: APIProfile) {
        Clipboard.copy(profile.notes)
        viewModel.showToast("备注已复制")
    }

    private func loadSelectedAPIKey() {
        isSelectedAPIKeyVisible = false
        guard let profile = viewModel.selectedProfile else {
            selectedAPIKey = ""
            hasSelectedAPIKey = false
            return
        }
        do {
            selectedAPIKey = try viewModel.repository.apiKey(for: profile)
            hasSelectedAPIKey = !selectedAPIKey.isEmpty
        } catch {
            selectedAPIKey = ""
            hasSelectedAPIKey = false
            show(error)
        }
    }

    private var pendingImportBinding: Binding<Bool> {
        Binding(
            get: { pendingImport != nil },
            set: { if !$0 { pendingImport = nil } }
        )
    }

    private func prepareExport() {
        do {
            exportDocument = MarkdownBackupDocument(
                text: try viewModel.markdownBackup()
            )
            isExporterPresented = true
        } catch {
            show(error)
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let markdown = try String(contentsOf: url, encoding: .utf8)
            pendingImport = try MarkdownBackupCodec.decode(markdown)
        } catch {
            show(error)
        }
    }

    private func show(_ error: Error) {
        viewModel.notice = RequestNotice(
            message: ContentViewModel.friendlyMessage(error)
        )
    }
}

private struct MarkdownBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.modelTapMarkdown, .plainText]
    }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private extension UTType {
    static var modelTapMarkdown: UTType {
        UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
    }
}

private struct ConnectionOverview: View {
    let profile: APIProfile
    let hasAPIKey: Bool
    let apiKey: String
    let isAPIKeyVisible: Bool
    let onToggleKeyVisibility: () -> Void
    let onCopyURL: () -> Void
    let onCopyKey: () -> Void
    let onCopyEnvironment: () -> Void
    let onCopyNotes: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("连接信息")
                    .font(.headline)
                Text(profile.apiFormat.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }

            connectionCard
        }
    }

    @ViewBuilder
    private var connectionCard: some View {
        if #available(macOS 26.0, *) {
            connectionRows
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
        } else {
            connectionRows
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

    private var connectionRows: some View {
        VStack(spacing: 0) {
            credentialRow(
                title: "Base URL",
                value: profile.baseURL,
                onCopy: onCopyURL
            )
            Divider()
                .padding(.horizontal, 16)
            credentialRow(
                title: "API Key",
                value: isAPIKeyVisible && hasAPIKey
                    ? apiKey
                    : hasAPIKey
                        ? String(repeating: "•", count: 24)
                        : "未设置",
                isSensitive: true,
                isRevealed: isAPIKeyVisible,
                onToggleVisibility: onToggleKeyVisibility,
                onCopy: onCopyKey
            )
            Divider()
                .padding(.horizontal, 16)
            environmentRow
            Divider()
                .padding(.horizontal, 16)
            notesRow
        }
    }

    private func credentialRow(
        title: String,
        value: String,
        isSensitive: Bool = false,
        isRevealed: Bool = false,
        onToggleVisibility: (() -> Void)? = nil,
        onCopy: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.body.weight(.medium))
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(value == "未设置" ? Color.secondary : Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(
                    minWidth: 0,
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .clipped()
                .layoutPriority(-1)
            HStack(spacing: 12) {
                if isSensitive, let onToggleVisibility {
                    Button(action: onToggleVisibility) {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!hasAPIKey)
                    .help(isRevealed ? "隐藏API Key" : "显示API Key")
                    .accessibilityLabel(isRevealed ? "隐藏API Key" : "显示API Key")
                }
                Button("复制", systemImage: "doc.on.doc", action: onCopy)
                    .buttonStyle(.borderless)
                    .disabled(isSensitive && !hasAPIKey)
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
    }

    private var environmentRow: some View {
        HStack(spacing: 16) {
            Text("环境变量")
                .font(.body.weight(.medium))
                .frame(width: 110, alignment: .leading)
            Text("Shell格式，可直接粘贴到终端或应用配置中")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 12)
            Button("复制", systemImage: "doc.on.doc", action: onCopyEnvironment)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
    }

    private var notesRow: some View {
        let notes = profile.notes.trimmingCharacters(in: .whitespacesAndNewlines)

        return HStack(alignment: .top, spacing: 16) {
            Text("备注")
                .font(.body.weight(.medium))
                .frame(width: 110, alignment: .leading)
            Text(notes.isEmpty ? "未填写" : notes)
                .foregroundStyle(notes.isEmpty ? Color.secondary : Color.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button("复制", systemImage: "doc.on.doc", action: onCopyNotes)
                .buttonStyle(.borderless)
                .disabled(notes.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(minHeight: 58, alignment: .top)
    }
}

private struct CopyToast: View {
    let message: String

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                toastLabel
                    .glassEffect()
            } else {
                toastLabel
                    .background(.regularMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(.primary.opacity(0.08))
                    }
            }
        }
            .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
            .allowsHitTesting(false)
    }

    private var toastLabel: some View {
        Label(message, systemImage: "checkmark")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
    }
}

private func environmentExample(for profile: APIProfile, apiKey: String) -> String {
    switch profile.apiFormat {
    case .openAI, .openAIResponses:
        return "export OPENAI_BASE_URL=\(shellQuoted(profile.baseURL))\nexport OPENAI_API_KEY=\(shellQuoted(apiKey))"
    case .anthropic:
        return "export ANTHROPIC_BASE_URL=\(shellQuoted(profile.baseURL))\nexport ANTHROPIC_API_KEY=\(shellQuoted(apiKey))"
    }
}

private func shellQuoted(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
}
