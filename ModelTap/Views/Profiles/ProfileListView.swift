import SwiftData
import SwiftUI

struct ProfileListView: View {
    @Query(sort: \APIProfile.updatedAt, order: .reverse) private var profiles: [APIProfile]
    @Query(sort: \ProfileFolder.name) private var folders: [ProfileFolder]
    @Binding var selectedProfile: APIProfile?
    @Binding var searchText: String
    let onNew: () -> Void
    let onEdit: (APIProfile) -> Void
    let onDelete: (APIProfile) -> Void
    let onDuplicate: (APIProfile) -> Void
    let onCopyURL: (APIProfile) -> Void
    let onCopyKey: (APIProfile) -> Void
    let onCopyEnvironment: (APIProfile) -> Void
    let onCreateFolder: (String) -> Void
    let onRenameFolder: (ProfileFolder, String) -> Void
    let onDeleteFolder: (ProfileFolder) -> Void
    let onMoveProfile: (APIProfile, ProfileFolder?) -> Void
    let onImportBackup: () -> Void
    let onExportBackup: () -> Void

    @State private var collapsedFolderIDs: Set<UUID> = []
    @State private var isUnfiledCollapsed = false
    @State private var folderEditor: FolderEditorState?
    @State private var pendingDeleteFolder: ProfileFolder?

    private var visibleFolders: [ProfileFolder] {
        folders.filter {
            searchText.isEmpty
                || $0.name.localizedCaseInsensitiveContains(searchText)
                || !displayedProfiles(in: $0).isEmpty
        }
    }

    private var unfiledProfiles: [APIProfile] {
        let folderIDs = Set(folders.map(\.id))
        let values = profiles.filter {
            guard let folderID = $0.folderID else { return true }
            return !folderIDs.contains(folderID)
        }
        return filter(values)
    }

