import Foundation
import Testing
@testable import MMSecurity

@Suite("CredentialStore")
struct CredentialStoreTests {
    private func makeStore() -> InMemoryCredentialStore {
        InMemoryCredentialStore()
    }

    @Test func unconfiguredVendorReportsNotConfigured() {
        let store = makeStore()

        let status = store.status(for: .aliyun)

        #expect(status.vendor == .aliyun)
        #expect(!status.isConfigured)
        #expect(status.suffix == nil)
    }

    @Test func savedKeyReportsConfiguredWithLast4() throws {
        let store = makeStore()

        try store.save(key: "sk-test-abcd1234", for: .aliyun)
        let status = store.status(for: .aliyun)

        #expect(status.isConfigured)
        #expect(status.suffix == "1234")
    }

    @Test func saveTwiceOverwrites() throws {
        let store = makeStore()

        try store.save(key: "first-key-0001", for: .openai)
        try store.save(key: "second-key-9999", for: .openai)
        let status = store.status(for: .openai)

        #expect(status.suffix == "9999")
    }

    @Test func deleteRemovesKey() throws {
        let store = makeStore()

        try store.save(key: "sk-test-abcd1234", for: .volcengine)
        try store.delete(for: .volcengine)
        let status = store.status(for: .volcengine)

        #expect(!status.isConfigured)
        #expect(status.suffix == nil)
    }

    @Test func deletingAbsentKeyDoesNotThrow() {
        let store = makeStore()

        #expect(throws: Never.self) {
            try store.delete(for: .aliyun)
        }
    }

    @Test func vendorsAreIsolated() throws {
        let store = makeStore()

        try store.save(key: "ali-key-0000", for: .aliyun)

        #expect(!store.status(for: .openai).isConfigured)
    }

    @Test func statusDescriptionNeverContainsFullKey() throws {
        let store = makeStore()
        let fullKey = "sk-secret-abcdef1234567890"

        try store.save(key: fullKey, for: .aliyun)
        let status = store.status(for: .aliyun)

        #expect(!status.description.contains(fullKey))
        #expect(status.description.contains("7890"))
        #expect(!status.debugDescription.contains(fullKey))
    }
}
