import Foundation
import Testing
@testable import MMSecurity

@Suite("CredentialStore")
struct CredentialStoreTests {
    @Test func unconfiguredProfileReportsNotConfigured() throws {
        let store = InMemoryCredentialStore()
        let profileID = UUID()

        #expect(try store.load(for: profileID) == nil)
        let status = store.status(for: profileID)
        #expect(status.profileID == profileID)
        #expect(!status.isPrimaryConfigured)
        #expect(!status.isSecondaryConfigured)
        #expect(!status.isConfigured)
        #expect(status.primarySuffix == nil)
        #expect(status.secondarySuffix == nil)
        #expect(status.description == "未配置")
    }

    @Test func saveLoadOverwriteDeleteAndIsolatePrimaryAndSecondarySecrets() throws {
        let store = InMemoryCredentialStore()
        let firstID = UUID()
        let secondID = UUID()

        let initial = ProviderCredentials(primarySecret: "key-alpha-1234", secondarySecret: "sec-beta-5678")
        try store.save(initial, for: firstID)

        #expect(try store.load(for: firstID) == initial)
        #expect(try store.load(for: secondID) == nil)
        #expect(!store.status(for: secondID).isConfigured)

        let status = store.status(for: firstID)
        #expect(status.isPrimaryConfigured)
        #expect(status.primarySuffix == "1234")
        #expect(status.isSecondaryConfigured)
        #expect(status.secondarySuffix == "5678")

        let updated = ProviderCredentials(primarySecret: "key-gamma-9999", secondarySecret: "   ")
        try store.save(updated, for: firstID)
        let loadedUpdated = try store.load(for: firstID)
        #expect(loadedUpdated == ProviderCredentials(primarySecret: "key-gamma-9999", secondarySecret: nil))
        #expect(store.status(for: firstID).primarySuffix == "9999")
        #expect(!store.status(for: firstID).isSecondaryConfigured)

        try store.delete(for: firstID)
        #expect(try store.load(for: firstID) == nil)
        #expect(!store.status(for: firstID).isConfigured)

        // Deleting an absent profile is idempotent.
        try store.delete(for: firstID)
    }

    @Test func credentialsAndStatusRedactSecretsAndMaskShortSecrets() throws {
        let store = InMemoryCredentialStore()
        let profileID = UUID()
        let primary = "secret-primary-abcdef1234"
        let secondary = "secret-secondary-ghijkl5678"
        let credentials = ProviderCredentials(primarySecret: primary, secondarySecret: secondary)

        #expect(!credentials.description.contains(primary))
        #expect(!credentials.description.contains(secondary))
        #expect(!credentials.debugDescription.contains(primary))
        #expect(!credentials.debugDescription.contains(secondary))

        try store.save(credentials, for: profileID)
        let status = store.status(for: profileID)
        #expect(!status.description.contains(primary))
        #expect(!status.description.contains(secondary))
        #expect(!status.debugDescription.contains(primary))
        #expect(!status.debugDescription.contains(secondary))
        #expect(status.description.contains("1234"))
        #expect(status.description.contains("5678"))

        // Short secrets (<= 4 chars) must be fully masked as "****".
        let short3ID = UUID()
        try store.save(ProviderCredentials(primarySecret: "abc", secondarySecret: "1234"), for: short3ID)
        let shortStatus = store.status(for: short3ID)
        #expect(shortStatus.primarySuffix == "****")
        #expect(shortStatus.secondarySuffix == "****")
        #expect(!shortStatus.description.contains("abc"))
        #expect(!shortStatus.description.contains("1234"))

        // Blank primary secret throws emptyPrimarySecret.
        #expect(throws: CredentialStoreError.emptyPrimarySecret) {
            try store.save(ProviderCredentials(primarySecret: "   \n\t "), for: UUID())
        }
    }
}

@Suite("ProviderProfileStore")
struct ProviderProfileStoreTests {
    private func makeTempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("minimate-profile-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("provider-profiles.json", isDirectory: false)
    }

