import Foundation
import os

/// Persistent store for non-sensitive provider profiles and per-role active selection.
public protocol ProviderProfileStore: Sendable {
    func profiles(for role: ProviderRole) -> [ProviderProfile]
    func profile(id: UUID) -> ProviderProfile?
    func activeProfileID(for role: ProviderRole) -> UUID?
    func activeProfile(for role: ProviderRole) -> ProviderProfile?
    func save(_ profile: ProviderProfile) throws
    func delete(id: UUID) throws
    func setActive(id: UUID?, for role: ProviderRole) throws
}

private struct ProfileStoreSnapshot: Codable, Sendable {
    var schemaVersion: Int
    var profiles: [ProviderProfile]
    var activeIDs: [String: UUID]

    static let currentSchemaVersion = 1

    static var empty: ProfileStoreSnapshot {
        ProfileStoreSnapshot(
            schemaVersion: currentSchemaVersion,
            profiles: [],
            activeIDs: [:]
        )
    }

    func sortedProfiles(for role: ProviderRole) -> [ProviderProfile] {
        profiles
            .filter { $0.role == role }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func activeID(for role: ProviderRole) -> UUID? {
        activeIDs[role.rawValue]
    }

    mutating func save(_ profile: ProviderProfile) throws {
        let normalized = try profile.validatedAndNormalized()
        if let index = profiles.firstIndex(where: { $0.id == normalized.id }) {
            let existing = profiles[index]
            guard existing.role == normalized.role else {
                throw ProviderProfileError.roleMismatch(expected: existing.role, actual: normalized.role)
            }
            profiles[index] = normalized
        } else {
            profiles.append(normalized)
        }
        if activeIDs[normalized.role.rawValue] == nil {
            activeIDs[normalized.role.rawValue] = normalized.id
        }
    }

    mutating func delete(id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            return
        }
        let removed = profiles.remove(at: index)
        if activeIDs[removed.role.rawValue] == id {
            let remaining = sortedProfiles(for: removed.role)
            activeIDs[removed.role.rawValue] = remaining.first?.id
        }
    }

    mutating func setActive(id: UUID?, for role: ProviderRole) throws {
        guard let id else {
            activeIDs.removeValue(forKey: role.rawValue)
            return
        }
        guard let existing = profiles.first(where: { $0.id == id }) else {
            throw ProviderProfileError.profileNotFound(id)
        }
        guard existing.role == role else {
            throw ProviderProfileError.roleMismatch(expected: role, actual: existing.role)
        }
        activeIDs[role.rawValue] = id
    }
}

/// JSON file-backed profile store with atomic writes. Stores non-sensitive metadata only.
public final class JSONFileProviderProfileStore: ProviderProfileStore, Sendable {
    private let fileURL: URL
    private let state: OSAllocatedUnfairLock<ProfileStoreSnapshot>

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        let loaded: ProfileStoreSnapshot
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                loaded = try decoder.decode(ProfileStoreSnapshot.self, from: data)
            } catch {
                throw ProviderProfileError.storageFailed(
                    "Failed to decode profile store at \(fileURL.lastPathComponent): \(error.localizedDescription)"
                )
            }
        } else {
            loaded = .empty
        }
        self.state = OSAllocatedUnfairLock(initialState: loaded)
    }

    public static func appDefault(fileManager: FileManager = .default) throws -> JSONFileProviderProfileStore {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ProviderProfileError.storageFailed("Application Support directory unavailable")
        }
        let url = appSupport
            .appendingPathComponent("MiniMate", isDirectory: true)
            .appendingPathComponent("provider-profiles.json", isDirectory: false)
        return try JSONFileProviderProfileStore(fileURL: url)
    }

    public func profiles(for role: ProviderRole) -> [ProviderProfile] {
        state.withLock { $0.sortedProfiles(for: role) }
    }

    public func profile(id: UUID) -> ProviderProfile? {
        state.withLock { snapshot in
            snapshot.profiles.first(where: { $0.id == id })
        }
    }

    public func activeProfileID(for role: ProviderRole) -> UUID? {
        state.withLock { $0.activeID(for: role) }
    }

    public func activeProfile(for role: ProviderRole) -> ProviderProfile? {
        state.withLock { snapshot in
            guard let id = snapshot.activeID(for: role) else { return nil }
            return snapshot.profiles.first(where: { $0.id == id })
        }
    }

    public func save(_ profile: ProviderProfile) throws {
        try state.withLock { snapshot in
            var candidate = snapshot
            try candidate.save(profile)
            try persistLocked(candidate)
            snapshot = candidate
        }
    }

    public func delete(id: UUID) throws {
        try state.withLock { snapshot in
            guard snapshot.profiles.contains(where: { $0.id == id }) else {
                return
            }
            var candidate = snapshot
            candidate.delete(id: id)
            try persistLocked(candidate)
            snapshot = candidate
        }
    }

    public func setActive(id: UUID?, for role: ProviderRole) throws {
        try state.withLock { snapshot in
            var candidate = snapshot
            try candidate.setActive(id: id, for: role)
            try persistLocked(candidate)
            snapshot = candidate
        }
    }

    private func persistLocked(_ snapshot: ProfileStoreSnapshot) throws {
        do {
            let parent = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw ProviderProfileError.storageFailed(error.localizedDescription)
        }
    }
}

/// In-memory profile store for unit tests and SwiftUI previews.
public final class InMemoryProviderProfileStore: ProviderProfileStore, Sendable {
    private let state = OSAllocatedUnfairLock(initialState: ProfileStoreSnapshot.empty)

    public init() {}

    public func profiles(for role: ProviderRole) -> [ProviderProfile] {
        state.withLock { $0.sortedProfiles(for: role) }
    }

    public func profile(id: UUID) -> ProviderProfile? {
        state.withLock { snapshot in
            snapshot.profiles.first(where: { $0.id == id })
        }
    }

    public func activeProfileID(for role: ProviderRole) -> UUID? {
        state.withLock { $0.activeID(for: role) }
    }

    public func activeProfile(for role: ProviderRole) -> ProviderProfile? {
        state.withLock { snapshot in
            guard let id = snapshot.activeID(for: role) else { return nil }
            return snapshot.profiles.first(where: { $0.id == id })
        }
    }

    public func save(_ profile: ProviderProfile) throws {
        try state.withLock { snapshot in
            try snapshot.save(profile)
        }
    }

    public func delete(id: UUID) throws {
        state.withLock { snapshot in
            snapshot.delete(id: id)
        }
    }

    public func setActive(id: UUID?, for role: ProviderRole) throws {
        try state.withLock { snapshot in
            try snapshot.setActive(id: id, for: role)
        }
    }
}
