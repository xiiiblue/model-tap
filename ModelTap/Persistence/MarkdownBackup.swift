import Foundation

struct ModelTapBackup: Sendable {
    static let currentVersion = 2

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
        let manualModelIDs: [String]?
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
    private static let folderMetadataPrefix = "<!-- modeltap-folder-meta:"
    private static let profileMetadataPrefix = "<!-- modeltap-profile-meta:"
    private static let testMetadataPrefix = "<!-- modeltap-test-meta:"

    // 版本1兼容：旧备份将完整数据保存为可见的单行JSON列表。
    private static let legacyFolderPrefix = "- `folder` "
    private static let legacyProfilePrefix = "- `profile` "
    private static let legacyTestRecordPrefix = "- `test-record` "

    private struct FolderMetadata: Codable {
        let id: UUID
        let createdAt: Date
        let updatedAt: Date
    }

    private struct ProfileMetadata: Codable {
        let id: UUID
        let folderID: UUID?
        let createdAt: Date
        let updatedAt: Date
        let lastUsedAt: Date?
        let lastTestStatus: String
    }

    private struct TestMetadata: Codable {
        let id: UUID
        let profileID: UUID
    }

    static func encode(_ backup: ModelTapBackup) throws -> String {
        var lines = [
            "# ModelTap配置备份",
            "",
            "> 警告：此文件包含明文API Key，请妥善保管，不要提交到公开仓库。",
            ""
        ]

        for folder in backup.folders {
            lines.append("## \(singleLine(folder.name))")
            lines.append("")

            for profile in backup.profiles where profile.folderID == folder.id {
                append(profile, to: &lines)
            }
        }

        let uncategorizedProfiles = backup.profiles.filter { $0.folderID == nil }
        if !uncategorizedProfiles.isEmpty {
            lines.append("## 未分类")
            lines.append("")
            for profile in uncategorizedProfiles {
                append(profile, to: &lines)
            }
        }

        return lines.joined(separator: "\n")
    }

    static func decode(_ markdown: String) throws -> ModelTapBackup {
        let lines = markdown.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)

        let backup: ModelTapBackup
        switch parseVersion(in: lines) {
        case 1:
            backup = try decodeLegacyV1(lines)
        case ModelTapBackup.currentVersion, .none:
            guard lines.contains(where: { $0.hasPrefix("BASE_URL: ") }) else {
                throw MarkdownBackupError.missingVersion
            }
            backup = try decodeReadableV2(lines)
        case .some(let formatVersion):
            throw MarkdownBackupError.unsupportedVersion(formatVersion)
        }

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

    private static func append(
        _ profile: ModelTapBackup.Profile,
        to lines: inout [String]
    ) {
        lines.append("### \(singleLine(profile.name))")
        lines.append("BASE_URL: \(profile.baseURL)")
        lines.append("API_KEY: \(profile.apiKey)")
        lines.append(
            "API格式: \(APIFormat(rawValue: profile.apiFormat)?.title ?? profile.apiFormat)"
        )
        lines.append("备注:")
        appendBlockquote(profile.notes, to: &lines)
        if let manualModelIDs = profile.manualModelIDs, !manualModelIDs.isEmpty {
            lines.append("手动模型:")
            lines.append(contentsOf: manualModelIDs.map { "- \(singleLine($0))" })
        }
        lines.append("")
    }

    private static func appendBlockquote(_ text: String, to lines: inout [String]) {
        guard !text.isEmpty else {
            lines.append(">")
            return
        }
        for line in text.components(separatedBy: "\n") {
            lines.append(line.isEmpty ? ">" : "> \(line)")
        }
    }

