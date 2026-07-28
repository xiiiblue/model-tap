import XCTest
@testable import ModelTap

final class EndpointResolverTests: XCTestCase {
    func testNormalizesKnownFullEndpointsWithoutAddingV1() throws {
        let cases = [
            ("https://api.example.com", "https://api.example.com"),
            ("https://api.example.com/", "https://api.example.com"),
            ("https://api.example.com/v1/", "https://api.example.com/v1"),
            ("https://api.example.com/v1/models", "https://api.example.com/v1"),
            ("https://api.example.com/v1/chat/completions", "https://api.example.com/v1")
        ]
        for (input, expected) in cases {
            XCTAssertEqual(try EndpointResolver(baseURLString: input).baseURL.absoluteString, expected)
        }
    }

    func testBuildsAllEndpoints() throws {
        let resolver = try EndpointResolver(baseURLString: "https://example.test/custom")
        XCTAssertEqual(resolver.modelsURL.absoluteString, "https://example.test/custom/models")
        XCTAssertEqual(resolver.chatCompletionsURL.absoluteString, "https://example.test/custom/chat/completions")
        XCTAssertEqual(resolver.responsesURL.absoluteString, "https://example.test/custom/responses")
    }

    func testRejectsInvalidURL() {
        XCTAssertThrowsError(try EndpointResolver(baseURLString: ""))
        XCTAssertThrowsError(try EndpointResolver(baseURLString: "ftp://example.test"))
    }
}
