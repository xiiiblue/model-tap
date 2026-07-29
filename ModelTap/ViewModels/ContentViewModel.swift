import Foundation
import SwiftData

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var selectedProfile: APIProfile?
    @Published var models: [ModelInfo] = []
    @Published var searchText = ""
    @Published var loadState: LoadState = .idle
    @Published var notice: RequestNotice?
    @Published var toast: RequestNotice?
    @Published var selectedModelID: String?
    @Published var selectedSummary: ModelTestSummary?
    @Published private(set) var testingModelIDs: Set<String> = []
    @Published var lastDiscovery: (count: Int, duration: TimeInterval, date: Date)?
    @Published var editor: ProfileEditorState?
    @Published private(set) var discoveredModelIDs: Set<String> = []

    let modelContext: ModelContext
    let repository: ProfileRepository
    private let discovery: ModelDiscoveryService
    private let tester: ModelTestService
    private var requestTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var toastDismissTask: Task<Void, Never>?

    init(
        modelContext: ModelContext,
        apiKeyCipher: any APIKeyEncrypting = LocalAPIKeyCipher(),
        client: APIClienting = URLSessionAPIClient()
    ) {
        self.modelContext = modelContext
        self.repository = ProfileRepository(modelContext: modelContext, apiKeyCipher: apiKeyCipher)
        self.discovery = ModelDiscoveryService(client: client)
        self.tester = ModelTestService(client: client)
        do {
            try repository.migrateLegacyCategories()
        } catch {
            notice = RequestNotice(
                message: "旧分类数据迁移失败：\(Self.friendlyMessage(error))"
            )
        }
    }

    func selectedProfileDidChange() {
        invalidateActiveRequest()
        discoveredModelIDs.removeAll()
        selectedModelID = nil
        selectedSummary = nil
        lastDiscovery = nil
        guard let selectedProfile else {
            models = []
            loadState = .idle
            return
        }
        models = selectedProfile.manualModelIDs.map {
            ModelInfo(id: $0, object: nil, latestTest: nil)
        }
        loadState = models.isEmpty ? .idle : .loaded
    }

    func isManualModel(_ modelID: String) -> Bool {
        selectedProfile?.manualModelIDs.contains(modelID) == true
    }

    func addManualModel(id rawID: String, testAfterAdding: Bool) {
        guard let profile = selectedProfile else { return }
        let modelID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty else { return }
        do {
            try repository.addManualModel(modelID, to: profile)
            if !models.contains(where: { $0.id == modelID }) {
                models.append(ModelInfo(id: modelID, object: nil, latestTest: nil))
            }
            loadState = .loaded
            selectedModelID = modelID
            selectedSummary = models.first(where: { $0.id == modelID })?.latestTest
            if testAfterAdding {
                test(modelID: modelID)
            }
        } catch {
            show(error)
        }
    }

    func removeManualModel(id modelID: String) {
        guard let profile = selectedProfile else { return }
        do {
            try repository.removeManualModel(modelID, from: profile)
            if !discoveredModelIDs.contains(modelID) {
                models.removeAll { $0.id == modelID }
            }
            if selectedModelID == modelID {
                selectedModelID = nil
                selectedSummary = nil
            }
            if models.isEmpty {
                loadState = .idle
            }
        } catch {
            show(error)
        }
    }

    func startNewProfile() { editor = ProfileEditorState() }

    func edit(_ profile: APIProfile) {
        do { editor = try ProfileEditorState(profile: profile, apiKey: repository.apiKey(for: profile)) }
        catch { show(error) }
    }

    func saveEditor() {
        guard let editor else { return }
        do {
            let profile = try repository.saveProfile(profile: editor.profile, name: editor.name, baseURL: editor.baseURL, apiKey: editor.apiKey, apiFormat: editor.apiFormat, folderID: editor.folderID, notes: editor.notes)
            selectedProfile = profile
            self.editor = nil
        } catch { show(error) }
    }

    func delete(_ profile: APIProfile) {
        if selectedProfile?.id == profile.id {
            invalidateActiveRequest()
        }
        do { try repository.delete(profile); if selectedProfile?.id == profile.id { selectedProfile = nil; models = []; loadState = .idle } }
        catch { show(error) }
    }

    func duplicate(_ profile: APIProfile) {
        do {
            selectedProfile = try repository.duplicate(profile)
            showToast("配置已复制")
        }
        catch { show(error) }
    }

    func createFolder(name: String) {
        do { _ = try repository.createFolder(name: name) }
        catch { show(error) }
    }

    func renameFolder(_ folder: ProfileFolder, name: String) {
        do { try repository.renameFolder(folder, name: name) }
        catch { show(error) }
    }

    func deleteFolder(_ folder: ProfileFolder) {
        do { try repository.deleteFolder(folder) }
        catch { show(error) }
    }

    func move(_ profile: APIProfile, to folder: ProfileFolder?) {
        do { try repository.move(profile, to: folder) }
        catch { show(error) }
    }

    func reorder(
        _ profile: APIProfile,
        relativeTo target: APIProfile,
        placeAfter: Bool
    ) {
        do {
            try repository.reorder(
                profile,
                relativeTo: target,
                placeAfter: placeAfter
            )
        }
        catch { show(error) }
    }

    func reorder(
        _ folder: ProfileFolder,
        relativeTo target: ProfileFolder,
        placeAfter: Bool
    ) {
        do {
            try repository.reorder(
                folder,
                relativeTo: target,
                placeAfter: placeAfter
            )
        }
        catch { show(error) }
    }

    func markdownBackup() throws -> String {
        try MarkdownBackupCodec.encode(repository.makeBackup())
    }

    func replaceAll(with backup: ModelTapBackup) {
        invalidateActiveRequest()
        do {
            try repository.replaceAll(with: backup)
            selectedProfile = nil
            models = []
            loadState = .idle
            selectedModelID = nil
            selectedSummary = nil
            notice = RequestNotice(
                message: "已导入\(backup.profiles.count)项配置"
            )
        } catch {
            show(error)
        }
    }

    func showToast(_ message: String) {
        toastDismissTask?.cancel()
        toast = RequestNotice(message: message)
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func discover() {
        guard let profile = selectedProfile else { return }
        let profileID = profile.id
        let requestID = beginRequest()
        loadState = .loading
        requestTask = Task { [weak self] in
            guard let self else { return }
            defer { finishRequest(requestID) }
            var apiKey = ""
            do {
                apiKey = try repository.apiKey(for: profile)
                let result = try await discovery.discover(baseURL: profile.baseURL, apiKey: apiKey, format: profile.apiFormat)
                guard isCurrentRequest(requestID, profileID: profileID) else { return }
                let existingSummaries = Dictionary(
                    uniqueKeysWithValues: models.compactMap { model in
                        model.latestTest.map { (model.id, $0) }
                    }
                )
                discoveredModelIDs = Set(result.models.map(\.id))
                let manualModels = profile.manualModelIDs
                    .filter { !discoveredModelIDs.contains($0) }
                    .map { ModelInfo(id: $0, object: nil, latestTest: nil) }
                models = (result.models + manualModels).map { model in
                    var model = model
                    model.latestTest = existingSummaries[model.id]
                    return model
                }
                lastDiscovery = (result.models.count, result.duration, result.testedAt)
                selectedModelID = models.first?.id
                profile.lastUsedAt = .now
                loadState = .loaded
                do {
                    try modelContext.save()
                } catch {
                    show(error)
                }
            } catch {
                guard isCurrentRequest(requestID, profileID: profileID),
                      !Self.isCancellation(error) else { return }
                loadState = .failed(Self.friendlyMessage(error, apiKey: apiKey))
            }
        }
    }

    func testSelected() {
        guard let id = selectedModelID else { return }
        test(modelID: id)
    }

    func test(modelID: String) {
        guard let profile = selectedProfile else { return }
        let profileID = profile.id
        let requestID = beginRequest()
        if loadState == .loading {
            loadState = models.isEmpty ? .idle : .loaded
        }
        testingModelIDs = [modelID]
        requestTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if activeRequestID == requestID {
                    testingModelIDs.remove(modelID)
                }
                finishRequest(requestID)
            }
            await Task.yield()
            let start = Date()
            let apiKey: String
            do {
                apiKey = try repository.apiKey(for: profile)
            } catch {
                guard isCurrentRequest(requestID, profileID: profileID) else { return }
                show(error)
                return
            }

            let summary: ModelTestSummary
            do {
                summary = try await tester.test(modelID: modelID, baseURL: profile.baseURL, apiKey: apiKey, format: profile.apiFormat)
            } catch {
                guard !Self.isCancellation(error),
                      isCurrentRequest(requestID, profileID: profileID) else { return }
                summary = ModelTestSummary(success: false, statusCode: Self.statusCode(error), duration: Date().timeIntervalSince(start), testedAt: .now, protocolName: nil, output: nil, errorSummary: Self.friendlyMessage(error, apiKey: apiKey), tokenUsage: nil)
            }

            guard isCurrentRequest(requestID, profileID: profileID) else { return }
            updateModel(id: modelID, summary: summary)
            selectedSummary = summary
            do {
                try repository.saveTestRecord(summary, modelID: modelID, profile: profile)
            } catch {
                show(error)
            }
        }
    }

    func cancel() {
        invalidateActiveRequest()
        loadState = models.isEmpty ? .idle : .loaded
    }

    private func updateModel(id: String, summary: ModelTestSummary) { if let index = models.firstIndex(where: { $0.id == id }) { models[index].latestTest = summary } }
    private func show(_ error: Error) { notice = RequestNotice(message: Self.friendlyMessage(error)) }
    func present(_ error: Error) { show(error) }

    private func beginRequest() -> UUID {
        requestTask?.cancel()
        testingModelIDs.removeAll()
        let requestID = UUID()
        activeRequestID = requestID
        return requestID
    }

    private func finishRequest(_ requestID: UUID) {
        guard activeRequestID == requestID else { return }
        activeRequestID = nil
        requestTask = nil
    }

    private func invalidateActiveRequest() {
        activeRequestID = nil
        requestTask?.cancel()
        requestTask = nil
        testingModelIDs.removeAll()
    }

    private func isCurrentRequest(_ requestID: UUID, profileID: UUID) -> Bool {
        activeRequestID == requestID
            && selectedProfile?.id == profileID
            && !Task.isCancelled
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? APIError) == .cancelled
    }

    static func statusCode(_ error: Error) -> Int? { if case APIError.http(let status, _, _) = error { return status }; return nil }
    static func friendlyMessage(_ error: Error, apiKey: String? = nil) -> String {
        let message = (error as? LocalizedError)?.errorDescription ?? "操作失败，请稍后重试。"
        return Redaction.sensitive(message, apiKey: apiKey)
    }
}

@MainActor
struct ProfileEditorState: Identifiable {
    let id = UUID()
    var profile: APIProfile?
    var name = ""
    var baseURL = ""
    var apiKey = ""
    var apiFormat: APIFormat = .openAI
    var folderID: UUID?
    var notes = ""
    init() {}
    init(profile: APIProfile, apiKey: String) { self.profile = profile; self.name = profile.name; self.baseURL = profile.baseURL; self.apiKey = apiKey; self.apiFormat = profile.apiFormat; self.folderID = profile.folderID; self.notes = profile.notes }
}
