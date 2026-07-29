import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)

            VStack(spacing: 6) {
                Text("ModelTap")
                    .font(.title2.weight(.semibold))
                Text("LLM API管理工具")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Text("集中管理API地址，查询可用模型并验证接口响应。支持OpenAI Chat Completions、Responses和Anthropic Messages格式。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(versionText)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(width: 440)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version.map { "版本\($0)" } ?? "ModelTap"
    }
}
