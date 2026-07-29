import Foundation
import SwiftData

enum FolderError: LocalizedError {
    case emptyName
    case duplicateName
    case reservedName

    var errorDescription: String? {
        switch self {
        case .emptyName: return "文件夹名称不能为空。"
        case .duplicateName: return "已存在同名文件夹。"
        case .reservedName: return "“未分类”和“测试记录”是系统保留名称，请使用其他名称。"
        }
    }
}

enum ProfileError: LocalizedError {
    case emptyName

    var errorDescription: String? {
        switch self {
        case .emptyName: return "配置名称不能为空。"
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
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ProfileError.emptyName }
        _ = try EndpointResolver(baseURLString: baseURL)
        let encryptedAPIKey = apiKey.isEmpty ? nil : try apiKeyCipher.encrypt(apiKey)
        let previousFolderID = profile?.folderID
        let isNewProfile = profile == nil
        let savedProfile: APIProfile
        if let existingProfile = profile {
            savedProfile = existingProfile
        } else {
            savedProfile = APIProfile(
                name: name,
                baseURL: baseURL,
                apiFormat: apiFormat,
                folderID: folderID,
                notes: notes,
                sortOrder: try nextProfileSortOrder(in: folderID)
            )
        }
        savedProfile.encryptedAPIKey = encryptedAPIKey
        savedProfile.keychainReference = nil
        savedProfile.name = name
        savedProfile.baseURL = baseURL
        savedProfile.apiFormat = apiFormat
        savedProfile.folderID = folderID
        if !isNewProfile, previousFolderID != folderID {
            savedProfile.sortOrder = try nextProfileSortOrder(
                in: folderID,
                excluding: savedProfile.id
            )
        }
        savedProfile.category = nil
        savedProfile.notes = notes
        savedProfile.updatedAt = .now
        if savedProfile.modelContext == nil { modelContext.insert(savedProfile) }
        if !isNewProfile, previousFolderID != folderID {
            try normalizeProfiles(in: previousFolderID, excluding: savedProfile.id)
        }
        try saveChanges()
        return savedProfile
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
        try saveChanges()
    }

    func duplicate(_ profile: APIProfile) throws -> APIProfile {
        let key = try apiKey(for: profile)
        let duplicate = try saveProfile(profile: nil, name: "\(profile.name) 副本", baseURL: profile.baseURL, apiKey: key, apiFormat: profile.apiFormat, folderID: profile.folderID, notes: profile.notes)
        duplicate.manualModelIDs = profile.manualModelIDs
        try saveChanges()
        return duplicate
    }

    func addManualModel(_ modelID: String, to profile: APIProfile) throws {
        guard !profile.manualModelIDs.contains(modelID) else { return }
        profile.manualModelIDs.append(modelID)
        profile.updatedAt = .now
        try saveChanges()
    }

    func removeManualModel(_ modelID: String, from profile: APIProfile) throws {
        profile.manualModelIDs.removeAll { $0 == modelID }
        profile.updatedAt = .now
        try saveChanges()
    }

    func createFolder(name: String) throws -> ProfileFolder {
        let name = try validatedFolderName(name, excluding: nil)
        let folder = ProfileFolder(
            name: name,
            sortOrder: try nextFolderSortOrder()
        )
        modelContext.insert(folder)
        try saveChanges()
        return folder
    }

    func renameFolder(_ folder: ProfileFolder, name: String) throws {
        folder.name = try validatedFolderName(name, excluding: folder.id)
        folder.updatedAt = .now
        try saveChanges()
    }

    func deleteFolder(_ folder: ProfileFolder) throws {
        let folderID = folder.id
        let descriptor = FetchDescriptor<APIProfile>(
            predicate: #Predicate { $0.folderID == folderID }
        )
        var nextOrder = try nextProfileSortOrder(in: nil)
        let folderProfiles = try modelContext.fetch(descriptor).sorted(by: profileComesBefore)
        for profile in folderProfiles {
            profile.folderID = nil
            profile.sortOrder = nextOrder
            nextOrder += 1
            profile.updatedAt = .now
        }
        modelContext.delete(folder)
        try saveChanges()
    }

    func move(_ profile: APIProfile, to folder: ProfileFolder?) throws {
        let previousFolderID = profile.folderID
        profile.folderID = folder?.id
        profile.sortOrder = try nextProfileSortOrder(
            in: folder?.id,
            excluding: profile.id
        )
        profile.updatedAt = .now
        try normalizeProfiles(in: previousFolderID, excluding: profile.id)
        try saveChanges()
    }

