import SwiftUI

@main
struct MiniMateApp: App {
    @State private var composition = AppComposition()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(composition)
        }
    }
}
