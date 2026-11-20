import Foundation
import Security

/// Vendor key storage boundary (Constitution IV): keys live only in Keychain.
public protocol CredentialStore: Sendable {
    func save(key: String, for vendor: VendorID) throws
    /// Configuration state; only exposes the last 4 characters, never the key.
    func status(for vendor: VendorID) -> CredentialStatus
    /// Removing a missing key is a no-op.
    func delete(for vendor: VendorID) throws
}

public struct CredentialStatus: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let vendor: VendorID
    public let isConfigured: Bool
    /// Last 4 characters of the stored key; nil when unconfigured.
    public let suffix: String?

    public init(vendor: VendorID, isConfigured: Bool, suffix: String?) {
        self.vendor = vendor
        self.isConfigured = isConfigured
        self.suffix = suffix
    }

    /// MUST NOT contain the full key (Constitution VII).
    public var description: String {
        if isConfigured, let suffix {
            return "已配置（末 4 位 \(suffix)）"
        }
        return "未配置"
    }

    public var debugDescription: String { description }
}

public enum CredentialStoreError: Error, Sendable {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
}

/// Keychain-backed store: generic password, this-device-only, after first unlock.
public struct KeychainCredentialStore: CredentialStore {
    private let service = "ai.minimate.credentials"

    public init() {}

    public func save(key: String, for vendor: VendorID) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vendor.rawValue,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        var item = baseQuery
        item.merge(attributes) { _, new in new }
        var status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(baseQuery as CFDictionary, [
                kSecValueData as String: Data(key.utf8),
            ] as CFDictionary)
        }
        guard status == errSecSuccess else {
            throw CredentialStoreError.saveFailed(status)
        }
    }

    public func status(for vendor: VendorID) -> CredentialStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vendor.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8)
        else {
            return CredentialStatus(vendor: vendor, isConfigured: false, suffix: nil)
        }
        return CredentialStatus(vendor: vendor, isConfigured: true, suffix: String(key.suffix(4)))
    }

    public func delete(for vendor: VendorID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vendor.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.deleteFailed(status)
        }
    }
}

/// In-memory store for tests and previews.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private var keys: [VendorID: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func save(key: String, for vendor: VendorID) throws {
        lock.withLock { keys[vendor] = key }
    }

    public func status(for vendor: VendorID) -> CredentialStatus {
        let key = lock.withLock { keys[vendor] }
        return CredentialStatus(
            vendor: vendor,
            isConfigured: key != nil,
            suffix: key.map { String($0.suffix(4)) }
        )
    }

    public func delete(for vendor: VendorID) throws {
        lock.withLock { keys[vendor] = nil }
    }
}