    private static func decodeReadableV2(_ lines: [String]) throws -> ModelTapBackup {
        let decoder = makeDecoder()
        var exportedAt = Date.now
        var folders: [ModelTapBackup.Folder] = []
        var profiles: [ModelTapBackup.Profile] = []
        var testRecords: [ModelTapBackup.TestRecord] = []
        var currentFolderName: String?
        var currentFolderID: UUID?
        var currentFolderWasGenerated = false
        var inTestRecords = false
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if line.hasPrefix("导出时间: ") {
                exportedAt = parseDate(
                    String(line.dropFirst("导出时间: ".count))
                ) ?? exportedAt
            } else if line == "## 测试记录" {
                inTestRecords = true
                currentFolderName = nil
                currentFolderID = nil
                currentFolderWasGenerated = false
            } else if line.hasPrefix("## ") {
                inTestRecords = false
                currentFolderName = String(line.dropFirst(3))
                currentFolderWasGenerated = currentFolderName != "未分类"
                if currentFolderWasGenerated, let currentFolderName {
                    let folderID = UUID()
                    currentFolderID = folderID
                    folders.append(
                        .init(
                            id: folderID,
                            name: currentFolderName,
                            createdAt: .now,
                            updatedAt: .now
                        )
                    )
                } else {
                    currentFolderID = nil
                }
            } else if line.hasPrefix(folderMetadataPrefix) {
                guard let folderName = currentFolderName else {
                    throw MarkdownBackupError.invalidRecord(line: index + 1)
                }
                let metadata: FolderMetadata = try decodeMetadata(
                    line,
                    prefix: folderMetadataPrefix,
                    lineNumber: index + 1,
                    decoder: decoder
                )
                if currentFolderWasGenerated {
                    folders.removeLast()
                }
                folders.append(
                    .init(
                        id: metadata.id,
                        name: folderName,
                        createdAt: metadata.createdAt,
                        updatedAt: metadata.updatedAt
                    )
                )
                currentFolderID = metadata.id
                currentFolderWasGenerated = false
            } else if line.hasPrefix("### ") {
                if inTestRecords {
                    let result = try decodeTestRecord(
                        lines,
                        startIndex: index,
                        decoder: decoder
                    )
                    testRecords.append(result.value)
                    index = result.nextIndex
                    continue
                } else {
                    let result = try decodeProfile(
                        lines,
                        startIndex: index,
                        decoder: decoder,
                        folderID: currentFolderID
                    )
                    profiles.append(result.value)
                    index = result.nextIndex
                    continue
                }
            }

            index += 1
        }

