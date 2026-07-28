import Foundation

struct ModelListResponse: Decodable, Sendable {
    let object: String?
    let data: [RemoteModel]
}

struct RemoteModel: Decodable, Sendable {
    let id: String
    let object: String?
}

struct ModelDiscoveryService: Sendable {
    let client: APIClienting

    func discover(baseURL: String, apiKey: String) async throws -> (models: [ModelInfo], duration: TimeInterval, statusCode: Int, testedAt: Date) {
        let resolver = try EndpointResolver(baseURLString: baseURL)
        var request = URLRequest(url: resolver.modelsURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let (data, response, duration) = try await client.request(request)
        guard (200..<300).contains(response.statusCode) else { throw Self.httpError(response, data: data) }
        let decoded: ModelListResponse
        do { decoded = try JSONDecoder().decode(ModelListResponse.self, from: data) } catch { throw APIError.invalidJSON("模型列表") }
        guard !decoded.data.isEmpty else { throw APIError.emptyModels }
        return (decoded.data.map { ModelInfo(id: $0.id, object: $0.object, latestTest: nil) }, duration, response.statusCode, .now)
    }

    static func httpError(_ response: HTTPURLResponse, data: Data) -> APIError {
        let message = serverMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
        return .http(status: response.statusCode, message: message, kind: response.errorKind(for: response.statusCode))
    }

    static func serverMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.flatMap { $0.isEmpty ? nil : String($0.prefix(240)) }
        }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return String(message.prefix(240)) }
        if let message = object["message"] as? String { return String(message.prefix(240)) }
        return nil
    }
}
