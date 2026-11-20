import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("小瓜")
                    .font(.largeTitle)
                Text("MiniMate")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("MiniMate")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("设置") {
                        SettingsView()
                    }
                }
            }
        }
    }
}

#Preview {
    HomeView()
}
