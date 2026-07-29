import Foundation

struct ModelListResponse: Decodable, Sendable {
    let object: String?
    let data: [RemoteModel]
}

struct RemoteModel: Decodable, Sendable {
    let id: String
    let object: String?

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        object = try container.decodeIfPresent(String.self, forKey: .object)
            ?? container.decodeIfPresent(String.self, forKey: .type)
    }
}

struct ModelDiscoveryService: Sendable {
    let client: APIClienting

    func discover(baseURL: String, apiKey: String, format: APIFormat) async throws -> (models: [ModelInfo], duration: TimeInterval, statusCode: Int, testedAt: Date) {
        let resolver = try EndpointResolver(baseURLString: baseURL)
        var request = URLRequest(url: resolver.modelsURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        addAuthentication(to: &request, apiKey: apiKey, format: format)
        let (data, response, duration) = try await client.request(request)
        guard (200..<300).contains(response.statusCode) else { throw Self.httpError(response, data: data) }
        let decoded: ModelListResponse
        do { decoded = try JSONDecoder().decode(ModelListResponse.self, from: data) } catch { throw APIError.invalidJSON("模型列表") }
        var seenModelIDs: Set<String> = []
        let models = decoded.data
            .filter { seenModelIDs.insert($0.id).inserted }
            .map { ModelInfo(id: $0.id, object: $0.object, latestTest: nil) }
        guard !models.isEmpty else { throw APIError.emptyModels }
        return (models, duration, response.statusCode, .now)
    }

    private func addAuthentication(to request: inout URLRequest, apiKey: String, format: APIFormat) {
        switch format {
        case .openAI, .openAIResponses:
            if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        case .anthropic:
            if !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "x-api-key") }
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
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
