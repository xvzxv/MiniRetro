// ControlLayout.swift — 虚拟按键布局模型与默认布局（M6）
import CoreGraphics
import Foundation

/// libretro 按键 ID（与 RetroCore.h 注释一致）
enum JoypadButton: UInt16, Codable, CaseIterable {
    case b = 0
    case y = 1
    case select = 2
    case start = 3
    case up = 4
    case down = 5
    case left = 6
    case right = 7
    case a = 8
    case x = 9
    case l = 10
    case r = 11

    var symbol: String {
        switch self {
        case .b: return "B"
        case .y: return "Y"
        case .select: return "SELECT"
        case .start: return "START"
        case .up: return "▲"
        case .down: return "▼"
        case .left: return "◀"
        case .right: return "▶"
        case .a: return "A"
        case .x: return "X"
        case .l: return "L"
        case .r: return "R"
        }
    }

    /// FC 上 Y/X/L/R 无意义（FC 只有 A/B），FC 布局会过滤掉
    var fcRelevant: Bool {
        switch self {
        case .b, .a, .up, .down, .left, .right, .start, .select: return true
        case .y, .x, .l, .r: return false
        }
    }

    var gbRelevant: Bool {
        switch self {
        case .b, .a, .up, .down, .left, .right, .start, .select: return true
        case .y, .x, .l, .r: return false
        }
    }
}

/// 单个可拖动按键（坐标相对屏幕归一化 0-1）
struct ControlButton: Codable, Equatable {
    var button: JoypadButton
    var relativeX: CGFloat
    var relativeY: CGFloat
    /// 相对屏幕短边的尺寸比例
    var relativeSize: CGFloat
    var opacity: CGFloat

    static func == (lhs: ControlButton, rhs: ControlButton) -> Bool {
        lhs.button == rhs.button
            && lhs.relativeX == rhs.relativeX
            && lhs.relativeY == rhs.relativeY
            && lhs.relativeSize == rhs.relativeSize
            && lhs.opacity == rhs.opacity
    }
}

/// 一套布局（按系统 + 皮肤维度）
struct ControlLayout: Codable, Equatable {
    var system: SystemType
    var skin: SkinType
    var buttons: [ControlButton]

    func button(_ joypad: JoypadButton) -> ControlButton? {
        buttons.first { $0.button == joypad }
    }
}

enum ControlLayouts {
    /// FC：十字键左侧，AB 并列右侧（小霸王风格），Start/Select 居中下方
    static func fc(skin: SkinType) -> ControlLayout {
        let opacity: CGFloat = skin == .classic ? 0.85 : 0.45
        return ControlLayout(system: .fc, skin: skin, buttons: [
            ControlButton(button: .up, relativeX: 0.12, relativeY: 0.30, relativeSize: 0.115, opacity: opacity),
            ControlButton(button: .down, relativeX: 0.12, relativeY: 0.52, relativeSize: 0.115, opacity: opacity),
            ControlButton(button: .left, relativeX: 0.045, relativeY: 0.41, relativeSize: 0.115, opacity: opacity),
            ControlButton(button: .right, relativeX: 0.195, relativeY: 0.41, relativeSize: 0.115, opacity: opacity),
            ControlButton(button: .a, relativeX: 0.88, relativeY: 0.47, relativeSize: 0.105, opacity: opacity),
            ControlButton(button: .b, relativeX: 0.78, relativeY: 0.47, relativeSize: 0.105, opacity: opacity),
            ControlButton(button: .start, relativeX: 0.62, relativeY: 0.16, relativeSize: 0.075, opacity: opacity),
            ControlButton(button: .select, relativeX: 0.38, relativeY: 0.16, relativeSize: 0.075, opacity: opacity),
        ])
    }

