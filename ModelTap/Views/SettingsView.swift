import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("关于 ModelTap")
                    .font(.title3.weight(.semibold))

                VStack(spacing: 0) {
                    settingRow("中文名", value: "模探")
                    Divider()
                    settingRow("版本", value: "第一阶段")
                    Divider()
                    Text("一键发现、验证和管理 LLM API。")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
                .padding(.horizontal, 20)
                .background(.quaternary.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("安全")
                    .font(.title3.weight(.semibold))

                Label("API Key 使用 macOS Keychain 保存。", systemImage: "lock.shield")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(.quaternary.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(24)
        .frame(width: 420, alignment: .topLeading)
    }

    private func settingRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }
}
