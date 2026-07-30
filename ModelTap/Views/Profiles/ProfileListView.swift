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
    let onApplySort: (SidebarSortSnapshot) -> Bool

    @State private var collapsedFolderIDs: Set<UUID> = []
    @State private var isUnfiledCollapsed = false
    @State private var folderEditor: FolderEditorState?
    @State private var pendingDeleteFolder: ProfileFolder?
    @State private var pendingDeleteProfiles: [APIProfile] = []
    @State private var isSorting = false
    @State private var sortSections: [SidebarSortSection] = []
    @State private var sortDropTarget: SidebarSortDropTarget?

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
        Group {
            if isSorting {
                sortingList
            } else {
                standardList
            }
        }
        .toolbar {
            if isSorting {
                ToolbarItem(placement: .primaryAction) {
                    if #available(macOS 26.0, *) {
                        Button("取消", systemImage: "xmark") {
                            cancelSorting()
                        }
                        .buttonStyle(.glass)
                    } else {
                        Button("取消", systemImage: "xmark") {
                            cancelSorting()
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if #available(macOS 26.0, *) {
                        Button("完成", systemImage: "checkmark") {
                            finishSorting()
                        }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button("完成", systemImage: "checkmark") {
                            finishSorting()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button("新增配置", systemImage: "plus", action: onNew)
                        .help("Command-N")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("新建文件夹", systemImage: "folder.badge.plus") {
                        folderEditor = FolderEditorState(folder: nil, name: "")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("排序", systemImage: "arrow.up.arrow.down") {
                        startSorting()
                    }
                    .disabled(profiles.isEmpty && folders.count < 2)
                }
            }
        }
        .overlay {
            if !isSorting && profiles.isEmpty && folders.isEmpty {
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

    private var standardList: some View {
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
    }

    private var sortingList: some View {
        List {
            ForEach(sortSections) { section in
                sortingSectionHeader(section)

                ForEach(section.profileIDs, id: \.self) { profileID in
                    if let profile = profiles.first(where: {
                        $0.id == profileID
                    }) {
                        sortingProfileRow(profile, in: section.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .listRowSeparator(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            sortingHint
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
        }
        .onExitCommand {
            cancelSorting()
        }
    }

    @ViewBuilder
    private var sortingHint: some View {
        if #available(macOS 26.0, *) {
            sortingHintLabel
                .glassEffect(
                    .regular,
                    in: .rect(cornerRadius: 12)
                )
        } else {
            sortingHintLabel
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                    .strokeBorder(Color.primary.opacity(0.08))
                }
        }
    }

    private var sortingHintLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.arrow.down")
            Text("拖动整行调整顺序或移动配置")
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func sortingSectionHeader(
        _ section: SidebarSortSection
    ) -> some View {
        if let folderID = section.folderID {
            SidebarSortingFolderRow(title: section.title)
                .padding(.horizontal, 8)
                .background {
                    sortingDropBackground(for: .section(section.id))
                }
                .listRowInsets(
                    EdgeInsets(top: 7, leading: 10, bottom: 2, trailing: 8)
                )
                .listRowBackground(Color.clear)
                .draggable(
                    SidebarSortDragItem.folder(folderID).encoded
                ) {
                    SidebarSortDragPreview(
                        systemImage: "folder",
                        title: section.title
                    )
                }
                .dropDestination(for: String.self) { values, location in
                    performSortDrop(
                        values,
                        on: section.id,
                        location: location
                    )
                } isTargeted: { isTargeted in
                    updateSortDropTarget(
                        .section(section.id),
                        isTargeted: isTargeted
                    )
                }
        } else {
            SidebarSortingFolderRow(title: section.title)
                .padding(.horizontal, 8)
                .background {
                    sortingDropBackground(for: .section(section.id))
                }
                .listRowInsets(
                    EdgeInsets(top: 7, leading: 10, bottom: 2, trailing: 8)
                )
                .listRowBackground(Color.clear)
                .dropDestination(for: String.self) { values, location in
                    performSortDrop(
                        values,
                        on: section.id,
                        location: location
                    )
                } isTargeted: { isTargeted in
                    updateSortDropTarget(
                        .section(section.id),
                        isTargeted: isTargeted
                    )
                }
        }
    }

    private func sortingProfileRow(
        _ profile: APIProfile,
        in sectionID: SidebarSortGroupID
    ) -> some View {
        SidebarSortingProfileRow(title: profile.name)
            .padding(.horizontal, 8)
            .background {
                sortingDropBackground(for: .profile(profile.id))
            }
            .listRowInsets(
                EdgeInsets(top: 1, leading: 30, bottom: 1, trailing: 8)
            )
            .listRowBackground(Color.clear)
            .draggable(
                SidebarSortDragItem.profile(profile.id).encoded
            ) {
                SidebarSortDragPreview(
                    systemImage: "link",
                    title: profile.name
                )
            }
            .dropDestination(for: String.self) { values, location in
                performSortDrop(
                    values,
                    relativeTo: profile.id,
                    in: sectionID,
                    location: location
                )
            } isTargeted: { isTargeted in
                updateSortDropTarget(
                    .profile(profile.id),
                    isTargeted: isTargeted
                )
            }
    }

    private func sortingDropBackground(
        for target: SidebarSortDropTarget
    ) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.accentColor.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
            }
            .opacity(sortDropTarget == target ? 1 : 0)
            .animation(.easeInOut(duration: 0.12), value: sortDropTarget)
    }

    private func startSorting() {
        searchText = ""
        let folderIDs = Set(folders.map(\.id))
        let sections = orderedFolders.map { folder in
            SidebarSortSection(
                id: .folder(folder.id),
                title: folder.name,
                profileIDs: orderedProfiles
                    .filter { $0.folderID == folder.id }
                    .map(\.id)
            )
        }
        let unfiled = SidebarSortSection(
            id: .unfiled,
            title: "未分类",
            profileIDs: orderedProfiles
                .filter {
                    guard let folderID = $0.folderID else { return true }
                    return !folderIDs.contains(folderID)
                }
                .map(\.id)
        )
        sortSections = sections + [unfiled]
        sortDropTarget = nil
        isSorting = true
    }

    private func cancelSorting() {
        sortDropTarget = nil
        sortSections = []
        isSorting = false
    }

    private func finishSorting() {
        let snapshot = SidebarSortSnapshot(
            folderIDs: sortSections.compactMap(\.folderID),
            groups: sortSections.map {
                SidebarProfileSortGroup(
                    folderID: $0.folderID,
                    profileIDs: $0.profileIDs
                )
            }
        )
        guard onApplySort(snapshot) else { return }
        cancelSorting()
    }

    private func updateSortDropTarget(
        _ target: SidebarSortDropTarget,
        isTargeted: Bool
    ) {
        if isTargeted {
            sortDropTarget = target
        } else if sortDropTarget == target {
            sortDropTarget = nil
        }
    }

    private func performSortDrop(
        _ values: [String],
        on sectionID: SidebarSortGroupID,
        location: CGPoint
    ) -> Bool {
        guard let value = values.first,
              let item = SidebarSortDragItem(encoded: value) else {
            return false
        }
        sortDropTarget = nil
        switch item {
        case .folder(let folderID):
            guard case .folder(let targetFolderID) = sectionID else {
                return false
            }
            return moveSortFolder(
                folderID,
                relativeTo: targetFolderID,
                placeAfter: location.y > 14
            )
        case .profile(let profileID):
            return moveSortProfile(profileID, to: sectionID)
        }
    }

    private func performSortDrop(
        _ values: [String],
        relativeTo targetProfileID: UUID,
        in sectionID: SidebarSortGroupID,
        location: CGPoint
    ) -> Bool {
        guard let value = values.first,
              let item = SidebarSortDragItem(encoded: value),
              case .profile(let profileID) = item else {
            return false
        }
        sortDropTarget = nil
        return moveSortProfile(
            profileID,
            relativeTo: targetProfileID,
            in: sectionID,
            placeAfter: location.y > 18
        )
    }

    private func moveSortFolder(
        _ folderID: UUID,
        relativeTo targetFolderID: UUID,
        placeAfter: Bool
    ) -> Bool {
        guard folderID != targetFolderID,
              let sourceIndex = sortSections.firstIndex(where: {
                  $0.folderID == folderID
              }) else {
            return false
        }
        var updated = sortSections
        let movingSection = updated.remove(at: sourceIndex)
        guard let targetIndex = updated.firstIndex(where: {
            $0.folderID == targetFolderID
        }) else {
            return false
        }
        updated.insert(
            movingSection,
            at: placeAfter ? targetIndex + 1 : targetIndex
        )
        sortSections = updated
        return true
    }

    private func moveSortProfile(
        _ profileID: UUID,
        to sectionID: SidebarSortGroupID
    ) -> Bool {
        var updated = sortSections
        guard updated.contains(where: {
            $0.profileIDs.contains(profileID)
        }), let targetIndex = updated.firstIndex(where: {
            $0.id == sectionID
        }) else {
            return false
        }
        for index in updated.indices {
            updated[index].profileIDs.removeAll { $0 == profileID }
        }
        updated[targetIndex].profileIDs.append(profileID)
        sortSections = updated
        return true
    }

    private func moveSortProfile(
        _ profileID: UUID,
        relativeTo targetProfileID: UUID,
        in sectionID: SidebarSortGroupID,
        placeAfter: Bool
    ) -> Bool {
        guard profileID != targetProfileID else { return false }
        var updated = sortSections
        guard updated.contains(where: {
            $0.profileIDs.contains(profileID)
        }) else {
            return false
        }
        for index in updated.indices {
            updated[index].profileIDs.removeAll { $0 == profileID }
        }
        guard let sectionIndex = updated.firstIndex(where: {
            $0.id == sectionID
        }), let targetIndex = updated[sectionIndex].profileIDs.firstIndex(
            of: targetProfileID
        ) else {
            return false
        }
        updated[sectionIndex].profileIDs.insert(
            profileID,
            at: placeAfter ? targetIndex + 1 : targetIndex
        )
        sortSections = updated
        return true
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
    }

    private func profileRow(_ profile: APIProfile) -> some View {
        ProfileRow(profile: profile)
            .tag(profile)
            .listRowInsets(EdgeInsets(top: 1, leading: 30, bottom: 1, trailing: 8))
            .contextMenu { profileMenu(profile) }
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

private enum SidebarSortGroupID: Hashable {
    case folder(UUID)
    case unfiled
}

private struct SidebarSortSection: Identifiable {
    let id: SidebarSortGroupID
    let title: String
    var profileIDs: [UUID]

    var folderID: UUID? {
        guard case .folder(let folderID) = self.id else { return nil }
        return folderID
    }
}

private enum SidebarSortDragItem {
    case folder(UUID)
    case profile(UUID)

    init?(encoded: String) {
        let components = encoded.split(
            separator: ":",
            maxSplits: 1
        )
        guard components.count == 2,
              let id = UUID(uuidString: String(components[1])) else {
            return nil
        }
        switch components[0] {
        case "folder":
            self = .folder(id)
        case "profile":
            self = .profile(id)
        default:
            return nil
        }
    }

    var encoded: String {
        switch self {
        case .folder(let id):
            "folder:\(id.uuidString)"
        case .profile(let id):
            "profile:\(id.uuidString)"
        }
    }
}

private enum SidebarSortDropTarget: Equatable {
    case section(SidebarSortGroupID)
    case profile(UUID)
}

private struct SidebarSortingFolderRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "folder")
                .font(.body)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SidebarSortingProfileRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
            Text(title)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SidebarSortDragPreview: View {
    let systemImage: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
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
