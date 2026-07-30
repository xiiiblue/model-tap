import SwiftUI

struct ModelRowView: View {
    let model: ModelInfo
    let isTesting: Bool
    let isManual: Bool
    let onCopy: () -> Void
    let onTest: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 22)
            Text(model.id)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isManual {
                Text("手动")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .fixedSize()
            }
            trailingActions
        }
        .padding(.vertical, 5)
    }

    private var trailingActions: some View {
        HStack(spacing: 12) {
            if let summary = model.latestTest {
                Text(Formatters.duration(summary.duration))
                    .foregroundStyle(.secondary)
                    .frame(width: 75, alignment: .trailing)
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
                    .frame(width: 75, alignment: .trailing)
            }
            Button("复制模型ID", systemImage: "doc.on.doc", action: onCopy)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("复制模型ID")
            Button("测试", systemImage: "play", action: onTest)
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderless)
                .disabled(isTesting)
                .fixedSize()
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
    }

    @ViewBuilder private var statusIcon: some View {
        if isTesting {
            LoadingStatusIcon()
                .help("测试中")
        } else if let summary = model.latestTest {
            Image(systemName: summary.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(summary.success ? .green : .red)
                .help(summary.success ? "测试成功" : (summary.errorSummary ?? "测试失败"))
        } else {
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary).help("未测试")
        }
    }
}

private struct LoadingStatusIcon: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .frame(width: 15, height: 15)
            .accessibilityLabel("测试中")
    }
}
