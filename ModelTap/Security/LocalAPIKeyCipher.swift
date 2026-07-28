import CryptoKit
import Foundation

protocol APIKeyEncrypting {
    func encrypt(_ value: String) throws -> Data
    func decrypt(_ data: Data) throws -> String
}

enum LocalEncryptionError: LocalizedError {
    case invalidCiphertext
    case invalidPlaintext
    case keyFileUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidCiphertext:
            return "本地加密的API Key已损坏，请重新填写。"
        case .invalidPlaintext:
            return "无法读取本地加密的API Key，请重新填写。"
        case .keyFileUnavailable(let message):
            return "无法访问本地加密密钥：\(message)"
        }
    }
}

final class LocalAPIKeyCipher: APIKeyEncrypting {
    private let keyURL: URL
    private let fileManager: FileManager

    init(
        keyURL: URL = LocalAPIKeyCipher.defaultKeyURL(),
        fileManager: FileManager = .default
    ) {
        self.keyURL = keyURL
        self.fileManager = fileManager
    }

    func encrypt(_ value: String) throws -> Data {
        let sealedBox = try AES.GCM.seal(Data(value.utf8), using: loadOrCreateKey())
        guard let combined = sealedBox.combined else {
            throw LocalEncryptionError.invalidCiphertext
        }
        return combined
    }

    func decrypt(_ data: Data) throws -> String {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let plaintext = try AES.GCM.open(sealedBox, using: loadOrCreateKey())
            guard let value = String(data: plaintext, encoding: .utf8) else {
                throw LocalEncryptionError.invalidPlaintext
            }
            return value
        } catch let error as LocalEncryptionError {
            throw error
        } catch {
            throw LocalEncryptionError.invalidCiphertext
        }
    }

    private func loadOrCreateKey() throws -> SymmetricKey {
        if fileManager.fileExists(atPath: keyURL.path) {
            do {
                let data = try Data(contentsOf: keyURL)
                guard data.count == 32 else {
                    throw LocalEncryptionError.keyFileUnavailable("密钥文件格式无效")
                }
                return SymmetricKey(data: data)
            } catch let error as LocalEncryptionError {
                throw error
            } catch {
                throw LocalEncryptionError.keyFileUnavailable(error.localizedDescription)
            }
        }

        do {
            let directory = keyURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let key = SymmetricKey(size: .bits256)
            let data = key.withUnsafeBytes { Data($0) }
            try data.write(to: keyURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
            return key
        } catch {
            throw LocalEncryptionError.keyFileUnavailable(error.localizedDescription)
        }
    }

    private static func defaultKeyURL() -> URL {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseDirectory
            .appendingPathComponent("ModelTap", isDirectory: true)
            .appendingPathComponent("local-encryption.key", isDirectory: false)
    }
}
