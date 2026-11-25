import Foundation
import SwiftUI

struct HomeView: View {
    /// Local counter to verify data survives a re-sign (quickstart §2, T009).
    @AppStorage("resignCheckCounter") private var counter = 0

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-showAvatar") {
            // 调试入口：`devicectl ... launch <bundle> -showAvatar` 直达形象页。
            NavigationStack {
                AvatarScreen()
            }
        } else {
            home
        }
        #else
        home
        #endif
    }

    private var home: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("小瓜")
                    .font(.largeTitle)
                Text("MiniMate")
                    .foregroundStyle(.secondary)
                Button("本地计数器：\(counter)") {
                    counter += 1
                }
                .buttonStyle(.bordered)
                Text("重签后此数值应保留")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NavigationLink("形象") {
                    AvatarScreen()
                }
                .buttonStyle(.borderedProminent)
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
