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

    private var filteredProfiles: [APIProfile] { searchText.isEmpty ? profiles : profiles.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.baseURL.localizedCaseInsensitiveContains(searchText) } }

    var body: some View {
        List(selection: $selectedProfile) {
            ForEach(filteredProfiles) { profile in
                ProfileRow(profile: profile)
                    .tag(profile)
                    .contextMenu { profileMenu(profile) }
            }
            .onDelete { offsets in offsets.map { filteredProfiles[$0] }.forEach(onDelete) }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "搜索配置")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("新增配置", systemImage: "plus", action: onNew).help("Command-N") }
            ToolbarItem(placement: .automatic) { Button("设置", systemImage: "gear") { openSettings() }.help("打开设置") }
        }
        .overlay { if profiles.isEmpty { ContentUnavailableView("还没有配置", systemImage: "externaldrive.badge.plus", description: Text("添加一个 LLM API 配置开始使用。")) } }
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

private struct ProfileRow: View {
    let profile: APIProfile
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(profile.name).font(.headline)
                Spacer()
                Label(profile.testStatus.title, systemImage: profile.testStatus == .success ? "checkmark.circle.fill" : profile.testStatus == .failure ? "xmark.circle.fill" : "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(profile.testStatus == .success ? .green : profile.testStatus == .failure ? .red : .secondary)
            }
            Text(profile.baseURL)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}
