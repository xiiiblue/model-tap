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
}