        return ModelTapBackup(
            formatVersion: ModelTapBackup.currentVersion,
            exportedAt: exportedAt,
            folders: folders,
            profiles: profiles,
            testRecords: testRecords
        )
    }

    private static func decodeProfile(
        _ lines: [String],
        startIndex: Int,
        decoder: JSONDecoder,
        folderID: UUID?
    ) throws -> (value: ModelTapBackup.Profile, nextIndex: Int) {
        let name = String(lines[startIndex].dropFirst(4))
        var metadata: ProfileMetadata?
        var baseURL: String?
        var apiKey: String?
        var apiFormat: String?
        var notes = ""
        var manualModelIDs: [String] = []
        var index = startIndex + 1

        while index < lines.count,
              !lines[index].hasPrefix("### "),
              !lines[index].hasPrefix("## ") {
            let line = lines[index]
            if line.hasPrefix(profileMetadataPrefix) {
                metadata = try decodeMetadata(
                    line,
                    prefix: profileMetadataPrefix,
                    lineNumber: index + 1,
                    decoder: decoder
                )
            } else if line.hasPrefix("BASE_URL: ") {
                baseURL = parseMarkdownLink(
                    String(line.dropFirst("BASE_URL: ".count))
                )
            } else if line.hasPrefix("API_KEY: ") {
                apiKey = String(line.dropFirst("API_KEY: ".count))
            } else if line.hasPrefix("API格式: ") {
                apiFormat = parseAPIFormat(
                    String(line.dropFirst("API格式: ".count))
                )
            } else if line == "备注:" {
                let result = parseBlockquote(lines, startIndex: index + 1)
                notes = result.value
                index = result.nextIndex
                continue
            } else if line == "手动模型:" {
                index += 1
                while index < lines.count, lines[index].hasPrefix("- ") {
                    let modelID = String(lines[index].dropFirst(2))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !modelID.isEmpty {
                        manualModelIDs.append(modelID)
                    }
                    index += 1
                }
                continue
            }
            index += 1
        }

        guard let baseURL, let apiKey, let apiFormat else {
            throw MarkdownBackupError.invalidRecord(line: startIndex + 1)
        }
        let now = Date.now

        return (
            .init(
                id: metadata?.id ?? UUID(),
                name: name,
                baseURL: baseURL,
                apiKey: apiKey,
                apiFormat: apiFormat,
                folderID: metadata?.folderID ?? folderID,
                notes: notes,
                manualModelIDs: manualModelIDs,
                createdAt: metadata?.createdAt ?? now,
                updatedAt: metadata?.updatedAt ?? now,
                lastUsedAt: metadata?.lastUsedAt,
                lastTestStatus: metadata?.lastTestStatus ?? ProfileTestStatus.notTested.rawValue
            ),
            index
        )
    }

    private static func decodeTestRecord(
        _ lines: [String],
        startIndex: Int,
        decoder: JSONDecoder
    ) throws -> (value: ModelTapBackup.TestRecord, nextIndex: Int) {
        var metadata: TestMetadata?
        var modelID: String?
        var testedAt: Date?
        var success: Bool?
        var statusCode: Int?
        var duration: TimeInterval?
        var protocolName: String?
        var errorSummary: String?
        var index = startIndex + 1

        while index < lines.count,
              !lines[index].hasPrefix("### "),
              !lines[index].hasPrefix("## ") {
            let line = lines[index]
            if line.hasPrefix(testMetadataPrefix) {
                metadata = try decodeMetadata(
                    line,
                    prefix: testMetadataPrefix,
                    lineNumber: index + 1,
                    decoder: decoder
                )
            } else if line.hasPrefix("模型: ") {
                modelID = String(line.dropFirst("模型: ".count))
            } else if line.hasPrefix("测试时间: ") {
                testedAt = parseDate(String(line.dropFirst("测试时间: ".count)))
            } else if line.hasPrefix("结果: ") {
                let value = String(line.dropFirst("结果: ".count))
                success = value == "成功" ? true : value == "失败" ? false : nil
            } else if line.hasPrefix("状态码: ") {
                let value = String(line.dropFirst("状态码: ".count))
                statusCode = value == "-" ? nil : Int(value)
            } else if line.hasPrefix("耗时: "), line.hasSuffix("秒") {
                duration = TimeInterval(
                    line.dropFirst("耗时: ".count).dropLast("秒".count)
                )
            } else if line.hasPrefix("协议: ") {
                let value = String(line.dropFirst("协议: ".count))
                protocolName = value == "-" ? nil : value
            } else if line == "错误:" {
                let result = parseBlockquote(lines, startIndex: index + 1)
                errorSummary = result.value.isEmpty ? nil : result.value
                index = result.nextIndex
                continue
            }
            index += 1
        }

        guard let metadata, let modelID, let testedAt, let success, let duration else {
            throw MarkdownBackupError.invalidRecord(line: startIndex + 1)
        }

        return (
            .init(
                id: metadata.id,
                profileID: metadata.profileID,
                modelID: modelID,
                testedAt: testedAt,
                success: success,
                statusCode: statusCode,
                duration: duration,
                protocolName: protocolName,
                errorSummary: errorSummary
            ),
            index
        )
    }

    private static func decodeLegacyV1(_ lines: [String]) throws -> ModelTapBackup {
        let decoder = makeDecoder()
        var folders: [ModelTapBackup.Folder] = []
        var profiles: [ModelTapBackup.Profile] = []
        var testRecords: [ModelTapBackup.TestRecord] = []

        for (index, line) in lines.enumerated() {
            if line.hasPrefix(legacyFolderPrefix) {
                folders.append(
                    try decodeRecord(
                        String(line.dropFirst(legacyFolderPrefix.count)),
                        as: ModelTapBackup.Folder.self,
                        line: index + 1,
                        decoder: decoder
                    )
                )
            } else if line.hasPrefix(legacyProfilePrefix) {
                profiles.append(
                    try decodeRecord(
                        String(line.dropFirst(legacyProfilePrefix.count)),
                        as: ModelTapBackup.Profile.self,
                        line: index + 1,
                        decoder: decoder
                    )
                )
            } else if line.hasPrefix(legacyTestRecordPrefix) {
                testRecords.append(
                    try decodeRecord(
                        String(line.dropFirst(legacyTestRecordPrefix.count)),
                        as: ModelTapBackup.TestRecord.self,
                        line: index + 1,
                        decoder: decoder
                    )
                )
            }
        }

        return ModelTapBackup(
            formatVersion: 1,
            exportedAt: .now,
            folders: folders,
            profiles: profiles,
            testRecords: testRecords
        )
    }

    private static func parseVersion(in lines: [String]) -> Int? {
        for line in lines where line.hasPrefix(versionPrefix) {
            let value = line
                .dropFirst(versionPrefix.count)
                .replacingOccurrences(of: "-->", with: "")
                .trimmingCharacters(in: .whitespaces)
            return Int(value)
        }
        return nil
    }

    private static func parseMarkdownLink(_ value: String) -> String {
        guard value.hasPrefix("["),
              let separator = value.range(of: "]("),
              value.hasSuffix(")") else {
            return value
        }
        return String(value[value.index(after: value.startIndex)..<separator.lowerBound])
    }

    private static func parseAPIFormat(_ value: String) -> String? {
        if let format = APIFormat(rawValue: value) {
            return format.rawValue
        }
        return APIFormat.allCases.first { $0.title == value }?.rawValue
    }

    private static func parseBlockquote(
        _ lines: [String],
        startIndex: Int
    ) -> (value: String, nextIndex: Int) {
        var values: [String] = []
        var index = startIndex
        while index < lines.count, lines[index].hasPrefix(">") {
            let line = lines[index]
            values.append(line.hasPrefix("> ") ? String(line.dropFirst(2)) : String(line.dropFirst()))
            index += 1
        }
        return (values.joined(separator: "\n"), index)
    }

    private static func singleLine(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ")
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func decodeMetadata<T: Decodable>(
        _ value: String,
        prefix: String,
        lineNumber: Int,
        decoder: JSONDecoder
    ) throws -> T {
        let payload = value
            .dropFirst(prefix.count)
            .dropLast("-->".count)
            .trimmingCharacters(in: .whitespaces)
        return try decodeRecord(
            payload,
            as: T.self,
            line: lineNumber,
            decoder: decoder
        )
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
