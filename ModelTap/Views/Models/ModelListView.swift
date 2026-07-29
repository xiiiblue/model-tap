import SwiftUI

struct ModelListView: View {
    @ObservedObject var viewModel: ContentViewModel
    @State private var isManualModelPopoverPresented = false
    @State private var manualModelID = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("模型").font(.headline)
                Spacer()
                if let discovery = viewModel.lastDiscovery {
                    Text(
                        "\(discovery.count)个 · \(Formatters.duration(discovery.duration)) · \(discovery.date.modelTapShort)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                TextField("搜索模型ID", text: $viewModel.modelSearchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
                Button {
                    presentManualModelPopover()
                } label: {
                    Label("手动模型", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .help("手动添加模型ID")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .popover(isPresented: $isManualModelPopoverPresented, arrowEdge: .top) {
            manualModelPopover
        }
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

                if viewModel.filteredModels.isEmpty {
                    ContentUnavailableView(
                        "没有匹配的模型",
                        systemImage: "magnifyingglass"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    modelRows
                }
            }
        }
    }

    @ViewBuilder private var emptyContent: some View {
        switch viewModel.loadState {
        case .idle, .loaded:
            ContentUnavailableView {
                Label("尚无模型", systemImage: "list.bullet.rectangle")
            } description: {
                Text("可以查询服务端模型列表，也可以手动添加模型ID。")
            } actions: {
                Button("手动添加模型", systemImage: "plus") {
                    presentManualModelPopover()
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
                Button("手动添加模型", systemImage: "plus") {
                    presentManualModelPopover()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var modelRows: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.filteredModels) { model in
                    let isManual = viewModel.isManualModel(model.id)
                    ModelRowView(
                        model: model,
                        isTesting: viewModel.testingModelIDs.contains(model.id),
                        isManual: isManual,
                        onCopy: {
                            Clipboard.copy(model.id)
                            viewModel.notice = RequestNotice(message: "模型ID已复制")
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

    private var manualModelPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("手动添加模型")
                .font(.headline)
            TextField("模型ID", text: $manualModelID)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .onSubmit {
                    addManualModel(testAfterAdding: false)
                }
            HStack {
                Spacer()
                Button("添加") {
                    addManualModel(testAfterAdding: false)
                }
                .disabled(normalizedManualModelID.isEmpty)
                Button("添加并测试") {
                    addManualModel(testAfterAdding: true)
                }
                .buttonStyle(.borderedProminent)
                .disabled(normalizedManualModelID.isEmpty)
            }
        }
        .padding(18)
    }

    private var normalizedManualModelID: String {
        manualModelID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func presentManualModelPopover() {
        manualModelID = ""
        isManualModelPopoverPresented = true
    }

    private func addManualModel(testAfterAdding: Bool) {
        let modelID = normalizedManualModelID
        guard !modelID.isEmpty else { return }
        isManualModelPopoverPresented = false
        viewModel.addManualModel(
            id: modelID,
            testAfterAdding: testAfterAdding
        )
        manualModelID = ""
    }
}
