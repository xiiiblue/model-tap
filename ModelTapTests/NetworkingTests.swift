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

    func testHTTPErrorMapping() {
        for status in [401, 404, 429, 500] {
            let response = HTTPURLResponse(url: URL(string: "https://example.test")!, statusCode: status, httpVersion: nil, headerFields: nil)!
            guard case .http(let mapped, _, _) = ModelDiscoveryService.httpError(response, data: Data()) else { return XCTFail("not HTTP error") }
            XCTAssertEqual(mapped, status)
        }
    }

    func testAuthorizationAndEmptyKey() async throws {
        let client = RecordingClient(data: Data(#"{"object":"list","data":[{"id":"one"}]}"#.utf8), status: 200)
        _ = try await ModelDiscoveryService(client: client).discover(baseURL: "https://example.test/v1", apiKey: "sk-fake-key")
        XCTAssertEqual(client.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-fake-key")
        let noKeyClient = RecordingClient(data: Data(#"{"object":"list","data":[{"id":"one"}]}"#.utf8), status: 200)
        _ = try await ModelDiscoveryService(client: noKeyClient).discover(baseURL: "https://example.test/v1", apiKey: "")
        XCTAssertNil(noKeyClient.lastRequest?.value(forHTTPHeaderField: "Authorization"))
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
