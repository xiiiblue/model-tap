import SwiftUI

struct TestDetailView: View {
    let summary: ModelTestSummary?

    var body: some View {
        Group {
            if let summary {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(summary.success ? "测试成功" : "测试失败", systemImage: summary.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(summary.success ? .green : .red)
                            .font(.headline)
                        LabeledContent("状态码", value: summary.statusCode.map(String.init) ?? "—")
                        LabeledContent("接口协议", value: summary.protocolName?.rawValue ?? "—")
                        LabeledContent("耗时", value: Formatters.duration(summary.duration))
                        if let usage = Formatters.tokens(summary.tokenUsage) { LabeledContent("Token 用量", value: usage) }
                        if let error = summary.errorSummary {
                            Divider()
                            Text(error).foregroundStyle(.red).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding()
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("暂无测试详情", systemImage: "checkmark.bubble")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("测试模型后将在这里显示结果和错误信息。")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding()
            }
        }
        .frame(minWidth: 270, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
