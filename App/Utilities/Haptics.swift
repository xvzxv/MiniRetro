// Haptics.swift — 震动反馈（命中事件可选开关，M7）
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum Haptics {
    /// 轻触（按键反馈）
    static func tap() {
        guard SettingsStore.shared.hapticsEnabled else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// 成功（金手指生效、存档完成）
    static func success() {
        guard SettingsStore.shared.hapticsEnabled else { return }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// 游戏内事件（由 core 侧消息触发，预留）
    static func gameEvent() {
        guard SettingsStore.shared.hapticsEnabled else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}
