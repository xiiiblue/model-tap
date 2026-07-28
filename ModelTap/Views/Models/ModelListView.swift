import SwiftUI

struct ModelListView: View {
    @ObservedObject var viewModel: ContentViewModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("模型").font(.headline)
                Spacer()
                if let discovery = viewModel.lastDiscovery { Text("\(discovery.count) 个 · \(Formatters.duration(discovery.duration)) · \(discovery.date.modelTapShort)").font(.caption).foregroundStyle(.secondary) }
                TextField("搜索模型 ID", text: $viewModel.modelSearchText).textFieldStyle(.roundedBorder).frame(width: 190)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            switch viewModel.loadState {
            case .idle:
                ContentUnavailableView("尚未查询模型", systemImage: "list.bullet.rectangle", description: Text("点击“查询模型”获取服务端模型列表。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loading:
                ProgressView("正在查询模型…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView("查询失败", systemImage: "exclamationmark.triangle", description: Text(message))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                if viewModel.filteredModels.isEmpty { ContentUnavailableView("没有匹配的模型", systemImage: "magnifyingglass") }
                else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(viewModel.filteredModels) { model in
                                ModelRowView(model: model, isTesting: viewModel.testingModelIDs.contains(model.id), onCopy: { Clipboard.copy(model.id); viewModel.notice = RequestNotice(message: "模型 ID 已复制") }, onTest: { viewModel.selectedModelID = model.id; viewModel.test(modelID: model.id) })
                                    .padding(.horizontal)
                                    .background(viewModel.selectedModelID == model.id ? Color.accentColor.opacity(0.08) : .clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture { viewModel.selectedModelID = model.id; viewModel.selectedSummary = model.latestTest }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: viewModel.modelSearchText) { _, _ in }
    }
}