    func reorder(
        _ profile: APIProfile,
        relativeTo target: APIProfile,
        placeAfter: Bool
    ) throws {
        guard profile.id != target.id else { return }
        let previousFolderID = profile.folderID
        let destinationFolderID = target.folderID
        var destinationProfiles = try orderedProfiles(in: destinationFolderID)
            .filter { $0.id != profile.id }
        guard let targetIndex = destinationProfiles.firstIndex(where: {
            $0.id == target.id
        }) else { return }

        profile.folderID = destinationFolderID
        let insertionIndex = placeAfter ? targetIndex + 1 : targetIndex
        destinationProfiles.insert(profile, at: insertionIndex)
        for (index, item) in destinationProfiles.enumerated() {
            item.sortOrder = index
            item.updatedAt = .now
        }
        if previousFolderID != destinationFolderID {
            try normalizeProfiles(in: previousFolderID, excluding: profile.id)
        }
        try saveChanges()
    }

    func reorder(
        _ folder: ProfileFolder,
        relativeTo target: ProfileFolder,
        placeAfter: Bool
    ) throws {
        guard folder.id != target.id else { return }
        var ordered = try orderedFolders().filter { $0.id != folder.id }
        guard let targetIndex = ordered.firstIndex(where: {
            $0.id == target.id
        }) else { return }
        let insertionIndex = placeAfter ? targetIndex + 1 : targetIndex
        ordered.insert(folder, at: insertionIndex)
        for (index, item) in ordered.enumerated() {
            item.sortOrder = index
            item.updatedAt = .now
        }
        try saveChanges()
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
                folder = ProfileFolder(
                    name: category,
                    sortOrder: try nextFolderSortOrder()
                )
                modelContext.insert(folder)
                folders.append(folder)
            }
            profile.folderID = folder.id
            profile.sortOrder = try nextProfileSortOrder(
                in: folder.id,
                excluding: profile.id
            )
            profile.category = nil
        }
        try saveChanges()
    }

    func makeBackup() throws -> ModelTapBackup {
        let folders = try orderedFolders()
        let profiles = try modelContext.fetch(FetchDescriptor<APIProfile>())
            .sorted(by: profileComesBefore)
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
                    manualModelIDs: $0.manualModelIDs,
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

        for (folderIndex, item) in backup.folders.enumerated() {
            let folder = foldersByID.removeValue(forKey: item.id)
                ?? ProfileFolder(id: item.id, name: item.name)
            folder.name = item.name
            folder.createdAt = item.createdAt
            folder.updatedAt = item.updatedAt
            folder.sortOrder = folderIndex
            if folder.modelContext == nil {
                modelContext.insert(folder)
            }
        }

        var profileOrderByFolder: [UUID?: Int] = [:]
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
            profile.manualModelIDs = item.manualModelIDs ?? []
            profile.sortOrder = profileOrderByFolder[item.folderID, default: 0]
            profileOrderByFolder[item.folderID, default: 0] += 1
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
        try saveChanges()
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
        try saveChanges()
    }

    private func validatedFolderName(_ value: String, excluding folderID: UUID?) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FolderError.emptyName }
        guard !["未分类", "测试记录"].contains(name) else {
            throw FolderError.reservedName
        }
        let folders = try modelContext.fetch(FetchDescriptor<ProfileFolder>())
        let duplicate = folders.contains {
            $0.id != folderID
                && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        guard !duplicate else { throw FolderError.duplicateName }
        return name
    }

    private func saveChanges() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func orderedFolders() throws -> [ProfileFolder] {
        try modelContext.fetch(FetchDescriptor<ProfileFolder>())
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private func orderedProfiles(in folderID: UUID?) throws -> [APIProfile] {
        try modelContext.fetch(FetchDescriptor<APIProfile>())
            .filter { $0.folderID == folderID }
            .sorted(by: profileComesBefore)
    }

    private func profileComesBefore(_ lhs: APIProfile, _ rhs: APIProfile) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func nextFolderSortOrder() throws -> Int {
        (try modelContext.fetch(FetchDescriptor<ProfileFolder>())
            .map(\.sortOrder)
            .max() ?? -1) + 1
    }

    private func nextProfileSortOrder(
        in folderID: UUID?,
        excluding profileID: UUID? = nil
    ) throws -> Int {
        let orders = try modelContext.fetch(FetchDescriptor<APIProfile>())
            .filter { profile in
                profile.folderID == folderID
                    && (profileID.map { profile.id != $0 } ?? true)
            }
            .map(\.sortOrder)
        return (orders.max() ?? -1) + 1
    }

    private func normalizeProfiles(
        in folderID: UUID?,
        excluding profileID: UUID? = nil
    ) throws {
        let values = try orderedProfiles(in: folderID)
            .filter { $0.id != profileID }
        for (index, profile) in values.enumerated() {
            profile.sortOrder = index
        }
    }
}
