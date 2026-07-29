import SwiftUI

struct ModelListView: View {
    @ObservedObject var viewModel: ContentViewModel
    let onManualInput: () -> Void

    var body: some View {
        content
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder private var content: some View {
        if viewModel.models.isEmpty {
            emptyContent
        } else {
            VStack(spacing: 0) {
                if viewModel.loadState == .loading {
                    ProgressView("正在查询模型…")
                        .controlSize(.small)
                        .padding(.vertical, 8)
                } else if case .failed(let message) = viewModel.loadState {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.08))
                }

                modelRows
            }
        }
    }

    @ViewBuilder private var emptyContent: some View {
        switch viewModel.loadState {
        case .idle:
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity, minHeight: 220)
                .accessibilityLabel("尚未查询模型")
        case .loaded:
            ContentUnavailableView {
                Label("尚无模型", systemImage: "list.bullet.rectangle")
            } description: {
                Text("可以查询服务端模型列表，也可以手动添加模型ID。")
            } actions: {
                Button("手动输入", systemImage: "plus") {
                    onManualInput()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading:
            ProgressView("正在查询模型…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("查询失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("手动输入", systemImage: "plus") {
                    onManualInput()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var modelRows: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.models) { model in
                let isManual = viewModel.isManualModel(model.id)
                ModelRowView(
                    model: model,
                    isTesting: viewModel.testingModelIDs.contains(model.id),
                    isManual: isManual,
                    onCopy: {
                        Clipboard.copy(model.id)
                        viewModel.showToast("模型ID已复制")
                    },
                    onTest: {
                        viewModel.selectedModelID = model.id
                        viewModel.test(modelID: model.id)
                    }
                )
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    viewModel.selectedModelID == model.id
                        ? Color.accentColor.opacity(0.08)
                        : .clear
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectedModelID = model.id
                    viewModel.selectedSummary = model.latestTest
                }
                .contextMenu {
                    if isManual {
                        Button(
                            "删除手动模型",
                            systemImage: "trash",
                            role: .destructive
                        ) {
                            viewModel.removeManualModel(id: model.id)
                        }
                    }
                }
            }
        }
    }

}
