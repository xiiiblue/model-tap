import XCTest
@testable import ModelTap

final class NetworkingTests: XCTestCase {
    func testModelListParsing() throws {
        let data = Data(#"{"object":"list","data":[{"id":"gpt-example","object":"model"}]}"#.utf8)
        let response = try JSONDecoder().decode(ModelListResponse.self, from: data)
        XCTAssertEqual(response.data.map(\.id), ["gpt-example"])
    }

    func testMalformedJSONFails() {
        XCTAssertThrowsError(try JSONDecoder().decode(ModelListResponse.self, from: Data("not-json".utf8)))
    }

    func testChatResponseParsing() throws {
        let data = Data(#"{"choices":[{"message":{"content":"OK"}}],"usage":{"prompt_tokens":4,"completion_tokens":1,"total_tokens":5}}"#.utf8)
        let response = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        XCTAssertEqual(response.choices.first?.message?.content, "OK")
        XCTAssertEqual(response.usage?.modelUsage.totalTokens, 5)
    }

    func testResponsesResponseParsing() throws {
        let data = Data(#"{"output":[{"content":[{"text":"OK"}]}],"usage":{"input_tokens":4,"output_tokens":1,"total_tokens":5}}"#.utf8)
        let response = try JSONDecoder().decode(ResponsesResponse.self, from: data)
        XCTAssertEqual(response.output?.first?.content?.first?.text, "OK")
        XCTAssertEqual(response.usage?.modelUsage.promptTokens, 4)
    }

    func testAnthropicResponseParsing() throws {
        let data = Data(#"{"content":[{"type":"text","text":"OK"}],"usage":{"input_tokens":4,"output_tokens":1}}"#.utf8)
        let response = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        XCTAssertEqual(response.content.first?.text, "OK")
        XCTAssertEqual(response.usage?.modelUsage.promptTokens, 4)
        XCTAssertEqual(response.usage?.modelUsage.completionTokens, 1)
    }

    func testHTTPErrorMapping() {
        for status in [401, 404, 429, 500] {
            let response = HTTPURLResponse(url: URL(string: "https://example.test")!, statusCode: status, httpVersion: nil, headerFields: nil)!
            guard case .http(let mapped, _, _) = ModelDiscoveryService.httpError(response, data: Data()) else { return XCTFail("not HTTP error") }
            XCTAssertEqual(mapped, status)
        }
    }

    func testAuthorizationAndEmptyKey() async throws {
        let client = RecordingClient(data: Data(#"{"object":"list","data":[{"id":"one"}]}"#.utf8), status: 200)
        _ = try await ModelDiscoveryService(client: client).discover(baseURL: "https://example.test/v1", apiKey: "sk-fake-key", format: .openAI)
        XCTAssertEqual(client.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-fake-key")
        let noKeyClient = RecordingClient(data: Data(#"{"object":"list","data":[{"id":"one"}]}"#.utf8), status: 200)
        _ = try await ModelDiscoveryService(client: noKeyClient).discover(baseURL: "https://example.test/v1", apiKey: "", format: .openAI)
        XCTAssertNil(noKeyClient.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    func testAnthropicDiscoveryUsesAnthropicHeaders() async throws {
        let client = RecordingClient(data: Data(#"{"data":[{"id":"claude-example","type":"model"}]}"#.utf8), status: 200)
        let result = try await ModelDiscoveryService(client: client).discover(baseURL: "https://example.test/v1", apiKey: "anthropic-fake-key", format: .anthropic)
        XCTAssertEqual(result.models.first?.id, "claude-example")
        XCTAssertEqual(result.models.first?.object, "model")
        XCTAssertEqual(client.lastRequest?.value(forHTTPHeaderField: "x-api-key"), "anthropic-fake-key")
        XCTAssertEqual(client.lastRequest?.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertNil(client.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    func testDiscoveryDeduplicatesRepeatedModelIDs() async throws {
        let client = RecordingClient(
            data: Data(
                #"{"data":[{"id":"same","object":"model"},{"id":"same","object":"model"},{"id":"other","object":"model"}]}"#.utf8
            ),
            status: 200
        )

        let result = try await ModelDiscoveryService(client: client).discover(
            baseURL: "https://example.test/v1",
            apiKey: "",
            format: .openAI
        )

        XCTAssertEqual(result.models.map(\.id), ["same", "other"])
    }

    func testAnthropicTestUsesMessagesRequest() async throws {
        let client = RecordingClient(data: Data(#"{"content":[{"type":"text","text":"OK"}],"usage":{"input_tokens":4,"output_tokens":1}}"#.utf8), status: 200)
        let summary = try await ModelTestService(client: client).test(modelID: "claude-example", baseURL: "https://example.test/v1", apiKey: "anthropic-fake-key", format: .anthropic)
        XCTAssertTrue(summary.success)
        XCTAssertEqual(summary.protocolName, .anthropicMessages)
        XCTAssertEqual(client.lastRequest?.url?.absoluteString, "https://example.test/v1/messages")
        XCTAssertEqual(client.lastRequest?.value(forHTTPHeaderField: "x-api-key"), "anthropic-fake-key")
        XCTAssertNil(client.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    func testChatTestUsesMinimalCompatiblePayload() async throws {
        let client = RecordingClient(
            data: Data(#"{"choices":[{"message":{"content":"OK"}}]}"#.utf8),
            status: 200
        )
        _ = try await ModelTestService(client: client).test(
            modelID: "chat-example",
            baseURL: "https://example.test/v1",
            apiKey: "",
            format: .openAI
        )

        let body = try XCTUnwrap(client.lastRequest?.httpBody)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(payload["model"] as? String, "chat-example")
        XCTAssertNotNil(payload["messages"])
        XCTAssertNil(payload["temperature"])
        XCTAssertNil(payload["max_tokens"])
        XCTAssertNil(payload["stream"])
    }

    func testResponsesTestUsesMinimalCompatiblePayload() async throws {
        let client = RecordingClient(
            data: Data(#"{"output":[{"content":[{"text":"OK"}]}]}"#.utf8),
            status: 200
        )
        _ = try await ModelTestService(client: client).test(
            modelID: "responses-example",
            baseURL: "https://example.test/v1",
            apiKey: "",
            format: .openAIResponses
        )

        let body = try XCTUnwrap(client.lastRequest?.httpBody)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(payload["model"] as? String, "responses-example")
        XCTAssertNotNil(payload["input"])
        XCTAssertNil(payload["temperature"])
        XCTAssertNil(payload["max_output_tokens"])
        XCTAssertNil(payload["stream"])
    }

    func testGPTImageModelUsesImageGenerationsRequest() async throws {
        let client = RecordingClient(
            data: Data(#"{"data":[{"b64_json":"aW1hZ2U="}]}"#.utf8),
            status: 200
        )
        let summary = try await ModelTestService(client: client).test(
            modelID: "gpt-image-2",
            baseURL: "https://example.test/v1",
            apiKey: "sk-fake-key",
            format: .openAIResponses
        )

        XCTAssertTrue(summary.success)
        XCTAssertEqual(summary.protocolName, .imageGenerations)
        XCTAssertEqual(client.lastRequest?.url?.absoluteString, "https://example.test/v1/images/generations")
        XCTAssertEqual(client.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-fake-key")

        let body = try XCTUnwrap(client.lastRequest?.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["model"] as? String, "gpt-image-2")
        XCTAssertEqual(payload["quality"] as? String, "low")
        XCTAssertEqual(payload["size"] as? String, "1024x1024")
        XCTAssertEqual(payload["output_format"] as? String, "jpeg")
    }

    func testOnlyGPTImageFamilyUsesImageEndpoint() {
        XCTAssertTrue(ModelTestService.isGPTImageModel("gpt-image-2"))
        XCTAssertTrue(ModelTestService.isGPTImageModel("openai/gpt-image-1.5"))
        XCTAssertFalse(ModelTestService.isGPTImageModel("gpt-5.5"))
        XCTAssertFalse(ModelTestService.isGPTImageModel("image-capable-text-model"))
    }
}

final class RecordingClient: APIClienting, @unchecked Sendable {
    let data: Data
    let status: Int
    private(set) var lastRequest: URLRequest?
    init(data: Data, status: Int) { self.data = data; self.status = status }
    func request(_ request: URLRequest) async throws -> (Data, HTTPURLResponse, TimeInterval) {
        lastRequest = request
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, 0.01)
    }
}
