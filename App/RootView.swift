// RootView.swift — 根导航：Tab（游戏库 / 设置）
import SwiftUI

struct RootView: View {
    private enum Tab: Hashable {
        case library
        case settings
    }

    @State private var selection: Tab = .library

    var body: some View {
        TabView(selection: $selection) {
            LibraryView()
                .tabItem {
                    Label("游戏库", systemImage: "gamecontroller")
                }
                .tag(Tab.library)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gear")
                }
                .tag(Tab.settings)
        }
        .onAppear {
            // 自动化/调试入口：-MRShowSettings 启动时直接进入设置页
            if ProcessInfo.processInfo.arguments.contains("-MRShowSettings") {
                selection = .settings
            }
        }
    }
}
