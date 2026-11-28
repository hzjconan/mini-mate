import Foundation
import MMConversation
import MMCore
import MMEmotion
import MMPerception
import MMSecurity
import Observation

/// Composition root: creates and holds module implementations, injected into the view tree.
@Observable
final class AppComposition {
    let clock: any MMCore.Clock
    let credentialStore: any CredentialStore
    let profileStore: any ProviderProfileStore
    let providerRegistry: ProviderRegistry
    let profileStoreLoadError: String?

    init(
        clock: any MMCore.Clock = SystemClock(),
        credentialStore: any CredentialStore = KeychainCredentialStore(),
        profileStore: (any ProviderProfileStore)? = nil,
        providerRegistry: ProviderRegistry = .makeDefault()
    ) {
        self.clock = clock
        self.credentialStore = credentialStore
        self.providerRegistry = providerRegistry
        if let profileStore {
            self.profileStore = profileStore
            self.profileStoreLoadError = nil
        } else {
            do {
                self.profileStore = try JSONFileProviderProfileStore.appDefault()
                self.profileStoreLoadError = nil
            } catch {
                self.profileStore = InMemoryProviderProfileStore()
                self.profileStoreLoadError = SecretRedactor.sanitizedErrorMessage(error)
            }
        }
    }

    func makePerceptionSource() -> (any PerceptionSource)? {
        #if os(iOS)
        ARKitPerceptionSource(clock: clock)
        #else
        nil
        #endif
    }

    func makeEmotionStateMachine() -> any EmotionStateMachine {
        RuleBasedEmotionStateMachine(presets: ExpressionPreset.bundledDefaults, clock: clock)
    }
}
