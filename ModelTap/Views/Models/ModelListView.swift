import SwiftUI

struct ModelListView: View {
    @ObservedObject var viewModel: ContentViewModel
    let onManualInput: () -> Void

    var body: some View {
        content
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder private var content: some View {
        if viewModel.loadState == .loading {
            loadingContent
        } else if viewModel.models.isEmpty {
            emptyContent
        } else {
            VStack(spacing: 0) {
                if case .failed(let message) = viewModel.loadState {
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
                .font(.system(size: 72, weight: .light))
                .symbolRenderingMode(.hierarchical)
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
            loadingContent
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

    private var loadingContent: some View {
        ProgressView("正在查询模型…")
            .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var modelRows: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.models) { model in
                let isManual = viewModel.isManualModel(model.id)
                VStack(spacing: 0) {
                    ModelRowView(
                        model: model,
                        isTesting: viewModel.testingModelIDs.contains(model.id),
                        isManual: isManual,
                        onCopy: {
                            Clipboard.copy(model.id)
                            viewModel.showToast("模型ID已复制")
                        },
                        onTest: {
                            viewModel.test(modelID: model.id)
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectedModelID = model.id
                        viewModel.selectedSummary = model.latestTest
                        if model.latestTest == nil {
                            viewModel.expandedTestModelID = nil
                        } else {
                            viewModel.expandedTestModelID =
                                viewModel.expandedTestModelID == model.id
                                ? nil
                                : model.id
                        }
                    }

                    if viewModel.expandedTestModelID == model.id,
                       let summary = model.latestTest {
                        TestDetailView(summary: summary)
                            .padding(.leading, 34)
                            .padding(.bottom, 10)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    viewModel.selectedModelID == model.id
                        ? Color.accentColor.opacity(0.08)
                        : .clear
                )
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
