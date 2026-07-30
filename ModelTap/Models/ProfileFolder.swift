import Foundation
import SwiftData

@Model
final class ProfileFolder {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int = 0

    init(id: UUID = UUID(), name: String, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
        self.sortOrder = sortOrder
    }
}

struct SidebarSortSnapshot {
    let folderIDs: [UUID]
    let groups: [SidebarProfileSortGroup]
}

struct SidebarProfileSortGroup {
    let folderID: UUID?
    let profileIDs: [UUID]
}
