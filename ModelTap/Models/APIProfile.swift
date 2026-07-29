import Foundation
import SwiftData

enum ProfileTestStatus: String, Codable, CaseIterable {
    case notTested
    case success
    case failure

    var title: String {
        switch self {
        case .notTested: return "未测试"
        case .success: return "可用"
        case .failure: return "失败"
        }
    }
}

enum APIFormat: String, Codable, CaseIterable, Hashable, Sendable {
    case openAI = "openai"
    case openAIResponses = "openai-response"
    case anthropic = "anthropic"

    var title: String {
        switch self {
        case .openAI: return "OpenAI Chat Completions"
        case .openAIResponses: return "OpenAI Responses"
        case .anthropic: return "Anthropic Messages"
        }
    }
}

@Model
final class APIProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var baseURL: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var lastTestStatusRaw: String
    var encryptedAPIKey: Data?
    // 仅为兼容旧版SwiftData结构保留；新代码不会访问macOS Keychain。
    var keychainReference: String?
    var apiFormatRaw: String = APIFormat.openAI.rawValue
    var folderID: UUID?
    var manualModelIDsRaw: String = ""
    // 仅用于将上一版文本分类迁移为文件夹。
    var category: String?

    init(id: UUID = UUID(), name: String, baseURL: String, apiFormat: APIFormat = .openAI, folderID: UUID? = nil, notes: String = "") {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.notes = notes
        self.createdAt = .now
        self.updatedAt = .now
        self.lastUsedAt = nil
        self.lastTestStatusRaw = ProfileTestStatus.notTested.rawValue
        self.encryptedAPIKey = nil
        self.keychainReference = nil
        self.apiFormatRaw = apiFormat.rawValue
        self.folderID = folderID
        self.manualModelIDsRaw = ""
        self.category = nil
    }

    var testStatus: ProfileTestStatus {
        get { ProfileTestStatus(rawValue: lastTestStatusRaw) ?? .notTested }
        set { lastTestStatusRaw = newValue.rawValue }
    }

    var apiFormat: APIFormat {
        get { APIFormat(rawValue: apiFormatRaw) ?? .openAI }
        set { apiFormatRaw = newValue.rawValue }
    }

    var manualModelIDs: [String] {
        get {
            let values = manualModelIDsRaw
                .split(separator: "\n")
                .map(String.init)
            var seen: Set<String> = []
            return values.filter { seen.insert($0).inserted }
        }
        set {
            var seen: Set<String> = []
            manualModelIDsRaw = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
                .joined(separator: "\n")
        }
    }
}
