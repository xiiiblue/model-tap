import Foundation
import SwiftData

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var selectedProfile: APIProfile?
    @Published var models: [ModelInfo] = []
    @Published var searchText = ""
    @Published var modelSearchText = ""
    @Published var loadState: LoadState = .idle
    @Published var notice: RequestNotice?
    @Published var selectedModelID: String?
    @Published var selectedSummary: ModelTestSummary?
    @Published var isBatchTesting = false
    @Published var batchProgress: (completed: Int, total: Int)?
    @Published var lastDiscovery: (count: Int, duration: TimeInterval, date: Date)?
    @Published var editor: ProfileEditorState?

    let modelContext: ModelContext
    let repository: ProfileRepository
    private let discovery: ModelDiscoveryService
    private let tester: ModelTestService
    private var requestTask: Task<Void, Never>?

    init(modelContext: ModelContext, keychain: KeychainStoring = KeychainStore(), client: APIClienting = URLSessionAPIClient()) {
        self.modelContext = modelContext
        self.repository = ProfileRepository(modelContext: modelContext, keychain: keychain)
        self.discovery = ModelDiscoveryService(client: client)
        self.tester = ModelTestService(client: client)
    }

    var filteredModels: [ModelInfo] { modelSearchText.isEmpty ? models : models.filter { $0.id.localizedCaseInsensitiveContains(modelSearchText) } }

    func startNewProfile() { editor = ProfileEditorState() }

    func edit(_ profile: APIProfile) {
        do { editor = try ProfileEditorState(profile: profile, apiKey: repository.apiKey(for: profile)) }
        catch { show(error) }
    }

    func saveEditor() {
        guard let editor else { return }
        do {
            let profile = try repository.saveProfile(profile: editor.profile, name: editor.name, baseURL: editor.baseURL, apiKey: editor.apiKey, notes: editor.notes)
            selectedProfile = profile
            self.editor = nil
            notice = RequestNotice(message: "配置已保存")
        } catch { show(error) }
    }

    func delete(_ profile: APIProfile) {
        do { try repository.delete(profile); if selectedProfile?.id == profile.id { selectedProfile = nil; models = []; loadState = .idle } }
        catch { show(error) }
    }

    func duplicate(_ profile: APIProfile) {
        do { selectedProfile = try repository.duplicate(profile); notice = RequestNotice(message: "配置已复制") }
        catch { show(error) }
    }

    func discover() {
        guard let profile = selectedProfile else { return }
        requestTask?.cancel()
        loadState = .loading
        requestTask = Task { [weak self] in
            guard let self else { return }
            do {
                let key = try repository.apiKey(for: profile)
                let result = try await discovery.discover(baseURL: profile.baseURL, apiKey: key)
                models = result.models
                lastDiscovery = (result.models.count, result.duration, result.testedAt)
                selectedModelID = models.first?.id
                profile.lastUsedAt = .now
                loadState = .loaded
                try? modelContext.save()
            } catch {
                if !Task.isCancelled { loadState = .failed(Self.friendlyMessage(error)) }
            }
        }
    }

    func testSelected() {
        guard let id = selectedModelID else { return }
        test(modelID: id)
    }

    func test(modelID: String) {
        guard let profile = selectedProfile else { return }
        requestTask?.cancel()
        requestTask = Task { [weak self] in
            guard let self else { return }
            let start = Date()
            do {
                let key = try repository.apiKey(for: profile)
                let summary = try await tester.test(modelID: modelID, baseURL: profile.baseURL, apiKey: key)
                updateModel(id: modelID, summary: summary)
                selectedSummary = summary
                try repository.saveTestRecord(summary, modelID: modelID, profile: profile)
                notice = RequestNotice(message: "\(modelID) 测试成功")
            } catch {
                let summary = ModelTestSummary(success: false, statusCode: Self.statusCode(error), duration: Date().timeIntervalSince(start), testedAt: .now, protocolName: nil, output: nil, errorSummary: Self.friendlyMessage(error), tokenUsage: nil)
                updateModel(id: modelID, summary: summary)
                selectedSummary = summary
                try? repository.saveTestRecord(summary, modelID: modelID, profile: profile)
            }
        }
    }

    func testAll() {
        guard let profile = selectedProfile, !filteredModels.isEmpty else { return }
        requestTask?.cancel()
        isBatchTesting = true
        batchProgress = (0, filteredModels.count)
        let batchModels = filteredModels
        requestTask = Task { [weak self] in
            guard let self else { return }
            let key = (try? repository.apiKey(for: profile)) ?? ""
            let baseURL = profile.baseURL
            let profileID = profile.id
            let runner = BatchTestRunner { [tester] id in try await tester.test(modelID: id, baseURL: baseURL, apiKey: key) }
            let result = await runner.run(models: batchModels, onResult: { [weak self] id, result in
                guard let self else { return }
                switch result {
                case .success(let summary):
                    updateModel(id: id, summary: summary)
                    if let currentProfile = try? modelContext.fetch(FetchDescriptor<APIProfile>()).first(where: { $0.id == profileID }) { try? repository.saveTestRecord(summary, modelID: id, profile: currentProfile) }
                case .failure(let error):
                    let summary = ModelTestSummary(success: false, statusCode: Self.statusCode(error), duration: 0, testedAt: .now, protocolName: nil, output: nil, errorSummary: Self.friendlyMessage(error), tokenUsage: nil)
                    updateModel(id: id, summary: summary)
                    if let currentProfile = try? modelContext.fetch(FetchDescriptor<APIProfile>()).first(where: { $0.id == profileID }) { try? repository.saveTestRecord(summary, modelID: id, profile: currentProfile) }
                }
            }, onProgress: { [weak self] completed, total in self?.batchProgress = (completed, total) })
            isBatchTesting = false
            batchProgress = nil
            notice = RequestNotice(message: "批量测试完成：成功 \(result.succeeded)，失败 \(result.failed)，耗时 \(Formatters.duration(result.duration))")
        }
    }

    func cancel() { requestTask?.cancel(); requestTask = nil; isBatchTesting = false; batchProgress = nil; loadState = .idle }

    private func updateModel(id: String, summary: ModelTestSummary) { if let index = models.firstIndex(where: { $0.id == id }) { models[index].latestTest = summary } }
    private func show(_ error: Error) { notice = RequestNotice(message: Self.friendlyMessage(error)) }
    static func statusCode(_ error: Error) -> Int? { if case APIError.http(let status, _, _) = error { return status }; return nil }
    static func friendlyMessage(_ error: Error) -> String { (error as? LocalizedError)?.errorDescription ?? "操作失败，请稍后重试。" }
}

@MainActor
struct ProfileEditorState: Identifiable {
    let id = UUID()
    var profile: APIProfile?
    var name = ""
    var baseURL = ""
    var apiKey = ""
    var notes = ""
    init() {}
    init(profile: APIProfile, apiKey: String) { self.profile = profile; self.name = profile.name; self.baseURL = profile.baseURL; self.apiKey = apiKey; self.notes = profile.notes }
}
