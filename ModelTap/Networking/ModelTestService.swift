import Foundation

struct ChatCompletionsResponse: Decodable, Sendable {
    let choices: [ChatChoice]
    let usage: UsagePayload?
}
struct ChatChoice: Decodable, Sendable { let message: ChatMessage?; let text: String? }
struct ChatMessage: Decodable, Sendable { let content: String? }
struct ResponsesResponse: Decodable, Sendable {
    let output: [ResponseOutputItem]?
    let outputText: String?
    let usage: UsagePayload?
    enum CodingKeys: String, CodingKey { case output, outputText = "output_text", usage }
}
struct ResponseOutputItem: Decodable, Sendable { let content: [ResponseContentItem]? }
struct ResponseContentItem: Decodable, Sendable { let text: String? }
struct AnthropicMessagesResponse: Decodable, Sendable {
    let content: [AnthropicContentItem]
    let usage: UsagePayload?
}
struct AnthropicContentItem: Decodable, Sendable {
    let type: String?
    let text: String?
}
struct UsagePayload: Decodable, Sendable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    enum CodingKeys: String, CodingKey { case promptTokens = "prompt_tokens", completionTokens = "completion_tokens", totalTokens = "total_tokens", inputTokens = "input_tokens", outputTokens = "output_tokens" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        promptTokens = try c.decodeIfPresent(Int.self, forKey: .promptTokens) ?? c.decodeIfPresent(Int.self, forKey: .inputTokens)
        completionTokens = try c.decodeIfPresent(Int.self, forKey: .completionTokens) ?? c.decodeIfPresent(Int.self, forKey: .outputTokens)
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens)
    }
    var modelUsage: TokenUsage { TokenUsage(promptTokens: promptTokens, completionTokens: completionTokens, totalTokens: totalTokens) }
}

struct ModelTestService: Sendable {
    let client: APIClienting
    let prompt = "仅回复：OK"

    func test(modelID: String, baseURL: String, apiKey: String, format: APIFormat) async throws -> ModelTestSummary {
        switch format {
        case .openAI:
            return try await testChat(modelID: modelID, baseURL: baseURL, apiKey: apiKey)
        case .openAIResponses:
            return try await testResponses(modelID: modelID, baseURL: baseURL, apiKey: apiKey)
        case .anthropic:
            return try await testAnthropicMessages(modelID: modelID, baseURL: baseURL, apiKey: apiKey)
        }
    }

    private func testChat(modelID: String, baseURL: String, apiKey: String) async throws -> ModelTestSummary {
        let resolver = try EndpointResolver(baseURLString: baseURL)
        var request = URLRequest(url: resolver.chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthorization(to: &request, apiKey: apiKey)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": modelID, "messages": [["role": "user", "content": prompt]], "temperature": 0, "max_tokens": 16, "stream": false])
        let (data, response, duration) = try await client.request(request)
        guard (200..<300).contains(response.statusCode) else { throw ModelDiscoveryService.httpError(response, data: data) }
        let decoded: ChatCompletionsResponse
        do { decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data) } catch { throw APIError.invalidJSON("Chat Completions 响应") }
        guard let output = decoded.choices.first?.message?.content ?? decoded.choices.first?.text, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.invalidModelOutput }
        return ModelTestSummary(success: true, statusCode: response.statusCode, duration: duration, testedAt: .now, protocolName: .chatCompletions, output: output, errorSummary: nil, tokenUsage: decoded.usage?.modelUsage)
    }

    private func testResponses(modelID: String, baseURL: String, apiKey: String) async throws -> ModelTestSummary {
        let resolver = try EndpointResolver(baseURLString: baseURL)
        var request = URLRequest(url: resolver.responsesURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthorization(to: &request, apiKey: apiKey)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": modelID, "input": prompt, "temperature": 0, "max_output_tokens": 16, "stream": false])
        let (data, response, duration) = try await client.request(request)
        guard (200..<300).contains(response.statusCode) else { throw ModelDiscoveryService.httpError(response, data: data) }
        let decoded: ResponsesResponse
        do { decoded = try JSONDecoder().decode(ResponsesResponse.self, from: data) } catch { throw APIError.invalidJSON("Responses 响应") }
        let output = decoded.outputText ?? decoded.output?.flatMap { $0.content ?? [] }.compactMap(\ .text).joined() ?? ""
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.invalidModelOutput }
        return ModelTestSummary(success: true, statusCode: response.statusCode, duration: duration, testedAt: .now, protocolName: .responses, output: output, errorSummary: nil, tokenUsage: decoded.usage?.modelUsage)
    }

    private func testAnthropicMessages(modelID: String, baseURL: String, apiKey: String) async throws -> ModelTestSummary {
        let resolver = try EndpointResolver(baseURLString: baseURL)
        var request = URLRequest(url: resolver.anthropicMessagesURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "x-api-key") }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": modelID, "max_tokens": 16, "messages": [["role": "user", "content": prompt]]])
        let (data, response, duration) = try await client.request(request)
        guard (200..<300).contains(response.statusCode) else { throw ModelDiscoveryService.httpError(response, data: data) }
        let decoded: AnthropicMessagesResponse
        do { decoded = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data) } catch { throw APIError.invalidJSON("Anthropic Messages 响应") }
        let output = decoded.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.invalidModelOutput }
        return ModelTestSummary(success: true, statusCode: response.statusCode, duration: duration, testedAt: .now, protocolName: .anthropicMessages, output: output, errorSummary: nil, tokenUsage: decoded.usage?.modelUsage)
    }

    private func addAuthorization(to request: inout URLRequest, apiKey: String) {
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
    }
}