    var body: some View {
        VStack(spacing: 0) {
            backupActions
            Divider()

            List(selection: $selectedProfile) {
                ForEach(visibleFolders) { folder in
                    DisclosureGroup(isExpanded: expansionBinding(for: folder)) {
                        ForEach(displayedProfiles(in: folder)) { profile in
                            profileRow(profile)
                        }
                        .onDelete { offsets in
                            let values = displayedProfiles(in: folder)
                            offsets.map { values[$0] }.forEach(onDelete)
                        }
                    } label: {
                        folderLabel(folder)
                    }
                }

                if searchText.isEmpty || !unfiledProfiles.isEmpty {
                    DisclosureGroup(isExpanded: unfiledExpansionBinding) {
                        ForEach(unfiledProfiles) { profile in
                            profileRow(profile)
                        }
                        .onDelete { offsets in
                            offsets.map { unfiledProfiles[$0] }.forEach(onDelete)
                        }
                    } label: {
                        Label("未分类", systemImage: "tray")
                            .font(.headline)
                            .dropDestination(for: String.self) { values, _ in
                                moveProfiles(values, to: nil)
                            }
                    }
                }
            }
            .overlay {
                if profiles.isEmpty && folders.isEmpty {
                    ContentUnavailableView(
                        "还没有配置",
                        systemImage: "externaldrive.badge.plus",
                        description: Text("添加文件夹或LLM API配置开始使用。")
                    )
                }
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "搜索配置或文件夹")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("新增配置", systemImage: "plus", action: onNew)
                    .help("Command-N")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("新建文件夹", systemImage: "folder.badge.plus") {
                    folderEditor = FolderEditorState(folder: nil, name: "")
                }
            }
        }
        .sheet(item: $folderEditor) { state in
            FolderEditorView(
                title: state.folder == nil ? "新建文件夹" : "重命名文件夹",
                initialName: state.name,
                onCancel: { folderEditor = nil },
                onSave: { name in
                    if let folder = state.folder {
                        onRenameFolder(folder, name)
                    } else {
                        onCreateFolder(name)
                    }
                    folderEditor = nil
                }
            )
        }
        .confirmationDialog(
            "删除文件夹“\(pendingDeleteFolder?.name ?? "")”？",
            isPresented: Binding(
                get: { pendingDeleteFolder != nil },
                set: { if !$0 { pendingDeleteFolder = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除文件夹", role: .destructive) {
                if let folder = pendingDeleteFolder {
                    onDeleteFolder(folder)
                }
                pendingDeleteFolder = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteFolder = nil
            }
        } message: {
            Text("文件夹中的配置将移到“未分类”，不会被删除。")
        }
    }

    private var backupActions: some View {
        HStack(spacing: 8) {
            Button("导入", systemImage: "square.and.arrow.down", action: onImportBackup)
                .help("导入Markdown全量备份")
            Button("导出", systemImage: "square.and.arrow.up", action: onExportBackup)
                .help("导出Markdown全量备份")
            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func displayedProfiles(in folder: ProfileFolder) -> [APIProfile] {
        let values = profiles.filter { $0.folderID == folder.id }
        if searchText.isEmpty || folder.name.localizedCaseInsensitiveContains(searchText) {
            return values
        }
        return filter(values)
    }

    private func filter(_ values: [APIProfile]) -> [APIProfile] {
        guard !searchText.isEmpty else { return values }
        return values.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.baseURL.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func expansionBinding(for folder: ProfileFolder) -> Binding<Bool> {
        Binding(
            get: {
                searchText.isEmpty ? !collapsedFolderIDs.contains(folder.id) : true
            },
            set: { isExpanded in
                guard searchText.isEmpty else { return }
                if isExpanded {
                    collapsedFolderIDs.remove(folder.id)
                } else {
                    collapsedFolderIDs.insert(folder.id)
                }
            }
        )
    }

    private var unfiledExpansionBinding: Binding<Bool> {
        Binding(
            get: { searchText.isEmpty ? !isUnfiledCollapsed : true },
            set: { if searchText.isEmpty { isUnfiledCollapsed = !$0 } }
        )
    }

    private func folderLabel(_ folder: ProfileFolder) -> some View {
        Label(folder.name, systemImage: "folder")
            .font(.headline)
            .dropDestination(for: String.self) { values, _ in
                moveProfiles(values, to: folder)
            }
            .contextMenu {
                Button("重命名", systemImage: "pencil") {
                    folderEditor = FolderEditorState(folder: folder, name: folder.name)
                }
                Button("删除文件夹", systemImage: "trash", role: .destructive) {
                    pendingDeleteFolder = folder
                }
            }
    }

    private func profileRow(_ profile: APIProfile) -> some View {
        ProfileRow(profile: profile)
            .tag(profile)
            .draggable(profile.id.uuidString)
            .contextMenu { profileMenu(profile) }
    }

    private func moveProfiles(_ values: [String], to folder: ProfileFolder?) -> Bool {
        let ids = Set(values.compactMap { UUID(uuidString: $0) })
        let movingProfiles = profiles.filter { ids.contains($0.id) }
        movingProfiles.forEach { onMoveProfile($0, folder) }
        return !movingProfiles.isEmpty
    }

    @ViewBuilder
    private func profileMenu(_ profile: APIProfile) -> some View {
        Button("编辑", systemImage: "pencil") { onEdit(profile) }
        Button("复制配置", systemImage: "plus.square.on.square") { onDuplicate(profile) }
        Menu("移动到文件夹", systemImage: "folder") {
            Button("未分类", systemImage: "tray") { onMoveProfile(profile, nil) }
            if !folders.isEmpty {
                Divider()
                ForEach(folders) { folder in
                    Button(folder.name, systemImage: "folder") {
                        onMoveProfile(profile, folder)
                    }
                    .disabled(profile.folderID == folder.id)
                }
            }
        }
        Divider()
        Button("复制Base URL", systemImage: "link") { onCopyURL(profile) }
        Button("复制API Key", systemImage: "key") { onCopyKey(profile) }
        Button("复制环境变量", systemImage: "terminal") { onCopyEnvironment(profile) }
        Divider()
        Button("删除", systemImage: "trash", role: .destructive) { onDelete(profile) }
    }
}

private struct FolderEditorState: Identifiable {
    let id = UUID()
    let folder: ProfileFolder?
    let name: String
}

private struct FolderEditorView: View {
    let title: String
    let onCancel: () -> Void
    let onSave: (String) -> Void
    @State private var name: String

    init(
        title: String,
        initialName: String,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))
            TextField("文件夹名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { save() }
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func save() {
        onSave(name)
    }
}

private struct ProfileRow: View {
    let profile: APIProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(profile.name).font(.headline)
            Text(profile.baseURL)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}
