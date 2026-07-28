import Foundation
import SwiftData

@Model
final class ModelTestRecord {
    @Attribute(.unique) var id: UUID
    var profileID: UUID
    var modelID: String
    var testedAt: Date
    var success: Bool
    var statusCode: Int?
    var duration: TimeInterval
    var protocolNameRaw: String?
    var errorSummary: String?

    init(profileID: UUID, modelID: String, testedAt: Date = .now, success: Bool, statusCode: Int?, duration: TimeInterval, protocolName: APIProtocolName?, errorSummary: String?) {
        self.id = UUID()
        self.profileID = profileID
        self.modelID = modelID
        self.testedAt = testedAt
        self.success = success
        self.statusCode = statusCode
        self.duration = duration
        self.protocolNameRaw = protocolName?.rawValue
        self.errorSummary = errorSummary
    }

    var protocolName: APIProtocolName? {
        guard let protocolNameRaw else { return nil }
        return APIProtocolName(rawValue: protocolNameRaw)
    }
}
