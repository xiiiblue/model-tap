import Foundation

struct ModelInfo: Identifiable, Hashable, Sendable {
    let id: String
    let object: String?
    var latestTest: ModelTestSummary?
}

struct ModelTestSummary: Hashable, Sendable {
    let success: Bool
    let statusCode: Int?
    let duration: TimeInterval
    let testedAt: Date
    let protocolName: APIProtocolName?
    let output: String?
    let errorSummary: String?
    let tokenUsage: TokenUsage?
}

enum APIProtocolName: String, Codable, Sendable {
    case chatCompletions = "Chat Completions"
    case responses = "Responses"
    case anthropicMessages = "Anthropic Messages"
}

struct TokenUsage: Codable, Hashable, Sendable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
}
