import Foundation
import SwiftData
import XCTest
@testable import ModelTap

final class SecurityAndBatchTests: XCTestCase {
    func testRedaction() {
        XCTAssertEqual(Redaction.apiKey("sk-1234567890abcd"), "sk-1••••••••abcd")
        XCTAssertFalse(Redaction.sensitive("Bearer sk-1234567890abcd", apiKey: "sk-1234567890abcd").contains("sk-1234567890abcd"))
    }

    func testLocalAPIKeyCipherRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cipher = LocalAPIKeyCipher(
            keyURL: directory.appendingPathComponent("local-encryption.key")
        )

        let encrypted = try cipher.encrypt("sk-fake")

        XCTAssertNotEqual(encrypted, Data("sk-fake".utf8))
        XCTAssertEqual(try cipher.decrypt(encrypted), "sk-fake")
    }

    @MainActor func testRepositoryStoresEncryptedAPIKey() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: APIProfile.self,
            ProfileFolder.self,
            ModelTestRecord.self,
            configurations: configuration
        )
        let cipher = TestAPIKeyCipher()
        let repository = ProfileRepository(
            modelContext: container.mainContext,
            apiKeyCipher: cipher
        )
        let folder = try repository.createFolder(name: "开发环境")
        let profile = try repository.saveProfile(
            profile: nil,
            name: "测试配置",
            baseURL: "https://example.test/v1",
            apiKey: "sk-fake",
            apiFormat: .openAI,
            folderID: folder.id,
            notes: ""
        )

        XCTAssertEqual(try repository.apiKey(for: profile), "sk-fake")
        XCTAssertEqual(profile.encryptedAPIKey, Data("encrypted:sk-fake".utf8))
        XCTAssertNil(profile.keychainReference)
        XCTAssertEqual(profile.folderID, folder.id)

        try repository.renameFolder(folder, name: "测试环境")
        XCTAssertEqual(folder.name, "测试环境")

        try repository.deleteFolder(folder)
        XCTAssertNil(profile.folderID)
    }

    @MainActor func testBatchContinuesAfterOneFailure() async {
        let runner = BatchTestRunner { id in
            if id == "bad" { throw APIError.http(status: 500, message: "fake", kind: .server) }
            return ModelTestSummary(success: true, statusCode: 200, duration: 0.01, testedAt: .now, protocolName: .chatCompletions, output: "OK", errorSummary: nil, tokenUsage: nil)
        }
        var completed: [String] = []
        let result = await runner.run(models: [ModelInfo(id: "good-1", object: nil, latestTest: nil), ModelInfo(id: "bad", object: nil, latestTest: nil), ModelInfo(id: "good-2", object: nil, latestTest: nil)], onResult: { id, _ in completed.append(id) }, onProgress: { _, _ in })
        XCTAssertEqual(completed, ["good-1", "bad", "good-2"])
        XCTAssertEqual(result.succeeded, 2)
        XCTAssertEqual(result.failed, 1)
    }

    @MainActor func testModelKeepsLoadingStateWhileRequestIsRunning() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: APIProfile.self,
            ProfileFolder.self,
            ModelTestRecord.self,
            configurations: configuration
        )
        let viewModel = ContentViewModel(
            modelContext: container.mainContext,
            apiKeyCipher: TestAPIKeyCipher(),
            client: DelayedAPIClient(delayNanoseconds: 250_000_000)
        )
        let profile = try viewModel.repository.saveProfile(
            profile: nil,
            name: "测试配置",
            baseURL: "https://example.test/v1",
            apiKey: "",
            apiFormat: .openAI,
            folderID: nil,
            notes: ""
        )
        viewModel.selectedProfile = profile
        viewModel.models = [ModelInfo(id: "gpt-example", object: "model", latestTest: nil)]

        viewModel.test(modelID: "gpt-example")
        await Task.yield()

        XCTAssertTrue(viewModel.testingModelIDs.contains("gpt-example"))

        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertFalse(viewModel.testingModelIDs.contains("gpt-example"))
        XCTAssertTrue(viewModel.models.first?.latestTest?.success == true)
    }
}

private struct TestAPIKeyCipher: APIKeyEncrypting {
    func encrypt(_ value: String) throws -> Data {
        Data("encrypted:\(value)".utf8)
    }

    func decrypt(_ data: Data) throws -> String {
        String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "encrypted:", with: "")
    }
}

private struct DelayedAPIClient: APIClienting {
    let delayNanoseconds: UInt64

    func request(_ request: URLRequest) async throws -> (Data, HTTPURLResponse, TimeInterval) {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        let data = Data(#"{"choices":[{"message":{"content":"OK"}}]}"#.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response, Double(delayNanoseconds) / 1_000_000_000)
    }
}
