import Foundation
import SwiftData

@MainActor
enum PreviewData {
    static let profile: APIProfile = {
        let profile = APIProfile(name: "本地 CPA", baseURL: "http://127.0.0.1:8317/v1", notes: "Preview 示例，不会发起真实请求")
        profile.lastTestStatusRaw = ProfileTestStatus.success.rawValue
        return profile
    }()

    static let models = [
        ModelInfo(id: "gpt-example", object: "model", latestTest: ModelTestSummary(success: true, statusCode: 200, duration: 0.42, testedAt: .now, protocolName: .chatCompletions, output: "OK", errorSummary: nil, tokenUsage: TokenUsage(promptTokens: 4, completionTokens: 1, totalTokens: 5))),
        ModelInfo(id: "local-reasoner", object: "model", latestTest: nil)
    ]
}
