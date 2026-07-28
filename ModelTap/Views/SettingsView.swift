import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("关于 ModelTap") {
                LabeledContent("中文名", value: "模探")
                LabeledContent("版本", value: "第一阶段")
                Text("一键发现、验证和管理 LLM API。")
                    .foregroundStyle(.secondary)
            }
            Section("安全") { Label("API Key 使用 macOS Keychain 保存。", systemImage: "lock.shield") }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 260)
        .padding()
    }
}
