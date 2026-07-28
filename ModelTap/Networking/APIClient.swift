import Foundation

protocol APIClienting: Sendable {
    func request(_ request: URLRequest) async throws -> (Data, HTTPURLResponse, TimeInterval)
}

struct URLSessionAPIClient: APIClienting {
    let session: URLSession
    var timeout: TimeInterval = 30

    init(session: URLSession = .shared) { self.session = session }

    func request(_ request: URLRequest) async throws -> (Data, HTTPURLResponse, TimeInterval) {
        var request = request
        request.timeoutInterval = timeout
        let start = ContinuousClock.now
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            let duration = start.duration(to: .now).timeInterval
            return (data, httpResponse, duration)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw APIError.cancelled
        } catch let error as URLError {
            throw APIError.network(error)
        }
    }
}

enum APIError: Error, LocalizedError, Equatable, Sendable {
    case invalidResponse
    case invalidJSON(String)
    case http(status: Int, message: String, kind: ErrorKind)
    case network(URLError)
    case cancelled
    case emptyModels
    case invalidModelOutput

    enum ErrorKind: String, Sendable {
        case url = "URL 配置"
        case authentication = "API Key"
        case network = "网络连接"
        case protocolError = "接口协议"
        case model = "模型"
        case server = "服务端"
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "服务返回了无法识别的响应。"
        case .invalidJSON(let context): return "服务返回的数据格式无法解析（\(context)）。"
        case .http(let status, let message, let kind): return "HTTP \(status) · \(kind.rawValue)：\(message)"
        case .network(let error): return Self.networkMessage(error)
        case .cancelled: return "请求已取消。"
        case .emptyModels: return "服务返回的模型列表为空。"
        case .invalidModelOutput: return "模型响应中没有可识别的有效输出。"
        }
    }

    private static func networkMessage(_ error: URLError) -> String {
        switch error.code {
        case .cannotFindHost, .dnsLookupFailed: return "无法解析服务地址，请检查 URL 或 DNS。"
        case .secureConnectionFailed, .serverCertificateUntrusted, .clientCertificateRejected: return "TLS 证书或安全连接失败，请检查服务端证书。"
        case .timedOut: return "请求超时，请检查网络连接和服务状态。"
        case .notConnectedToInternet, .networkConnectionLost: return "网络连接不可用或已中断。"
        default: return "网络请求失败：\(error.localizedDescription)"
        }
    }
}

extension HTTPURLResponse {
    func errorKind(for status: Int) -> APIError.ErrorKind {
        switch status {
        case 401, 403: return .authentication
        case 404, 405, 415: return .protocolError
        case 408, 502, 503, 504: return .network
        case 429: return .server
        case 400..<500: return .model
        default: return .server
        }
    }
}