    /// GB：与 FC 同构（无 LR）
    static func gb(system: SystemType, skin: SkinType) -> ControlLayout {
        let opacity: CGFloat = skin == .classic ? 0.85 : 0.45
        return ControlLayout(system: system, skin: skin, buttons: [
            ControlButton(button: .up, relativeX: 0.12, relativeY: 0.30, relativeSize: 0.115, opacity: opacity),
            ControlButton(button: .down, relativeX: 0.12, relativeY: 0.52, relativeSize: 0.115, opacity: opacity),
            ControlButton(button: .left, relativeX: 0.045, relativeY: 0.41, relativeSize: 0.115, opacity: opacity),
            ControlButton(button: .right, relativeX: 0.195, relativeY: 0.41, relativeSize: 0.115, opacity: opacity),
            ControlButton(button: .a, relativeX: 0.88, relativeY: 0.47, relativeSize: 0.105, opacity: opacity),
            ControlButton(button: .b, relativeX: 0.78, relativeY: 0.47, relativeSize: 0.105, opacity: opacity),
            ControlButton(button: .start, relativeX: 0.62, relativeY: 0.16, relativeSize: 0.075, opacity: opacity),
            ControlButton(button: .select, relativeX: 0.38, relativeY: 0.16, relativeSize: 0.075, opacity: opacity),
        ])
    }

    /// GBA：十字 + AB + LR 肩键
    static func gba(skin: SkinType) -> ControlLayout {
        let opacity: CGFloat = skin == .classic ? 0.85 : 0.45
        return ControlLayout(system: .gba, skin: skin, buttons: [
            ControlButton(button: .up, relativeX: 0.12, relativeY: 0.30, relativeSize: 0.115, opacity: opacity),
            ControlButton(button: .down, relativeX: 0.12, relativeY: 0.52, relativeSize: 0.115, opacity: opacity),
            ControlButton(button: .left, relativeX: 0.045, relativeY: 0.41, relativeSize: 0.115, opacity: opacity),
            ControlButton(button: .right, relativeX: 0.195, relativeY: 0.41, relativeSize: 0.115, opacity: opacity),
            ControlButton(button: .a, relativeX: 0.88, relativeY: 0.47, relativeSize: 0.105, opacity: opacity),
            ControlButton(button: .b, relativeX: 0.78, relativeY: 0.47, relativeSize: 0.105, opacity: opacity),
            ControlButton(button: .l, relativeX: 0.10, relativeY: 0.07, relativeSize: 0.085, opacity: opacity),
            ControlButton(button: .r, relativeX: 0.90, relativeY: 0.07, relativeSize: 0.085, opacity: opacity),
            ControlButton(button: .start, relativeX: 0.62, relativeY: 0.16, relativeSize: 0.075, opacity: opacity),
            ControlButton(button: .select, relativeX: 0.38, relativeY: 0.16, relativeSize: 0.075, opacity: opacity),
        ])
    }

    static func `default`(system: SystemType, skin: SkinType) -> ControlLayout {
        switch system {
        case .fc, .fds: return fc(skin: skin)
        case .gb, .gbc: return gb(system: system, skin: skin)
        case .gba: return gba(skin: skin)
        }
    }
}

/// 布局持久化（Documents/Layouts/<system>-<skin>.json）
enum LayoutStore {
    static func layoutsDirectory() -> URL {
        FileManager.default.documentsDirectory
            .appendingPathComponent("Layouts", isDirectory: true)
    }

    static func layoutURL(system: SystemType, skin: SkinType) -> URL {
        layoutsDirectory().appendingPathComponent("\(system.rawValue)-\(skin.rawValue).json")
    }

    static func load(system: SystemType, skin: SkinType) -> ControlLayout {
        let url = layoutURL(system: system, skin: skin)
        if let data = try? Data(contentsOf: url),
           let layout = try? JSONDecoder().decode(ControlLayout.self, from: data) {
            return layout
        }
        return ControlLayouts.default(system: system, skin: skin)
    }

    static func save(_ layout: ControlLayout) {
        let url = layoutURL(system: layout.system, skin: layout.skin)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(layout) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func reset(system: SystemType, skin: SkinType) {
        try? FileManager.default.removeItem(at: layoutURL(system: system, skin: skin))
    }
}
