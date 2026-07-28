import Foundation
import SwiftData

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

    func saveProfile(profile: APIProfile?, name: String, baseURL: String, apiKey: String, apiFormat: APIFormat, category: String, notes: String) throws -> APIProfile {
        let profile = profile ?? APIProfile(name: name, baseURL: baseURL, apiFormat: apiFormat, category: category, notes: notes)
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.encryptedAPIKey = apiKey.isEmpty ? nil : try apiKeyCipher.encrypt(apiKey)
        profile.keychainReference = nil
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.apiFormat = apiFormat
        profile.category = trimmedCategory.isEmpty ? nil : trimmedCategory
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
        return try saveProfile(profile: nil, name: "\(profile.name) 副本", baseURL: profile.baseURL, apiKey: key, apiFormat: profile.apiFormat, category: profile.category ?? "", notes: profile.notes)
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
}
