import Foundation

public enum ProviderProfileError: Error, Sendable, Equatable {
    case emptyName
    case emptyDriverID
    case invalidEndpoint(String)
    case roleMismatch(expected: ProviderRole, actual: ProviderRole)
    case profileNotFound(UUID)
    case storageFailed(String)
}

/// Non-sensitive metadata for a user-configured model profile.
/// Secrets MUST NEVER be stored in this struct; they live exclusively in `CredentialStore` keyed by `id`.
public struct ProviderProfile: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let role: ProviderRole
    public var name: String
    public var driverID: String
    public var customEndpoint: String?
    public var modelName: String?
    public var voiceID: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        role: ProviderRole,
        name: String,
        driverID: String,
        customEndpoint: String? = nil,
        modelName: String? = nil,
        voiceID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.name = name
        self.driverID = driverID
        self.customEndpoint = customEndpoint
        self.modelName = modelName
        self.voiceID = voiceID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Validates required fields and normalizes whitespace on optional overrides.
    public func validatedAndNormalized() throws -> ProviderProfile {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ProviderProfileError.emptyName
        }

        let trimmedDriverID = driverID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDriverID.isEmpty else {
            throw ProviderProfileError.emptyDriverID
        }

        let normalizedEndpoint = Self.normalizeOptional(customEndpoint)
        if let endpoint = normalizedEndpoint {
            guard let url = URL(string: endpoint),
                  let scheme = url.scheme?.lowercased(),
                  Self.allowedSchemes.contains(scheme),
                  let host = url.host,
                  !host.isEmpty
            else {
                throw ProviderProfileError.invalidEndpoint(endpoint)
            }
        }

        return ProviderProfile(
            id: id,
            role: role,
            name: trimmedName,
            driverID: trimmedDriverID,
            customEndpoint: normalizedEndpoint,
            modelName: Self.normalizeOptional(modelName),
            voiceID: Self.normalizeOptional(voiceID),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static let allowedSchemes: Set<String> = ["https", "wss", "http", "ws"]

    private static func normalizeOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}
