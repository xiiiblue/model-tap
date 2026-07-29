import Foundation

enum Redaction {
    static func apiKey(_ key: String?) -> String {
        guard let key, !key.isEmpty else { return "（未设置）" }
        guard key.count > 8 else { return String(repeating: "•", count: max(1, key.count)) }
        return "\(key.prefix(4))••••••••\(key.suffix(4))"
    }

    static func sensitive(_ text: String, apiKey: String?) -> String {
        guard let apiKey, !apiKey.isEmpty else { return text }
        return text.replacingOccurrences(of: apiKey, with: Redaction.apiKey(apiKey))
    }
}

extension Date {
    var modelTapTimestamp: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: self)
    }
}
