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
                        LabeledContent("测试时间", value: summary.testedAt.modelTapShort)
                        if let usage = Formatters.tokens(summary.tokenUsage) { LabeledContent("Token 用量", value: usage) }
                        if let output = summary.output {
                            Divider()
                            Text("模型输出").font(.subheadline.weight(.semibold))
                            Text(output).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let error = summary.errorSummary {
                            Divider()
                            Text(error).foregroundStyle(.red).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding()
                }
            } else {
                ContentUnavailableView("暂无测试详情", systemImage: "checkmark.bubble", description: Text("测试模型后将在这里显示响应和错误信息。"))
            }
        }
        .frame(minWidth: 270, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
