import CryptoKit
import Foundation
import LocalAuthentication
import Security

protocol APIKeyEncrypting {
    func encrypt(_ value: String) throws -> Data
    func decrypt(_ data: Data) throws -> String
}

protocol MasterKeyStoring {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

enum LocalEncryptionError: LocalizedError {
    case invalidCiphertext
    case invalidPlaintext
    case invalidMasterKey
    case secureStorageUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidCiphertext:
            return "本地加密的API Key已损坏，请重新填写。"
        case .invalidPlaintext:
            return "无法读取本地加密的API Key，请重新填写。"
        case .invalidMasterKey:
            return "系统安全存储中的主密钥格式无效。"
        case .secureStorageUnavailable(let message):
            return "无法访问系统安全存储：\(message)"
        }
    }
}

final class DataProtectionKeychainMasterKeyStore: MasterKeyStoring {
    private let service: String
    private let account: String

    init(
        service: String = "com.modeltap.app.local-encryption",
        account: String = "master-key"
    ) {
        self.service = service
        self.account = account
    }

    func load() throws -> Data? {
        do {
            if let data = try load(useDataProtectionKeychain: true) {
                return data
            }
            return try load(useDataProtectionKeychain: false)
        } catch KeychainBackendError.missingEntitlement {
            return try load(useDataProtectionKeychain: false)
        }
    }

    func save(_ data: Data) throws {
        do {
            try save(data, useDataProtectionKeychain: true)
        } catch KeychainBackendError.missingEntitlement {
            try save(data, useDataProtectionKeychain: false)
        }
    }

    private func load(useDataProtectionKeychain: Bool) throws -> Data? {
        var query = baseQuery(
            useDataProtectionKeychain: useDataProtectionKeychain
        )
        let authenticationContext = LAContext()
        authenticationContext.interactionNotAllowed = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = authenticationContext

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw LocalEncryptionError.invalidMasterKey
            }
            return data
        case errSecItemNotFound:
            return nil
        case errSecMissingEntitlement where useDataProtectionKeychain:
            throw KeychainBackendError.missingEntitlement
        default:
            throw keychainError(status)
        }
    }

    private func save(
        _ data: Data,
        useDataProtectionKeychain: Bool
    ) throws {
        let query = baseQuery(
            useDataProtectionKeychain: useDataProtectionKeychain
        )
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] =
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(
                query as CFDictionary,
                update as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw keychainError(updateStatus)
            }
        } else if status == errSecMissingEntitlement,
                  useDataProtectionKeychain {
            throw KeychainBackendError.missingEntitlement
        } else if status != errSecSuccess {
            throw keychainError(status)
        }
    }

    private func baseQuery(
        useDataProtectionKeychain: Bool
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if useDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    private func keychainError(_ status: OSStatus) -> LocalEncryptionError {
        let message = SecCopyErrorMessageString(status, nil) as String?
            ?? "错误代码\(status)"
        return .secureStorageUnavailable(message)
    }
}

private enum KeychainBackendError: Error {
    case missingEntitlement
}

final class LocalAPIKeyCipher: APIKeyEncrypting {
    private let masterKeyStore: any MasterKeyStoring
    private let lock = NSLock()
    private var cachedMasterKeyData: Data?

    init(
        masterKeyStore: any MasterKeyStoring =
            DataProtectionKeychainMasterKeyStore()
    ) {
        self.masterKeyStore = masterKeyStore
    }

    func encrypt(_ value: String) throws -> Data {
        let sealedBox = try AES.GCM.seal(
            Data(value.utf8),
            using: loadOrCreateKey()
        )
        guard let combined = sealedBox.combined else {
            throw LocalEncryptionError.invalidCiphertext
        }
        return combined
    }

    func decrypt(_ data: Data) throws -> String {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let plaintext = try AES.GCM.open(
                sealedBox,
                using: loadOrCreateKey()
            )
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
        lock.lock()
        defer { lock.unlock() }

        if let cachedMasterKeyData {
            return SymmetricKey(data: cachedMasterKeyData)
        }

        if let storedData = try masterKeyStore.load() {
            try validateMasterKey(storedData)
            cachedMasterKeyData = storedData
            return SymmetricKey(data: storedData)
        }

        let masterKeyData = SymmetricKey(size: .bits256)
            .withUnsafeBytes { Data($0) }
        try validateMasterKey(masterKeyData)
        try masterKeyStore.save(masterKeyData)

        guard let verifiedData = try masterKeyStore.load(),
              verifiedData == masterKeyData else {
            throw LocalEncryptionError.secureStorageUnavailable(
                "写入后的主密钥无法通过回读校验"
            )
        }

        cachedMasterKeyData = verifiedData
        return SymmetricKey(data: verifiedData)
    }

    private func validateMasterKey(_ data: Data) throws {
        guard data.count == 32 else {
            throw LocalEncryptionError.invalidMasterKey
        }
    }
}
