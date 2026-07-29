import Foundation
import SwiftData

@Model
final class ProfileFolder {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
    }
}
