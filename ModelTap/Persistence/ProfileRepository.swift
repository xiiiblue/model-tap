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

    func makeBackup() throws -> ModelTapBackup {
        let folders = try modelContext.fetch(
            FetchDescriptor<ProfileFolder>(
                sortBy: [SortDescriptor(\ProfileFolder.name)]
            )
        )
        let profiles = try modelContext.fetch(
            FetchDescriptor<APIProfile>(
                sortBy: [SortDescriptor(\APIProfile.createdAt)]
            )
        )
        let records = try modelContext.fetch(
            FetchDescriptor<ModelTestRecord>(
                sortBy: [SortDescriptor(\ModelTestRecord.testedAt)]
            )
        )

        return ModelTapBackup(
            formatVersion: ModelTapBackup.currentVersion,
            exportedAt: .now,
            folders: folders.map {
                ModelTapBackup.Folder(
                    id: $0.id,
                    name: $0.name,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            profiles: try profiles.map {
                ModelTapBackup.Profile(
                    id: $0.id,
                    name: $0.name,
                    baseURL: $0.baseURL,
                    apiKey: try apiKey(for: $0),
                    apiFormat: $0.apiFormat.rawValue,
                    folderID: $0.folderID,
                    notes: $0.notes,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    lastUsedAt: $0.lastUsedAt,
                    lastTestStatus: $0.lastTestStatusRaw
                )
            },
            testRecords: records.map {
                ModelTapBackup.TestRecord(
                    id: $0.id,
                    profileID: $0.profileID,
                    modelID: $0.modelID,
                    testedAt: $0.testedAt,
                    success: $0.success,
                    statusCode: $0.statusCode,
                    duration: $0.duration,
                    protocolName: $0.protocolNameRaw,
                    errorSummary: $0.errorSummary
                )
            }
        )
    }

    func replaceAll(with backup: ModelTapBackup) throws {
        try MarkdownBackupCodec.validate(backup)

        var encryptedKeys: [UUID: Data] = [:]
        for profile in backup.profiles where !profile.apiKey.isEmpty {
            encryptedKeys[profile.id] = try apiKeyCipher.encrypt(profile.apiKey)
        }

        let existingFolders = try modelContext.fetch(FetchDescriptor<ProfileFolder>())
        let existingProfiles = try modelContext.fetch(FetchDescriptor<APIProfile>())
        let existingRecords = try modelContext.fetch(FetchDescriptor<ModelTestRecord>())
        var foldersByID = Dictionary(
            uniqueKeysWithValues: existingFolders.map { ($0.id, $0) }
        )
        var profilesByID = Dictionary(
            uniqueKeysWithValues: existingProfiles.map { ($0.id, $0) }
        )
        var recordsByID = Dictionary(
            uniqueKeysWithValues: existingRecords.map { ($0.id, $0) }
        )

        for item in backup.folders {
            let folder = foldersByID.removeValue(forKey: item.id)
                ?? ProfileFolder(id: item.id, name: item.name)
            folder.name = item.name
            folder.createdAt = item.createdAt
            folder.updatedAt = item.updatedAt
            if folder.modelContext == nil {
                modelContext.insert(folder)
            }
        }

        for item in backup.profiles {
            let profile = profilesByID.removeValue(forKey: item.id)
                ?? APIProfile(
                    id: item.id,
                    name: item.name,
                    baseURL: item.baseURL
                )
            profile.name = item.name
            profile.baseURL = item.baseURL
            profile.apiFormatRaw = item.apiFormat
            profile.folderID = item.folderID
            profile.notes = item.notes
            profile.createdAt = item.createdAt
            profile.updatedAt = item.updatedAt
            profile.lastUsedAt = item.lastUsedAt
            profile.lastTestStatusRaw = item.lastTestStatus
            profile.encryptedAPIKey = encryptedKeys[item.id]
            profile.keychainReference = nil
            profile.category = nil
            if profile.modelContext == nil {
                modelContext.insert(profile)
            }
        }

        for item in backup.testRecords {
            let record = recordsByID.removeValue(forKey: item.id)
                ?? ModelTestRecord(
                    profileID: item.profileID,
                    modelID: item.modelID,
                    testedAt: item.testedAt,
                    success: item.success,
                    statusCode: item.statusCode,
                    duration: item.duration,
                    protocolName: item.protocolName.flatMap {
                        APIProtocolName(rawValue: $0)
                    },
                    errorSummary: item.errorSummary
                )
            record.id = item.id
            record.profileID = item.profileID
            record.modelID = item.modelID
            record.testedAt = item.testedAt
            record.success = item.success
            record.statusCode = item.statusCode
            record.duration = item.duration
            record.protocolNameRaw = item.protocolName
            record.errorSummary = item.errorSummary
            if record.modelContext == nil {
                modelContext.insert(record)
            }
        }

        recordsByID.values.forEach(modelContext.delete)
        profilesByID.values.forEach(modelContext.delete)
        foldersByID.values.forEach(modelContext.delete)
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
