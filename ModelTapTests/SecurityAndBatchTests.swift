import Foundation
import SwiftData
import XCTest
@testable import ModelTap

final class SecurityAndBatchTests: XCTestCase {
    func testRedaction() {
        XCTAssertEqual(Redaction.apiKey("sk-1234567890abcd"), "sk-1••••••••abcd")
        XCTAssertFalse(Redaction.sensitive("Bearer sk-1234567890abcd", apiKey: "sk-1234567890abcd").contains("sk-1234567890abcd"))
    }

    func testTimestampFormat() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = 2026
        components.month = 7
        components.day = 29
        components.hour = 13
        components.minute = 33
        components.second = 33

        let date = try XCTUnwrap(components.date)

        XCTAssertEqual(date.modelTapTimestamp, "2026-07-29 13:33:33")
    }

    func testLocalAPIKeyCipherRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cipher = LocalAPIKeyCipher(
            keyURL: directory.appendingPathComponent("local-encryption.key")
        )

        let encrypted = try cipher.encrypt("sk-fake")

        XCTAssertNotEqual(encrypted, Data("sk-fake".utf8))
        XCTAssertEqual(try cipher.decrypt(encrypted), "sk-fake")
        let directoryPermissions = try FileManager.default.attributesOfItem(
            atPath: directory.path
        )[.posixPermissions] as? NSNumber
        let keyPermissions = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent("local-encryption.key").path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(
            directoryPermissions.map { $0.intValue & 0o777 },
            0o700
        )
        XCTAssertEqual(
            keyPermissions.map { $0.intValue & 0o777 },
            0o600
        )
    }

    @MainActor func testRepositoryStoresEncryptedAPIKey() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: APIProfile.self,
            ProfileFolder.self,
            ModelTestRecord.self,
            configurations: configuration
        )
        let cipher = TestAPIKeyCipher()
        let repository = ProfileRepository(
            modelContext: container.mainContext,
            apiKeyCipher: cipher
        )
        let folder = try repository.createFolder(name: "开发环境")
        let profile = try repository.saveProfile(
            profile: nil,
            name: "测试配置",
            baseURL: "https://example.test/v1",
            apiKey: "sk-fake",
            apiFormat: .openAI,
            folderID: folder.id,
            notes: ""
        )

        XCTAssertEqual(try repository.apiKey(for: profile), "sk-fake")
        XCTAssertEqual(profile.encryptedAPIKey, Data("encrypted:sk-fake".utf8))
        XCTAssertNil(profile.keychainReference)
        XCTAssertEqual(profile.folderID, folder.id)

        try repository.addManualModel("gpt-manual", to: profile)
        try repository.addManualModel("gpt-manual", to: profile)
        XCTAssertEqual(profile.manualModelIDs, ["gpt-manual"])

        try repository.removeManualModel("gpt-manual", from: profile)
        XCTAssertTrue(profile.manualModelIDs.isEmpty)

        try repository.renameFolder(folder, name: "测试环境")
        XCTAssertEqual(folder.name, "测试环境")

        try repository.deleteFolder(folder)
        XCTAssertNil(profile.folderID)
    }

    @MainActor func testRepositoryRejectsInvalidProfileFieldsAndReservedFolderNames() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: APIProfile.self,
            ProfileFolder.self,
            ModelTestRecord.self,
            configurations: configuration
        )
        let repository = ProfileRepository(
            modelContext: container.mainContext,
            apiKeyCipher: TestAPIKeyCipher()
        )

        XCTAssertThrowsError(
            try repository.saveProfile(
                profile: nil,
                name: " ",
                baseURL: "https://example.test/v1",
                apiKey: "",
                apiFormat: .openAI,
                folderID: nil,
                notes: ""
            )
        )
        XCTAssertThrowsError(
            try repository.saveProfile(
                profile: nil,
                name: "测试",
                baseURL: "ftp://example.test",
                apiKey: "",
                apiFormat: .openAI,
                folderID: nil,
                notes: ""
            )
        )
        XCTAssertThrowsError(try repository.createFolder(name: "未分类"))
        XCTAssertThrowsError(try repository.createFolder(name: "测试记录"))
    }

    @MainActor func testRepositoryPersistsFolderAndProfileReordering() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: APIProfile.self,
            ProfileFolder.self,
            ModelTestRecord.self,
            configurations: configuration
        )
        let repository = ProfileRepository(
            modelContext: container.mainContext,
            apiKeyCipher: TestAPIKeyCipher()
        )
        let firstFolder = try repository.createFolder(name: "文件夹A")
        let secondFolder = try repository.createFolder(name: "文件夹B")
        let firstProfile = try repository.saveProfile(
            profile: nil,
            name: "配置A",
            baseURL: "https://a.example.test/v1",
            apiKey: "",
            apiFormat: .openAI,
            folderID: firstFolder.id,
            notes: ""
        )
        let secondProfile = try repository.saveProfile(
            profile: nil,
            name: "配置B",
            baseURL: "https://b.example.test/v1",
            apiKey: "",
            apiFormat: .openAI,
            folderID: firstFolder.id,
            notes: ""
        )

        try repository.reorder(secondFolder, relativeTo: firstFolder, placeAfter: false)
        XCTAssertLessThan(secondFolder.sortOrder, firstFolder.sortOrder)

        try repository.reorder(secondProfile, relativeTo: firstProfile, placeAfter: false)
        XCTAssertEqual(secondProfile.folderID, firstFolder.id)
        XCTAssertLessThan(secondProfile.sortOrder, firstProfile.sortOrder)

        try repository.move(firstProfile, to: secondFolder)
        XCTAssertEqual(firstProfile.folderID, secondFolder.id)
        XCTAssertEqual(firstProfile.sortOrder, 0)
    }

    func testMarkdownBackupRoundTripKeepsAllConfigurationFields() throws {
        let folderID = UUID()
        let profileID = UUID()
        let recordID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let backup = ModelTapBackup(
            formatVersion: ModelTapBackup.currentVersion,
            exportedAt: date,
            folders: [
                .init(
                    id: folderID,
                    name: "生产环境",
                    createdAt: date,
                    updatedAt: date
                )
            ],
            profiles: [
                .init(
                    id: profileID,
                    name: "主配置",
                    baseURL: "https://example.test/v1",
                    apiKey: "sk-`特殊字符`",
                    apiFormat: APIFormat.openAIResponses.rawValue,
                    folderID: folderID,
                    notes: "第一行\n第二行",
                    manualModelIDs: ["gpt-manual", "claude-manual"],
                    createdAt: date,
                    updatedAt: date,
                    lastUsedAt: date,
                    lastTestStatus: ProfileTestStatus.success.rawValue
                )
            ],
            testRecords: [
                .init(
                    id: recordID,
                    profileID: profileID,
                    modelID: "gpt-example",
                    testedAt: date,
                    success: true,
                    statusCode: 200,
                    duration: 0.25,
                    protocolName: APIProtocolName.responses.rawValue,
                    errorSummary: nil
                )
            ]
        )

        let markdown = try MarkdownBackupCodec.encode(backup)
        let decoded = try MarkdownBackupCodec.decode(markdown)

        XCTAssertTrue(markdown.contains("明文API Key"))
        XCTAssertTrue(markdown.contains("## 生产环境"))
        XCTAssertTrue(markdown.contains("### 主配置"))
        XCTAssertTrue(markdown.contains("BASE_URL: https://example.test/v1"))
        XCTAssertFalse(markdown.contains("[https://example.test/v1]"))
        XCTAssertTrue(markdown.contains("API_KEY: sk-`特殊字符`"))
        XCTAssertTrue(markdown.contains("API格式: OpenAI Responses"))
        XCTAssertTrue(markdown.contains("> 第一行\n> 第二行"))
        XCTAssertTrue(markdown.contains("手动模型:\n- gpt-manual\n- claude-manual"))
        XCTAssertFalse(markdown.contains("- `profile`"))
        XCTAssertFalse(markdown.contains("modeltap-folder-meta"))
        XCTAssertFalse(markdown.contains("modeltap-profile-meta"))
        XCTAssertFalse(markdown.contains("导出时间:"))
        XCTAssertFalse(markdown.contains("## 测试记录"))
        XCTAssertEqual(decoded.folders.first?.name, "生产环境")
        XCTAssertEqual(decoded.profiles.first?.apiKey, "sk-`特殊字符`")
        XCTAssertEqual(decoded.profiles.first?.notes, "第一行\n第二行")
        XCTAssertEqual(decoded.profiles.first?.apiFormat, "openai-response")
        XCTAssertEqual(
            decoded.profiles.first?.manualModelIDs,
            ["gpt-manual", "claude-manual"]
        )
        XCTAssertTrue(decoded.testRecords.isEmpty)
    }

    func testReadableBackupHandlesReservedFolderNamesAndTrimmedEmptyAPIKey() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let unfiledNameFolderID = UUID()
        let recordsNameFolderID = UUID()
        let backup = ModelTapBackup(
            formatVersion: ModelTapBackup.currentVersion,
            exportedAt: date,
            folders: [
                .init(
                    id: unfiledNameFolderID,
                    name: "未分类",
                    createdAt: date,
                    updatedAt: date
                ),
                .init(
                    id: recordsNameFolderID,
                    name: "测试记录",
                    createdAt: date,
                    updatedAt: date
                )
            ],
            profiles: [
                makeBackupProfile(
                    name: "配置A",
                    folderID: unfiledNameFolderID,
                    date: date
                ),
                makeBackupProfile(
                    name: "配置B",
                    folderID: recordsNameFolderID,
                    date: date
                )
            ],
            testRecords: []
        )

        let markdown = try MarkdownBackupCodec.encode(backup)
            .replacingOccurrences(of: "API_KEY: \n", with: "API_KEY:\n")
        let decoded = try MarkdownBackupCodec.decode(markdown)
        let foldersByName = Dictionary(
            uniqueKeysWithValues: decoded.folders.map { ($0.name, $0.id) }
        )

        XCTAssertTrue(markdown.contains("## **未分类**"))
        XCTAssertTrue(markdown.contains("## **测试记录**"))
        XCTAssertEqual(
            decoded.profiles.first { $0.name == "配置A" }?.folderID,
            foldersByName["未分类"]
        )
        XCTAssertEqual(
            decoded.profiles.first { $0.name == "配置B" }?.folderID,
            foldersByName["测试记录"]
        )
        XCTAssertTrue(decoded.profiles.allSatisfy { $0.apiKey.isEmpty })

        let legacyUnescapedRecordsFolder = markdown.replacingOccurrences(
            of: "## **测试记录**",
            with: "## 测试记录"
        )
        let decodedLegacy = try MarkdownBackupCodec.decode(
            legacyUnescapedRecordsFolder
        )
        XCTAssertEqual(
            decodedLegacy.profiles.first { $0.name == "配置B" }?.folderID,
            decodedLegacy.folders.first { $0.name == "测试记录" }?.id
        )
    }

    func testReadableBackupCanRoundTripAnEmptyConfigurationSet() throws {
        let backup = ModelTapBackup(
            formatVersion: ModelTapBackup.currentVersion,
            exportedAt: .now,
            folders: [],
            profiles: [],
            testRecords: []
        )

        let decoded = try MarkdownBackupCodec.decode(
            MarkdownBackupCodec.encode(backup)
        )

        XCTAssertTrue(decoded.folders.isEmpty)
        XCTAssertTrue(decoded.profiles.isEmpty)
        XCTAssertTrue(decoded.testRecords.isEmpty)
    }

    func testMarkdownBackupCanImportLegacyVersionOne() throws {
        let folder = ModelTapBackup.Folder(
            id: UUID(),
            name: "旧备份",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let folderJSON = String(decoding: try encoder.encode(folder), as: UTF8.self)
        let markdown = """
        # ModelTap全量备份
        <!-- modeltap-backup-version: 1 -->
        ## 文件夹
        - `folder` \(folderJSON)
        """

        let decoded = try MarkdownBackupCodec.decode(markdown)

        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(decoded.folders.first?.id, folder.id)
    }

    func testLegacyDefaultStoreIsCopiedToModelTapDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyURL = root.appendingPathComponent("default.store")
        try Data("SQLite data ZAPIPROFILE".utf8).write(to: legacyURL)

        let storeURL = try PersistentStoreBootstrap.prepareStoreURL(
            applicationSupportDirectory: root
        )

        XCTAssertEqual(
            storeURL.lastPathComponent,
            PersistentStoreBootstrap.storeFileName
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
    }

    @MainActor func testModelKeepsLoadingStateWhileRequestIsRunning() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: APIProfile.self,
            ProfileFolder.self,
            ModelTestRecord.self,
            configurations: configuration
        )
        let viewModel = ContentViewModel(
            modelContext: container.mainContext,
            apiKeyCipher: TestAPIKeyCipher(),
            client: DelayedAPIClient(delayNanoseconds: 250_000_000)
        )
        let profile = try viewModel.repository.saveProfile(
            profile: nil,
            name: "测试配置",
            baseURL: "https://example.test/v1",
            apiKey: "",
            apiFormat: .openAI,
            folderID: nil,
            notes: ""
        )
        viewModel.selectedProfile = profile
        viewModel.models = [ModelInfo(id: "gpt-example", object: "model", latestTest: nil)]

        viewModel.test(modelID: "gpt-example")
        await Task.yield()

        XCTAssertTrue(viewModel.testingModelIDs.contains("gpt-example"))

        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertFalse(viewModel.testingModelIDs.contains("gpt-example"))
        XCTAssertTrue(viewModel.models.first?.latestTest?.success == true)
    }

    @MainActor func testSwitchingProfilePreventsCancelledTestFromWritingBack() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: APIProfile.self,
            ProfileFolder.self,
            ModelTestRecord.self,
            configurations: configuration
        )
        let viewModel = ContentViewModel(
            modelContext: container.mainContext,
            apiKeyCipher: TestAPIKeyCipher(),
            client: DelayedAPIClient(delayNanoseconds: 250_000_000)
        )
        let firstProfile = try viewModel.repository.saveProfile(
            profile: nil,
            name: "配置A",
            baseURL: "https://example.test/v1",
            apiKey: "",
            apiFormat: .openAI,
            folderID: nil,
            notes: ""
        )
        let secondProfile = try viewModel.repository.saveProfile(
            profile: nil,
            name: "配置B",
            baseURL: "https://example.test/v1",
            apiKey: "",
            apiFormat: .openAI,
            folderID: nil,
            notes: ""
        )
        try viewModel.repository.addManualModel("gpt-example", to: secondProfile)
        viewModel.selectedProfile = firstProfile
        viewModel.models = [
            ModelInfo(id: "gpt-example", object: "model", latestTest: nil)
        ]

        viewModel.test(modelID: "gpt-example")
        await Task.yield()
        viewModel.selectedProfile = secondProfile
        viewModel.selectedProfileDidChange()
        try await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertEqual(viewModel.models.map(\.id), ["gpt-example"])
        XCTAssertNil(viewModel.models.first?.latestTest)
        XCTAssertNil(viewModel.selectedSummary)
        XCTAssertTrue(
            try container.mainContext.fetch(FetchDescriptor<ModelTestRecord>()).isEmpty
        )
    }
}

private func makeBackupProfile(
    name: String,
    folderID: UUID?,
    date: Date
) -> ModelTapBackup.Profile {
    .init(
        id: UUID(),
        name: name,
        baseURL: "https://example.test/v1",
        apiKey: "",
        apiFormat: APIFormat.openAI.rawValue,
        folderID: folderID,
        notes: "",
        manualModelIDs: [],
        createdAt: date,
        updatedAt: date,
        lastUsedAt: nil,
        lastTestStatus: ProfileTestStatus.notTested.rawValue
    )
}

private struct TestAPIKeyCipher: APIKeyEncrypting {
    func encrypt(_ value: String) throws -> Data {
        Data("encrypted:\(value)".utf8)
    }

    func decrypt(_ data: Data) throws -> String {
        String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "encrypted:", with: "")
    }
}

private struct DelayedAPIClient: APIClienting {
    let delayNanoseconds: UInt64

    func request(_ request: URLRequest) async throws -> (Data, HTTPURLResponse, TimeInterval) {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        let data = Data(#"{"choices":[{"message":{"content":"OK"}}]}"#.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response, Double(delayNanoseconds) / 1_000_000_000)
    }
}
