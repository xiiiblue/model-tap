import Foundation

enum Formatters {
    static func duration(_ value: TimeInterval) -> String { String(format: "%.0f ms", value * 1000) }
    static func tokens(_ usage: TokenUsage?) -> String? {
        guard let usage else { return nil }
        if let total = usage.totalTokens { return "\(total) tokens" }
        return [usage.promptTokens, usage.completionTokens].compactMap { $0 }.map(String.init).joined(separator: " + ").nilIfEmpty.map { "\($0) tokens" }
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
