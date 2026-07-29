import Foundation
import SwiftData

enum FolderError: LocalizedError {
    case emptyName
    case duplicateName

    var errorDescription: String? {
        switch self {
        case .emptyName: return "文件夹名称不能为空。"
        case .duplicateName: return "已存在同名文件夹。"
        }
    }
}

@MainActor
final class ProfileRepository {
    private let modelContext: ModelContext
    private let apiKeyCipher: any APIKeyEncrypting

    init(
        modelContext: ModelContext,
        apiKeyCipher: any APIKeyEncrypting = LocalAPIKeyCipher()
    ) {
        self.modelContext = modelContext
        self.apiKeyCipher = apiKeyCipher
    }

    func saveProfile(profile: APIProfile?, name: String, baseURL: String, apiKey: String, apiFormat: APIFormat, folderID: UUID?, notes: String) throws -> APIProfile {
        let profile = profile ?? APIProfile(name: name, baseURL: baseURL, apiFormat: apiFormat, folderID: folderID, notes: notes)
        profile.encryptedAPIKey = apiKey.isEmpty ? nil : try apiKeyCipher.encrypt(apiKey)
        profile.keychainReference = nil
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.apiFormat = apiFormat
        profile.folderID = folderID
        profile.category = nil
        profile.notes = notes
        profile.updatedAt = .now
        if profile.modelContext == nil { modelContext.insert(profile) }
        try modelContext.save()
        return profile
    }

    func apiKey(for profile: APIProfile) throws -> String {
        guard let encryptedAPIKey = profile.encryptedAPIKey else { return "" }
        return try apiKeyCipher.decrypt(encryptedAPIKey)
    }

    func delete(_ profile: APIProfile) throws {
        let profileID = profile.id
        let descriptor = FetchDescriptor<ModelTestRecord>(predicate: #Predicate { $0.profileID == profileID })
        for record in try modelContext.fetch(descriptor) { modelContext.delete(record) }
        modelContext.delete(profile)
        try modelContext.save()
    }

    func duplicate(_ profile: APIProfile) throws -> APIProfile {
        let key = try apiKey(for: profile)
        return try saveProfile(profile: nil, name: "\(profile.name) 副本", baseURL: profile.baseURL, apiKey: key, apiFormat: profile.apiFormat, folderID: profile.folderID, notes: profile.notes)
    }

    func createFolder(name: String) throws -> ProfileFolder {
        let name = try validatedFolderName(name, excluding: nil)
        let folder = ProfileFolder(name: name)
        modelContext.insert(folder)
        try modelContext.save()
        return folder
    }

    func renameFolder(_ folder: ProfileFolder, name: String) throws {
        folder.name = try validatedFolderName(name, excluding: folder.id)
        folder.updatedAt = .now
        try modelContext.save()
    }

    func deleteFolder(_ folder: ProfileFolder) throws {
        let folderID = folder.id
        let descriptor = FetchDescriptor<APIProfile>(
            predicate: #Predicate { $0.folderID == folderID }
        )
        for profile in try modelContext.fetch(descriptor) {
            profile.folderID = nil
            profile.updatedAt = .now
        }
        modelContext.delete(folder)
        try modelContext.save()
    }

    func move(_ profile: APIProfile, to folder: ProfileFolder?) throws {
        profile.folderID = folder?.id
        profile.updatedAt = .now
        try modelContext.save()
    }

    func migrateLegacyCategories() throws {
        let profiles = try modelContext.fetch(FetchDescriptor<APIProfile>())
        let legacyProfiles = profiles.filter {
            $0.folderID == nil
                && !($0.category?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        guard !legacyProfiles.isEmpty else { return }

        var folders = try modelContext.fetch(FetchDescriptor<ProfileFolder>())
        for profile in legacyProfiles {
            guard let category = profile.category?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !category.isEmpty else { continue }
            let folder: ProfileFolder
            if let existing = folders.first(where: {
                $0.name.localizedCaseInsensitiveCompare(category) == .orderedSame
            }) {
                folder = existing
            } else {
                folder = ProfileFolder(name: category)
                modelContext.insert(folder)
                folders.append(folder)
            }
            profile.folderID = folder.id
            profile.category = nil
        }
        try modelContext.save()
    }

    func saveTestRecord(_ summary: ModelTestSummary, modelID: String, profile: APIProfile) throws {
        let record = ModelTestRecord(profileID: profile.id, modelID: modelID, success: summary.success, statusCode: summary.statusCode, duration: summary.duration, protocolName: summary.protocolName, errorSummary: summary.errorSummary)
        modelContext.insert(record)
        profile.lastTestStatusRaw = summary.success ? ProfileTestStatus.success.rawValue : ProfileTestStatus.failure.rawValue
        profile.updatedAt = .now
        let profileID = profile.id
        let descriptor = FetchDescriptor<ModelTestRecord>(predicate: #Predicate { $0.profileID == profileID }, sortBy: [SortDescriptor(\ModelTestRecord.testedAt, order: .reverse)])
        let records = try modelContext.fetch(descriptor)
        if records.count > 100 { records.dropFirst(100).forEach(modelContext.delete) }
        try modelContext.save()
    }

    private func validatedFolderName(_ value: String, excluding folderID: UUID?) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FolderError.emptyName }
        let folders = try modelContext.fetch(FetchDescriptor<ProfileFolder>())
        let duplicate = folders.contains {
            $0.id != folderID
                && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        guard !duplicate else { throw FolderError.duplicateName }
        return name
    }
}
