import Foundation
import SwiftData

enum PersistentStoreBootstrap {
    static let directoryName = "ModelTap"
    static let storeFileName = "ModelTap.store"
    static let legacyStoreFileName = "default.store"

    static func makeContainer(
        fileManager: FileManager = .default
    ) throws -> ModelContainer {
        let schema = Schema([
            APIProfile.self,
            ProfileFolder.self,
            ModelTestRecord.self
        ])
        let storeURL = try prepareStoreURL(fileManager: fileManager)
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        try applyPrivatePermissions(
            to: storeURL,
            fileManager: fileManager
        )
        return container
    }

    static func prepareStoreURL(
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let supportDirectory = try applicationSupportDirectory
            ?? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        let modelTapDirectory = supportDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(
            at: modelTapDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: modelTapDirectory.path
        )

        let storeURL = modelTapDirectory
            .appendingPathComponent(storeFileName)
        guard !fileManager.fileExists(atPath: storeURL.path) else {
            return storeURL
        }

        let legacyURL = supportDirectory
            .appendingPathComponent(legacyStoreFileName)
        if try legacyStoreBelongsToModelTap(
            at: legacyURL,
            fileManager: fileManager
        ) {
            try copyLegacyStore(
                from: legacyURL,
                to: storeURL,
                fileManager: fileManager
            )
        }
        return storeURL
    }

    private static func legacyStoreBelongsToModelTap(
        at storeURL: URL,
        fileManager: FileManager
    ) throws -> Bool {
        let candidates = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]
        for candidate in candidates
        where fileManager.fileExists(atPath: candidate.path) {
            let data = try Data(
                contentsOf: candidate,
                options: [.mappedIfSafe]
            )
            if data.range(of: Data("ZAPIPROFILE".utf8)) != nil {
                return true
            }
        }
        return false
    }

    private static func copyLegacyStore(
        from legacyURL: URL,
        to storeURL: URL,
        fileManager: FileManager
    ) throws {
        let sourceURLs = [
            legacyURL,
            URL(fileURLWithPath: legacyURL.path + "-wal")
        ]
        let destinationURLs = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]
        var copiedURLs: [URL] = []
        do {
            for (source, destination) in zip(
                sourceURLs,
                destinationURLs
            ) where fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(
                    at: source,
                    to: destination
                )
                copiedURLs.append(destination)
                try fileManager.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: destination.path
                )
            }
        } catch {
            for url in copiedURLs {
                try? fileManager.removeItem(at: url)
            }
            throw error
        }
    }

    private static func applyPrivatePermissions(
        to storeURL: URL,
        fileManager: FileManager
    ) throws {
        let relatedURLs = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm")
        ]
        for url in relatedURLs
        where fileManager.fileExists(atPath: url.path) {
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        }
    }
}
