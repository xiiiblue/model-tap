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
    var keychainReference: String?

    init(id: UUID = UUID(), name: String, baseURL: String, notes: String = "", keychainReference: String? = nil) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.notes = notes
        self.createdAt = .now
        self.updatedAt = .now
        self.lastUsedAt = nil
        self.lastTestStatusRaw = ProfileTestStatus.notTested.rawValue
        self.keychainReference = keychainReference
    }

    var testStatus: ProfileTestStatus {
        get { ProfileTestStatus(rawValue: lastTestStatusRaw) ?? .notTested }
        set { lastTestStatusRaw = newValue.rawValue }
    }
}
