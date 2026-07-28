import SwiftUI

struct ModelRowView: View {
    let model: ModelInfo
    let onCopy: () -> Void
    let onTest: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 22)
            Text(model.id)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
            Spacer()
            if let summary = model.latestTest {
                Text(Formatters.duration(summary.duration)).foregroundStyle(.secondary).frame(width: 75, alignment: .trailing)
                Text(summary.testedAt.modelTapShort).foregroundStyle(.secondary).frame(width: 145, alignment: .trailing)
            } else {
                Text("—").foregroundStyle(.tertiary).frame(width: 220, alignment: .trailing)
            }
            Button("复制", systemImage: "doc.on.doc", action: onCopy).labelStyle(.iconOnly).help("复制模型 ID")
            Button("测试", systemImage: "play", action: onTest)
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder private var statusIcon: some View {
        if let summary = model.latestTest {
            Image(systemName: summary.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(summary.success ? .green : .red)
                .help(summary.success ? "测试成功" : (summary.errorSummary ?? "测试失败"))
        } else {
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary).help("未测试")
        }
    }
}
