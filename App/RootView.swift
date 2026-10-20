// RootView.swift — 根导航：Tab（游戏库 / 设置）
import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("游戏库", systemImage: "gamecontroller")
                }
            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gear")
                }
        }
    }
}
