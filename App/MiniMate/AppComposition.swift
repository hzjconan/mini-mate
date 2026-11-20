import Foundation
import MMCore
import MMSecurity
import Observation

/// Composition root: creates and holds module implementations, injected into the view tree.
@Observable
final class AppComposition {
    let clock: any MMCore.Clock
    let credentialStore: any CredentialStore

    init(
        clock: any MMCore.Clock = SystemClock(),
        credentialStore: any CredentialStore = KeychainCredentialStore()
    ) {
        self.clock = clock
        self.credentialStore = credentialStore
    }
}
