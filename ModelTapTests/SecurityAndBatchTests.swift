import Foundation
import SwiftData
import XCTest
@testable import ModelTap

final class SecurityAndBatchTests: XCTestCase {
    func testRedaction() {
        XCTAssertEqual(Redaction.apiKey("sk-1234567890abcd"), "sk-1••••••••abcd")
        XCTAssertFalse(Redaction.sensitive("Bearer sk-1234567890abcd", apiKey: "sk-1234567890abcd").contains("sk-1234567890abcd"))
    }

    func testMockKeychainLifecycle() throws {
        let keychain = InMemoryKeychainStore()
        try keychain.save("sk-fake", for: "profile-1")
        XCTAssertEqual(try keychain.read(reference: "profile-1"), "sk-fake")
        try keychain.delete(reference: "profile-1")
        XCTAssertNil(try keychain.read(reference: "profile-1"))
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
            ModelTestRecord.self,
            configurations: configuration
        )
        let viewModel = ContentViewModel(
            modelContext: container.mainContext,
            keychain: InMemoryKeychainStore(),
            client: DelayedAPIClient(delayNanoseconds: 250_000_000)
        )
        let profile = try viewModel.repository.saveProfile(
            profile: nil,
            name: "测试配置",
            baseURL: "https://example.test/v1",
            apiKey: "",
            apiFormat: .openAI,
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
