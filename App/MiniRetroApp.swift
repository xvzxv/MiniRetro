// MiniRetroApp.swift — App 入口
import SwiftUI

@main
struct MiniRetroApp: App {
    @StateObject private var settings = SettingsStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .preferredColorScheme(.dark)
        }
    }
}
