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
    let onReorderProfile: (APIProfile, APIProfile, Bool) -> Void
    let onReorderFolder: (ProfileFolder, ProfileFolder, Bool) -> Void

    @State private var collapsedFolderIDs: Set<UUID> = []
    @State private var isUnfiledCollapsed = false
    @State private var folderEditor: FolderEditorState?
    @State private var pendingDeleteFolder: ProfileFolder?
    @State private var pendingDeleteProfiles: [APIProfile] = []

    private var visibleFolders: [ProfileFolder] {
        orderedFolders.filter {
            searchText.isEmpty
                || $0.name.localizedCaseInsensitiveContains(searchText)
                || !displayedProfiles(in: $0).isEmpty
        }
    }

    private var unfiledProfiles: [APIProfile] {
        let folderIDs = Set(folders.map(\.id))
        let values = orderedProfiles.filter {
            guard let folderID = $0.folderID else { return true }
            return !folderIDs.contains(folderID)
        }
        return filter(values)
    }

    var body: some View {
        List(selection: $selectedProfile) {
            ForEach(visibleFolders) { folder in
                folderRow(folder)
                if expansionBinding(for: folder).wrappedValue {
                    ForEach(displayedProfiles(in: folder)) { profile in
                        profileRow(profile)
                    }
                    .onDelete { offsets in
                        let values = displayedProfiles(in: folder)
                        pendingDeleteProfiles = offsets.map { values[$0] }
                    }
                }
            }

            if searchText.isEmpty || !unfiledProfiles.isEmpty {
                unfiledFolderRow
                if unfiledExpansionBinding.wrappedValue {
                    ForEach(unfiledProfiles) { profile in
                        profileRow(profile)
                    }
                    .onDelete { offsets in
                        pendingDeleteProfiles = offsets.map {
                            unfiledProfiles[$0]
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .listRowSeparator(.hidden)
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
        .overlay {
            if profiles.isEmpty && folders.isEmpty {
                ContentUnavailableView(
                    "还没有配置",
                    systemImage: "externaldrive.badge.plus",
                    description: Text("添加文件夹或LLM API配置开始使用。")
                )
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
        .confirmationDialog(
            profileDeletionTitle,
            isPresented: Binding(
                get: { !pendingDeleteProfiles.isEmpty },
                set: { if !$0 { pendingDeleteProfiles = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除配置", role: .destructive) {
                let profiles = pendingDeleteProfiles
                pendingDeleteProfiles = []
                profiles.forEach(onDelete)
            }
            Button("取消", role: .cancel) {
                pendingDeleteProfiles = []
            }
        } message: {
            Text("配置、API Key和相关测试记录将被删除，此操作无法撤销。")
        }
    }

    private func displayedProfiles(in folder: ProfileFolder) -> [APIProfile] {
        let values = orderedProfiles.filter { $0.folderID == folder.id }
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

    private var profileDeletionTitle: String {
        if pendingDeleteProfiles.count == 1,
           let profile = pendingDeleteProfiles.first {
            return "删除配置“\(profile.name)”？"
        }
        return "删除\(pendingDeleteProfiles.count)项配置？"
    }

    private var orderedFolders: [ProfileFolder] {
        folders.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var orderedProfiles: [APIProfile] {
        profiles.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
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

    private func folderRow(_ folder: ProfileFolder) -> some View {
        let expansion = expansionBinding(for: folder)
        return Button {
            expansion.wrappedValue.toggle()
        } label: {
            FolderRowLabel(
                title: folder.name,
                isExpanded: expansion.wrappedValue
            )
        }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 7, leading: 10, bottom: 2, trailing: 8))
            .listRowBackground(Color.clear)
            .draggable(SidebarDragItem.folder(folder.id).encoded)
            .dropDestination(for: String.self) { values, location in
                handleDrop(
                    values,
                    on: folder,
                    placeAfter: location.y > 14
                )
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

    private var unfiledFolderRow: some View {
        Button {
            unfiledExpansionBinding.wrappedValue.toggle()
        } label: {
            FolderRowLabel(
                title: "未分类",
                isExpanded: unfiledExpansionBinding.wrappedValue
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 7, leading: 10, bottom: 2, trailing: 8))
        .listRowBackground(Color.clear)
        .dropDestination(for: String.self) { values, _ in
            moveProfiles(values, to: nil)
        }
    }

    private func profileRow(_ profile: APIProfile) -> some View {
        ProfileRow(profile: profile)
            .tag(profile)
            .listRowInsets(EdgeInsets(top: 1, leading: 30, bottom: 1, trailing: 8))
            .draggable(SidebarDragItem.profile(profile.id).encoded)
            .dropDestination(for: String.self) { values, location in
                reorderProfiles(
                    values,
                    relativeTo: profile,
                    placeAfter: location.y > 21
                )
            }
            .contextMenu { profileMenu(profile) }
    }

    private func moveProfiles(_ values: [String], to folder: ProfileFolder?) -> Bool {
        let ids: Set<UUID> = Set(values.compactMap { value -> UUID? in
            guard let item = SidebarDragItem(encoded: value),
                  case .profile(let id) = item else {
                return nil
            }
            return id
        })
        let movingProfiles = profiles.filter { ids.contains($0.id) }
        movingProfiles.forEach { onMoveProfile($0, folder) }
        return !movingProfiles.isEmpty
    }

    private func reorderProfiles(
        _ values: [String],
        relativeTo target: APIProfile,
        placeAfter: Bool
    ) -> Bool {
        guard let movingID = values.compactMap({ value -> UUID? in
            guard let item = SidebarDragItem(encoded: value),
                  case .profile(let id) = item else {
                return nil
            }
            return id
        }).first,
        let movingProfile = profiles.first(where: { $0.id == movingID }) else {
            return false
        }
        onReorderProfile(movingProfile, target, placeAfter)
        return true
    }

    private func handleDrop(
        _ values: [String],
        on target: ProfileFolder,
        placeAfter: Bool
    ) -> Bool {
        if let movingID = values.compactMap({ value -> UUID? in
            guard let item = SidebarDragItem(encoded: value),
                  case .folder(let id) = item else {
                return nil
            }
            return id
        }).first,
        let movingFolder = folders.first(where: { $0.id == movingID }) {
            onReorderFolder(movingFolder, target, placeAfter)
            return true
        }
        return moveProfiles(values, to: target)
    }

    @ViewBuilder
    private func profileMenu(_ profile: APIProfile) -> some View {
        Button("编辑", systemImage: "pencil") { onEdit(profile) }
        Button("复制配置", systemImage: "plus.square.on.square") { onDuplicate(profile) }
        Menu("移动到文件夹", systemImage: "folder") {
            Button("未分类", systemImage: "folder") { onMoveProfile(profile, nil) }
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
        Button("删除", systemImage: "trash", role: .destructive) {
            pendingDeleteProfiles = [profile]
        }
    }
}

private enum SidebarDragItem {
    case profile(UUID)
    case folder(UUID)

    init?(encoded: String) {
        let parts = encoded.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else {
            return nil
        }
        switch parts[0] {
        case "profile": self = .profile(id)
        case "folder": self = .folder(id)
        default: return nil
        }
    }

    var encoded: String {
        switch self {
        case .profile(let id): "profile:\(id.uuidString)"
        case .folder(let id): "folder:\(id.uuidString)"
        }
    }
}

private struct FolderRowLabel: View {
    let title: String
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 10)
            Image(systemName: "folder")
                .font(.body)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .contentShape(Rectangle())
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
        Text(profile.name)
            .font(.body.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .contentShape(Rectangle())
    }
}
