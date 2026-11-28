import Foundation
import os
import Security

/// Sensitive credential bundle for a single provider profile.
/// Never prints plaintext secrets in `description` or `debugDescription` (Constitution VII).
public struct ProviderCredentials: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let primarySecret: String
    public let secondarySecret: String?

    public init(primarySecret: String, secondarySecret: String? = nil) {
        self.primarySecret = primarySecret
        self.secondarySecret = secondarySecret
    }

    public var description: String {
        "ProviderCredentials(primary: [REDACTED], secondary: \(secondarySecret == nil ? "nil" : "[REDACTED]"))"
    }

    public var debugDescription: String { description }
}

/// Redacted credential status for display in UI and logs.
public struct CredentialStatus: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let profileID: UUID
    public let isPrimaryConfigured: Bool
    public let primarySuffix: String?
    public let isSecondaryConfigured: Bool
    public let secondarySuffix: String?

    public var isConfigured: Bool { isPrimaryConfigured }

    public init(
        profileID: UUID,
        isPrimaryConfigured: Bool,
        primarySuffix: String?,
        isSecondaryConfigured: Bool = false,
        secondarySuffix: String? = nil
    ) {
        self.profileID = profileID
        self.isPrimaryConfigured = isPrimaryConfigured
        self.primarySuffix = primarySuffix
        self.isSecondaryConfigured = isSecondaryConfigured
        self.secondarySuffix = secondarySuffix
    }

    /// Masks short secrets (<= 4 chars) completely to prevent exposing the full value as a suffix.
    public static func maskedSuffix(for secret: String) -> String {
        secret.count <= 4 ? "****" : String(secret.suffix(4))
    }

    public var description: String {
        guard isPrimaryConfigured, let primarySuffix else {
            return "未配置"
        }
        if isSecondaryConfigured, let secondarySuffix {
            return "已配置（主末 4 位 \(primarySuffix) · 附加末 4 位 \(secondarySuffix)）"
        }
        return "已配置（末 4 位 \(primarySuffix)）"
    }

    public var debugDescription: String { description }
}

public enum CredentialStoreError: Error, Sendable, Equatable {
    case emptyPrimarySecret
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case encodingFailed
}

/// Keychain-only credential storage boundary keyed by `profileID` (Constitution IV & VII).
public protocol CredentialStore: Sendable {
    func save(_ credentials: ProviderCredentials, for profileID: UUID) throws
    func load(for profileID: UUID) throws -> ProviderCredentials?
    /// Configuration status; exposes at most a redacted suffix, never the secret.
    func status(for profileID: UUID) -> CredentialStatus
    /// Removing a missing credential is a no-op.
    func delete(for profileID: UUID) throws
}

private struct StoredSecretPayload: Codable {
    let primary: String
    let secondary: String?
}

private func normalizeCredentials(_ credentials: ProviderCredentials) throws -> ProviderCredentials {
    let trimmedPrimary = credentials.primarySecret.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPrimary.isEmpty else {
        throw CredentialStoreError.emptyPrimarySecret
    }
    let trimmedSecondary: String? = {
        guard let raw = credentials.secondarySecret?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return nil
        }
        return raw
    }()
    return ProviderCredentials(primarySecret: trimmedPrimary, secondarySecret: trimmedSecondary)
}

private func makeStatus(profileID: UUID, credentials: ProviderCredentials?) -> CredentialStatus {
    guard let credentials else {
        return CredentialStatus(
            profileID: profileID,
            isPrimaryConfigured: false,
            primarySuffix: nil,
            isSecondaryConfigured: false,
            secondarySuffix: nil
        )
    }
    return CredentialStatus(
        profileID: profileID,
        isPrimaryConfigured: true,
        primarySuffix: CredentialStatus.maskedSuffix(for: credentials.primarySecret),
        isSecondaryConfigured: credentials.secondarySecret != nil,
        secondarySuffix: credentials.secondarySecret.map(CredentialStatus.maskedSuffix(for:))
    )
}

/// Keychain-backed store: generic password, this-device-only, after first unlock.
public struct KeychainCredentialStore: CredentialStore {
    private let service: String

    public init(service: String = "ai.minimate.credentials.v2") {
        self.service = service
    }

    public func save(_ credentials: ProviderCredentials, for profileID: UUID) throws {
        let normalized = try normalizeCredentials(credentials)
        let payload = StoredSecretPayload(
            primary: normalized.primarySecret,
            secondary: normalized.secondarySecret
        )
        let data: Data
        do {
            data = try JSONEncoder().encode(payload)
        } catch {
            throw CredentialStoreError.encodingFailed
        }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        var item = baseQuery
        item.merge(attributes) { _, new in new }
        var status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(baseQuery as CFDictionary, [
                kSecValueData as String: data,
            ] as CFDictionary)
        }
        guard status == errSecSuccess else {
            throw CredentialStoreError.saveFailed(status)
        }
    }

    public func load(for profileID: UUID) throws -> ProviderCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw CredentialStoreError.loadFailed(status)
        }
        guard let data = item as? Data,
              let payload = try? JSONDecoder().decode(StoredSecretPayload.self, from: data)
        else {
            throw CredentialStoreError.encodingFailed
        }
        return ProviderCredentials(
            primarySecret: payload.primary,
            secondarySecret: payload.secondary
        )
    }

    public func status(for profileID: UUID) -> CredentialStatus {
        let loaded = try? load(for: profileID)
        return makeStatus(profileID: profileID, credentials: loaded)
    }

    public func delete(for profileID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.deleteFailed(status)
        }
    }
}

/// In-memory store for tests and previews.
public final class InMemoryCredentialStore: CredentialStore, Sendable {
    private let state = OSAllocatedUnfairLock(initialState: [UUID: ProviderCredentials]())

    public init() {}

    public func save(_ credentials: ProviderCredentials, for profileID: UUID) throws {
        let normalized = try normalizeCredentials(credentials)
        state.withLock { $0[profileID] = normalized }
    }

    public func load(for profileID: UUID) throws -> ProviderCredentials? {
        state.withLock { $0[profileID] }
    }

    public func status(for profileID: UUID) -> CredentialStatus {
        let credentials = state.withLock { $0[profileID] }
        return makeStatus(profileID: profileID, credentials: credentials)
    }

    public func delete(for profileID: UUID) throws {
        state.withLock { $0[profileID] = nil }
    }
}
