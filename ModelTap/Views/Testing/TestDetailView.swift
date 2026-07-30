import SwiftUI

struct TestDetailView: View {
    let summary: ModelTestSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 20) {
                metric("状态码", summary.statusCode.map(String.init) ?? "—")
                metric("接口协议", summary.protocolName?.rawValue ?? "—")
                metric("耗时", Formatters.duration(summary.duration))
                if let usage = Formatters.tokens(summary.tokenUsage) {
                    metric("Token用量", usage)
                }
            }

            if let error = summary.errorSummary {
                Divider()
                Text(error)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
        }
        .font(.caption)
    }
}
