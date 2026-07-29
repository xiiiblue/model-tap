import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel: ContentViewModel
    @State private var isExporterPresented = false
    @State private var exportDocument = MarkdownBackupDocument(text: "")
    @State private var isImporterPresented = false
    @State private var pendingImport: ModelTapBackup?

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
                onMoveProfile: viewModel.move
            )
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            detailView
        }
        .navigationTitle("ModelTap")
        .frame(minWidth: 900, minHeight: 560)
        .toolbar {
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
        .sheet(item: $viewModel.editor) { _ in ProfileEditorView(editor: $viewModel.editor, onSave: viewModel.saveEditor) }
        .alert(item: $viewModel.notice) { notice in Alert(title: Text(notice.message)) }
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
        .onChange(of: viewModel.selectedProfile) { _, profile in if profile != nil { viewModel.models = []; viewModel.loadState = .idle } }
    }

    @ViewBuilder private var detailView: some View {
        if let profile = viewModel.selectedProfile {
            VStack(spacing: 0) {
                ProfileDetailHeader(profile: profile, viewModel: viewModel)
                Divider()
                if viewModel.isBatchTesting, let progress = viewModel.batchProgress {
                    ProgressView("正在测试模型（\(progress.completed)/\(progress.total)）", value: Double(progress.completed), total: Double(progress.total)).padding()
                }
                ModelListView(viewModel: viewModel)
                Divider()
                TestDetailView(summary: viewModel.selectedSummary)
                    .frame(height: 190, alignment: .topLeading)
            }
        } else {
            ContentUnavailableView("选择一个 API 配置", systemImage: "point.3.connected.trianglepath.dotted", description: Text("从左侧选择配置，或新建一个配置开始。"))
        }
    }

    private func copyURL(_ profile: APIProfile) { Clipboard.copy(profile.baseURL); viewModel.notice = RequestNotice(message: "Base URL 已复制") }
    private func copyKey(_ profile: APIProfile) { let key = try? viewModel.repository.apiKey(for: profile); Clipboard.copy(key ?? ""); viewModel.notice = RequestNotice(message: "API Key 已复制") }
    private func copyEnvironment(_ profile: APIProfile) { let key = (try? viewModel.repository.apiKey(for: profile)) ?? ""; Clipboard.copy(environmentExample(for: profile, apiKey: key)); viewModel.notice = RequestNotice(message: "环境变量示例已复制") }

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

private struct ProfileDetailHeader: View {
    let profile: APIProfile
    @ObservedObject var viewModel: ContentViewModel
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name).font(.title2.weight(.semibold))
                Text(profile.baseURL).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Text(profile.apiFormat.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label(profile.testStatus.title, systemImage: profile.testStatus == .success ? "checkmark.circle.fill" : profile.testStatus == .failure ? "xmark.circle.fill" : "questionmark.circle").foregroundStyle(profile.testStatus == .success ? .green : profile.testStatus == .failure ? .red : .secondary)
            Button("编辑", systemImage: "pencil") { viewModel.edit(profile) }
            Button("查询模型", systemImage: "arrow.clockwise", action: viewModel.discover).disabled(viewModel.loadState == .loading || viewModel.isBatchTesting)
            Button("测试全部", systemImage: "play.fill", action: viewModel.testAll).disabled(viewModel.models.isEmpty || viewModel.isBatchTesting)
            if viewModel.isBatchTesting { Button("取消", role: .cancel, action: viewModel.cancel) }
            Menu { Button("复制 Base URL") { Clipboard.copy(profile.baseURL) }; Button("复制 API Key") { if let key = try? viewModel.repository.apiKey(for: profile) { Clipboard.copy(key) } }; Button("复制环境变量") { let key = (try? viewModel.repository.apiKey(for: profile)) ?? ""; Clipboard.copy(environmentExample(for: profile, apiKey: key)) } } label: { Image(systemName: "ellipsis.circle") }
        }
        .padding()
    }
}

private func environmentExample(for profile: APIProfile, apiKey: String) -> String {
    switch profile.apiFormat {
    case .openAI, .openAIResponses:
        return "export OPENAI_BASE_URL=\"\(profile.baseURL)\"\nexport OPENAI_API_KEY=\"\(apiKey)\""
    case .anthropic:
        return "export ANTHROPIC_BASE_URL=\"\(profile.baseURL)\"\nexport ANTHROPIC_API_KEY=\"\(apiKey)\""
    }
}
