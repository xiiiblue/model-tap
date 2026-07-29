import Foundation

struct ModelTapBackup: Sendable {
    static let currentVersion = 1

    let formatVersion: Int
    let exportedAt: Date
    let folders: [Folder]
    let profiles: [Profile]
    let testRecords: [TestRecord]

    struct Folder: Codable, Sendable {
        let id: UUID
        let name: String
        let createdAt: Date
        let updatedAt: Date
    }

    struct Profile: Codable, Sendable {
        let id: UUID
        let name: String
        let baseURL: String
        let apiKey: String
        let apiFormat: String
        let folderID: UUID?
        let notes: String
        let createdAt: Date
        let updatedAt: Date
        let lastUsedAt: Date?
        let lastTestStatus: String
    }

    struct TestRecord: Codable, Sendable {
        let id: UUID
        let profileID: UUID
        let modelID: String
        let testedAt: Date
        let success: Bool
        let statusCode: Int?
        let duration: TimeInterval
        let protocolName: String?
        let errorSummary: String?
    }
}

enum MarkdownBackupError: LocalizedError {
    case missingVersion
    case unsupportedVersion(Int)
    case invalidRecord(line: Int)
    case duplicateFolderID
    case duplicateFolderName
    case duplicateProfileID
    case duplicateTestRecordID
    case invalidAPIFormat(String)
    case invalidFolderReference
    case invalidProfileReference

    var errorDescription: String? {
        switch self {
        case .missingVersion:
            return "这不是有效的ModelTap Markdown备份。"
        case .unsupportedVersion(let version):
            return "暂不支持版本\(version)的ModelTap备份。"
        case .invalidRecord(let line):
            return "备份文件第\(line)行的数据格式无效。"
        case .duplicateFolderID:
            return "备份中存在重复的文件夹ID。"
        case .duplicateFolderName:
            return "备份中存在同名文件夹。"
        case .duplicateProfileID:
            return "备份中存在重复的配置ID。"
        case .duplicateTestRecordID:
            return "备份中存在重复的测试记录ID。"
        case .invalidAPIFormat(let format):
            return "备份中包含不支持的API格式：\(format)。"
        case .invalidFolderReference:
            return "备份中的配置引用了不存在的文件夹。"
        case .invalidProfileReference:
            return "备份中的测试记录引用了不存在的配置。"
        }
    }
}

enum MarkdownBackupCodec {
    private static let versionPrefix = "<!-- modeltap-backup-version:"
    private static let folderPrefix = "- `folder` "
    private static let profilePrefix = "- `profile` "
    private static let testRecordPrefix = "- `test-record` "

    static func encode(_ backup: ModelTapBackup) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        var lines = [
            "# ModelTap全量备份",
            "",
            "> 警告：此文件包含明文API Key，请妥善保管，不要提交到公开仓库。",
            "",
            "<!-- modeltap-backup-version: \(backup.formatVersion) -->",
            "",
            "共\(backup.folders.count)个文件夹、\(backup.profiles.count)项配置、\(backup.testRecords.count)条测试记录。",
            "",
            "## 文件夹",
            ""
        ]

        for folder in backup.folders {
            lines.append(folderPrefix + (try json(folder, encoder: encoder)))
        }

        lines.append(contentsOf: ["", "## 配置", ""])
        for profile in backup.profiles {
            lines.append(profilePrefix + (try json(profile, encoder: encoder)))
        }

        lines.append(contentsOf: ["", "## 测试记录", ""])
        for record in backup.testRecords {
            lines.append(testRecordPrefix + (try json(record, encoder: encoder)))
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func decode(_ markdown: String) throws -> ModelTapBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var formatVersion: Int?
        var folders: [ModelTapBackup.Folder] = []
        var profiles: [ModelTapBackup.Profile] = []
        var testRecords: [ModelTapBackup.TestRecord] = []

        for (index, rawLine) in markdown.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).enumerated() {
            let line = String(rawLine)
            if line.hasPrefix(versionPrefix) {
                let value = line
                    .dropFirst(versionPrefix.count)
                    .replacingOccurrences(of: "-->", with: "")
                    .trimmingCharacters(in: .whitespaces)
                formatVersion = Int(value)
            } else if line.hasPrefix(folderPrefix) {
                folders.append(
                    try decodeRecord(
                        String(line.dropFirst(folderPrefix.count)),
                        as: ModelTapBackup.Folder.self,
                        line: index + 1,
                        decoder: decoder
                    )
                )
            } else if line.hasPrefix(profilePrefix) {
                profiles.append(
                    try decodeRecord(
                        String(line.dropFirst(profilePrefix.count)),
                        as: ModelTapBackup.Profile.self,
                        line: index + 1,
                        decoder: decoder
                    )
                )
            } else if line.hasPrefix(testRecordPrefix) {
                testRecords.append(
                    try decodeRecord(
                        String(line.dropFirst(testRecordPrefix.count)),
                        as: ModelTapBackup.TestRecord.self,
                        line: index + 1,
                        decoder: decoder
                    )
                )
            }
        }

        guard let formatVersion else {
            throw MarkdownBackupError.missingVersion
        }
        guard formatVersion == ModelTapBackup.currentVersion else {
            throw MarkdownBackupError.unsupportedVersion(formatVersion)
        }

        let backup = ModelTapBackup(
            formatVersion: formatVersion,
            exportedAt: .now,
            folders: folders,
            profiles: profiles,
            testRecords: testRecords
        )
        try validate(backup)
        return backup
    }

    static func validate(_ backup: ModelTapBackup) throws {
        guard Set(backup.folders.map(\.id)).count == backup.folders.count else {
            throw MarkdownBackupError.duplicateFolderID
        }
        let normalizedFolderNames = backup.folders.map {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard Set(normalizedFolderNames).count == normalizedFolderNames.count else {
            throw MarkdownBackupError.duplicateFolderName
        }
        guard Set(backup.profiles.map(\.id)).count == backup.profiles.count else {
            throw MarkdownBackupError.duplicateProfileID
        }
        guard Set(backup.testRecords.map(\.id)).count == backup.testRecords.count else {
            throw MarkdownBackupError.duplicateTestRecordID
        }

        let folderIDs = Set(backup.folders.map(\.id))
        let profileIDs = Set(backup.profiles.map(\.id))
        for profile in backup.profiles {
            guard APIFormat(rawValue: profile.apiFormat) != nil else {
                throw MarkdownBackupError.invalidAPIFormat(profile.apiFormat)
            }
            if let folderID = profile.folderID, !folderIDs.contains(folderID) {
                throw MarkdownBackupError.invalidFolderReference
            }
        }
        guard backup.testRecords.allSatisfy({
            profileIDs.contains($0.profileID)
        }) else {
            throw MarkdownBackupError.invalidProfileReference
        }
    }

    private static func json<T: Encodable>(
        _ value: T,
        encoder: JSONEncoder
    ) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func decodeRecord<T: Decodable>(
        _ value: String,
        as type: T.Type,
        line: Int,
        decoder: JSONDecoder
    ) throws -> T {
        do {
            return try decoder.decode(type, from: Data(value.utf8))
        } catch {
            throw MarkdownBackupError.invalidRecord(line: line)
        }
    }
}
