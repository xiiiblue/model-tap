import Foundation

enum EndpointResolverError: LocalizedError, Equatable {
    case invalidURL
    case unsupportedScheme

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Base URL 为空或格式无效。"
        case .unsupportedScheme: return "Base URL 必须使用 http 或 https。"
        }
    }
}

struct EndpointResolver: Sendable {
    let baseURL: URL

    init(baseURLString: String) throws {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme), components.host != nil else {
            if let components = URLComponents(string: trimmed), components.scheme != nil { throw EndpointResolverError.unsupportedScheme }
            throw EndpointResolverError.invalidURL
        }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = components.path
        let suffixes = ["/chat/completions", "/responses", "/models"]
        for suffix in suffixes where path.lowercased().hasSuffix(suffix) {
            components.path = String(path.dropLast(suffix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            break
        }
        components.query = nil
        components.fragment = nil
        let normalizedPath = components.path.isEmpty ? "" : "/\(components.path)"
        let urlString = "\(scheme)://\(components.host!)\(components.port.map { ":\($0)" } ?? "")\(normalizedPath)"
        guard let url = URL(string: urlString) else { throw EndpointResolverError.invalidURL }
        self.baseURL = url
    }

    func endpoint(_ path: String) -> URL {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return baseURL.appending(path: cleanPath)
    }

    var modelsURL: URL { endpoint("models") }
    var chatCompletionsURL: URL { endpoint("chat/completions") }
    var responsesURL: URL { endpoint("responses") }
}