    @Test func jsonStorePersistsAcrossReloadsAndMaintainsPerRoleActive() throws {
        let fileURL = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = try JSONFileProviderProfileStore(fileURL: fileURL)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = Date(timeIntervalSince1970: 1_700_000_010)

        let brain1 = ProviderProfile(
            role: .realtimeBrain,
            name: "  主力对话  ",
            driverID: " mock-realtime ",
            customEndpoint: " https://example.com/ws ",
            modelName: "  model-a ",
            voiceID: "  ",
            createdAt: t0,
            updatedAt: t0
        )
        let brain2 = ProviderProfile(
            role: .realtimeBrain,
            name: "备用对话",
            driverID: "mock-realtime",
            createdAt: t1,
            updatedAt: t1
        )
        let tts1 = ProviderProfile(
            role: .emotionalTTS,
            name: "主力音色",
            driverID: "mock-tts",
            voiceID: "demo-voice",
            createdAt: t0,
            updatedAt: t0
        )

        try store.save(brain1)
        // First saved profile in a role automatically becomes active.
        #expect(store.activeProfileID(for: .realtimeBrain) == brain1.id)
        #expect(store.activeProfileID(for: .emotionalTTS) == nil)

        try store.save(brain2)
        // Saving a second profile keeps the existing active selection.
        #expect(store.activeProfileID(for: .realtimeBrain) == brain1.id)

        try store.save(tts1)
        #expect(store.activeProfileID(for: .emotionalTTS) == tts1.id)

        try store.setActive(id: brain2.id, for: .realtimeBrain)
        #expect(store.activeProfileID(for: .realtimeBrain) == brain2.id)

        // Reload from disk and verify exact state and zero secret fields in JSON.
        let reloaded = try JSONFileProviderProfileStore(fileURL: fileURL)
        #expect(reloaded.profiles(for: .realtimeBrain).map(\.id) == [brain1.id, brain2.id])
        #expect(reloaded.profiles(for: .realtimeBrain).first?.name == "主力对话")
        #expect(reloaded.profiles(for: .realtimeBrain).first?.customEndpoint == "https://example.com/ws")
        #expect(reloaded.profiles(for: .realtimeBrain).first?.modelName == "model-a")
        #expect(reloaded.profiles(for: .realtimeBrain).first?.voiceID == nil)
        #expect(reloaded.activeProfileID(for: .realtimeBrain) == brain2.id)
        #expect(reloaded.activeProfileID(for: .emotionalTTS) == tts1.id)

        let rawJSON = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(!rawJSON.contains("primarySecret"))
        #expect(!rawJSON.contains("secondarySecret"))

        // Deleting active profile falls back to first remaining in that role.
        try reloaded.delete(id: brain2.id)
        #expect(reloaded.activeProfileID(for: .realtimeBrain) == brain1.id)
        #expect(reloaded.activeProfileID(for: .emotionalTTS) == tts1.id)

        // Deleting the last profile in a role clears activeProfileID to nil.
        try reloaded.delete(id: brain1.id)
        #expect(reloaded.activeProfileID(for: .realtimeBrain) == nil)
        #expect(reloaded.profiles(for: .realtimeBrain).isEmpty)
        #expect(reloaded.activeProfileID(for: .emotionalTTS) == tts1.id)

        // Clearing active selection explicitly with nil succeeds without deleting the profile.
        try reloaded.setActive(id: nil, for: .emotionalTTS)
        #expect(reloaded.activeProfileID(for: .emotionalTTS) == nil)
        #expect(reloaded.profiles(for: .emotionalTTS).count == 1)
    }

    @Test func corruptJSONStoreThrowsWithoutOverwritingOriginalFile() throws {
        let fileURL = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let corruptPayload = Data("{not valid json".utf8)
        try corruptPayload.write(to: fileURL)

        var threwStorageFailed = false
        do {
            _ = try JSONFileProviderProfileStore(fileURL: fileURL)
        } catch ProviderProfileError.storageFailed {
            threwStorageFailed = true
        }
        #expect(threwStorageFailed)
        #expect(try Data(contentsOf: fileURL) == corruptPayload)
    }

    @Test func profileValidationAndRoleIsolationErrors() throws {
        let store = InMemoryProviderProfileStore()

        #expect(throws: ProviderProfileError.emptyName) {
            try store.save(ProviderProfile(role: .realtimeBrain, name: "   ", driverID: "mock-realtime"))
        }
        #expect(throws: ProviderProfileError.emptyDriverID) {
            try store.save(ProviderProfile(role: .realtimeBrain, name: "Valid", driverID: " "))
        }
        #expect(throws: ProviderProfileError.invalidEndpoint("ftp://example.com/api")) {
            try store.save(ProviderProfile(
                role: .realtimeBrain,
                name: "Valid",
                driverID: "mock-realtime",
                customEndpoint: "ftp://example.com/api"
            ))
        }
        #expect(throws: ProviderProfileError.invalidEndpoint("https://")) {
            try store.save(ProviderProfile(
                role: .realtimeBrain,
                name: "Valid",
                driverID: "mock-realtime",
                customEndpoint: "https://"
            ))
        }

        let sharedID = UUID()
        try store.save(ProviderProfile(id: sharedID, role: .realtimeBrain, name: "Brain", driverID: "mock-realtime"))

        #expect(throws: ProviderProfileError.roleMismatch(expected: .realtimeBrain, actual: .emotionalTTS)) {
            try store.save(ProviderProfile(id: sharedID, role: .emotionalTTS, name: "Hijack", driverID: "mock-tts"))
        }

        let unknownID = UUID()
        #expect(throws: ProviderProfileError.profileNotFound(unknownID)) {
            try store.setActive(id: unknownID, for: .realtimeBrain)
        }
        #expect(throws: ProviderProfileError.roleMismatch(expected: .emotionalTTS, actual: .realtimeBrain)) {
            try store.setActive(id: sharedID, for: .emotionalTTS)
        }
    }
}
