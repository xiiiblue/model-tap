import SwiftUI
import SwiftData

struct ProfileListView: View {
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \APIProfile.updatedAt, order: .reverse) private var profiles: [APIProfile]
    @Binding var selectedProfile: APIProfile?
    @Binding var searchText: String
    let onNew: () -> Void
    let onEdit: (APIProfile) -> Void
    let onDelete: (APIProfile) -> Void
    let onDuplicate: (APIProfile) -> Void
    let onCopyURL: (APIProfile) -> Void
    let onCopyKey: (APIProfile) -> Void
    let onCopyEnvironment: (APIProfile) -> Void

    private var filteredProfiles: [APIProfile] {
        guard !searchText.isEmpty else { return profiles }
        return profiles.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.baseURL.localizedCaseInsensitiveContains(searchText)
                || ($0.category?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var profileGroups: [ProfileGroup] {
        Dictionary(grouping: filteredProfiles, by: categoryName)
            .map { ProfileGroup(name: $0.key, profiles: $0.value) }
            .sorted {
                if $0.name == "未分类" { return false }
                if $1.name == "未分类" { return true }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    var body: some View {
        List(selection: $selectedProfile) {
            ForEach(profileGroups) { group in
                Section(group.name) {
                    ForEach(group.profiles) { profile in
                        ProfileRow(profile: profile)
                            .tag(profile)
                            .contextMenu { profileMenu(profile) }
                    }
                    .onDelete { offsets in
                        offsets.map { group.profiles[$0] }.forEach(onDelete)
                    }
                }
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "搜索配置")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("新增配置", systemImage: "plus", action: onNew).help("Command-N") }
            ToolbarItem(placement: .automatic) { Button("设置", systemImage: "gear") { openSettings() }.help("打开设置") }
        }
        .overlay { if profiles.isEmpty { ContentUnavailableView("还没有配置", systemImage: "externaldrive.badge.plus", description: Text("添加一个 LLM API 配置开始使用。")) } }
    }

    private func categoryName(_ profile: APIProfile) -> String {
        let value = profile.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "未分类" : value
    }

    @ViewBuilder private func profileMenu(_ profile: APIProfile) -> some View {
        Button("编辑", systemImage: "pencil") { onEdit(profile) }
        Button("复制配置", systemImage: "plus.square.on.square") { onDuplicate(profile) }
        Divider()
        Button("复制 Base URL", systemImage: "link") { onCopyURL(profile) }
        Button("复制 API Key", systemImage: "key") { onCopyKey(profile) }
        Button("复制环境变量", systemImage: "terminal") { onCopyEnvironment(profile) }
        Divider()
        Button("删除", systemImage: "trash", role: .destructive) { onDelete(profile) }
    }
}

private struct ProfileGroup: Identifiable {
    let name: String
    let profiles: [APIProfile]
    var id: String { name }
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
