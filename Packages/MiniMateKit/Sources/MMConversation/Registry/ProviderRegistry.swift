import Foundation
import MMSecurity
import os

public enum ProviderRegistryError: Error, Sendable, Equatable {
    case duplicateDriverID(String)
    case roleMismatch(expected: ProviderRole, actual: ProviderRole)
    case driverNotFound(String)
    case missingPrimarySecret(driverID: String)
}

/// Thread-safe dynamic registry of protocol drivers for both `realtimeBrain` and `emotionalTTS` roles.
///
/// ## Adding a New External Driver (Extension Point)
/// 1. Implement `RealtimeTextSession` (optionally `RealtimeSessionAuditable`) + wrap in `RealtimeSessionDriver`,
///    or implement `TTSProvider` + wrap in `TTSProviderDriver`.
/// 2. Use `context.webSocketTransport` / `context.httpTransport` so `mm-probe record-fixture` and offline tests work seamlessly.
/// 3. Register via `registry.register(driver)` in one place; Settings UI pickers and `mm-probe --driver` discover it automatically.
public final class ProviderRegistry: Sendable {
    private struct State {
        var realtimeDrivers: [String: any RealtimeSessionDriver] = [:]
        var realtimeOrder: [String] = []
        var ttsDrivers: [String: any TTSProviderDriver] = [:]
        var ttsOrder: [String] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public func register(_ driver: any RealtimeSessionDriver) throws {
        let descriptor = driver.descriptor
        guard descriptor.role == .realtimeBrain else {
            throw ProviderRegistryError.roleMismatch(expected: .realtimeBrain, actual: descriptor.role)
        }
        try state.withLock { s in
            guard s.realtimeDrivers[descriptor.id] == nil, s.ttsDrivers[descriptor.id] == nil else {
                throw ProviderRegistryError.duplicateDriverID(descriptor.id)
            }
            s.realtimeDrivers[descriptor.id] = driver
            s.realtimeOrder.append(descriptor.id)
        }
    }

    public func register(_ driver: any TTSProviderDriver) throws {
        let descriptor = driver.descriptor
        guard descriptor.role == .emotionalTTS else {
            throw ProviderRegistryError.roleMismatch(expected: .emotionalTTS, actual: descriptor.role)
        }
        try state.withLock { s in
            guard s.ttsDrivers[descriptor.id] == nil, s.realtimeDrivers[descriptor.id] == nil else {
                throw ProviderRegistryError.duplicateDriverID(descriptor.id)
            }
            s.ttsDrivers[descriptor.id] = driver
            s.ttsOrder.append(descriptor.id)
        }
    }

    public func descriptors(for role: ProviderRole) -> [ProviderDriverDescriptor] {
        state.withLock { s in
            switch role {
            case .realtimeBrain:
                return s.realtimeOrder.compactMap { s.realtimeDrivers[$0]?.descriptor }
            case .emotionalTTS:
                return s.ttsOrder.compactMap { s.ttsDrivers[$0]?.descriptor }
            }
        }
    }

    public func allDescriptors() -> [ProviderDriverDescriptor] {
        descriptors(for: .realtimeBrain) + descriptors(for: .emotionalTTS)
    }

    public func descriptor(id: String) -> ProviderDriverDescriptor? {
        state.withLock { s in
            s.realtimeDrivers[id]?.descriptor ?? s.ttsDrivers[id]?.descriptor
        }
    }

    public func makeRealtimeSession(
        profile: ProviderProfile,
        credentials: ProviderCredentials?,
        context: DriverBuildContext = DriverBuildContext()
    ) throws -> any RealtimeTextSession {
        guard profile.role == .realtimeBrain else {
            throw ProviderRegistryError.roleMismatch(expected: .realtimeBrain, actual: profile.role)
        }
        let driver = try state.withLock { s -> any RealtimeSessionDriver in
            guard let found = s.realtimeDrivers[profile.driverID] else {
                throw ProviderRegistryError.driverNotFound(profile.driverID)
            }
            return found
        }
        if driver.descriptor.requiresPrimarySecret {
            guard let secret = credentials?.primarySecret.trimmingCharacters(in: .whitespacesAndNewlines),
                  !secret.isEmpty
            else {
                throw ProviderRegistryError.missingPrimarySecret(driverID: profile.driverID)
            }
        }
        return try driver.makeSession(profile: profile, credentials: credentials, context: context)
    }

    public func makeTTSProvider(
        profile: ProviderProfile,
        credentials: ProviderCredentials?,
        context: DriverBuildContext = DriverBuildContext()
    ) throws -> any TTSProvider {
        guard profile.role == .emotionalTTS else {
            throw ProviderRegistryError.roleMismatch(expected: .emotionalTTS, actual: profile.role)
        }
        let driver = try state.withLock { s -> any TTSProviderDriver in
            guard let found = s.ttsDrivers[profile.driverID] else {
                throw ProviderRegistryError.driverNotFound(profile.driverID)
            }
            return found
        }
        if driver.descriptor.requiresPrimarySecret {
            guard let secret = credentials?.primarySecret.trimmingCharacters(in: .whitespacesAndNewlines),
                  !secret.isEmpty
            else {
                throw ProviderRegistryError.missingPrimarySecret(driverID: profile.driverID)
            }
        }
        return try driver.makeProvider(profile: profile, credentials: credentials, context: context)
    }
}
