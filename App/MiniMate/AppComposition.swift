import Foundation
import MMCore
import Observation

/// Composition root: creates and holds module implementations, injected into the view tree.
@Observable
final class AppComposition {
    let clock: any MMCore.Clock

    init(clock: any MMCore.Clock = SystemClock()) {
        self.clock = clock
    }
}
