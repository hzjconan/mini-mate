import SwiftUI

/// Placeholder — real content (credential rows + diagnostics entry) lands in T024.
struct SettingsView: View {
    var body: some View {
        List {
            Text("设置")
        }
        .navigationTitle("设置")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
