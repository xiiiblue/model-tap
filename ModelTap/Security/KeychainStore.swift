import Foundation
import Security

protocol KeychainStoring: Sendable {
    func save(_ value: String, for reference: String) throws
    func read(reference: String) throws -> String?
    func delete(reference: String) throws
}

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status): return "Keychain 操作失败（\(status)）"
        }
    }
}

final class KeychainStore: KeychainStoring, @unchecked Sendable {
    private let service = "com.modeltap.api-key"

    func save(_ value: String, for reference: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: reference]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(updateStatus) }
        } else if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func read(reference: String) throws -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: reference, kSecReturnData as String: true]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError.unexpectedStatus(status) }
        return String(data: data, encoding: .utf8)
    }

    func delete(reference: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: reference]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unexpectedStatus(status) }
    }
}

final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()
    func save(_ value: String, for reference: String) throws { lock.lock(); defer { lock.unlock() }; values[reference] = value }
    func read(reference: String) throws -> String? { lock.lock(); defer { lock.unlock() }; return values[reference] }
    func delete(reference: String) throws { lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: reference) }
}
