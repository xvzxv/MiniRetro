// ControlLayout.swift — 虚拟按键布局模型与默认布局（M6）
//
// 布局按传统有线手柄（FC/小霸王 → Xbox）的直觉排布：
//   左下 十字方向键 · 中下 SELECT/START（椭圆）· 右下 A/B（与方向键同高）
//   A/B 上方为连发键（TURBO），按住即自动连发对应按键
// 所有按键默认半透明，实际透明度 = 单键 opacity × 全局 controlOpacity（设置页可调）
import CoreGraphics
import Foundation

/// libretro 按键 ID（与 RetroCore.h 注释一致）
///
/// turboA / turboB 是**前端概念**（libretro 无对应键），使用 100+ 的保留值，
/// 由 EmulatorViewModel 拦截处理，不会下发给 core。
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
    // 前端虚拟键（不下发 core）
    case turboA = 100
    case turboB = 101

    /// 是否为连发键（前端处理）
    var isTurbo: Bool {
        self == .turboA || self == .turboB
    }

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
        case .turboA: return "A+"
        case .turboB: return "B+"
        }
    }

    /// FC 上 Y/X/L/R 无意义（FC 只有 A/B），FC 布局会过滤掉
    var fcRelevant: Bool {
        switch self {
        case .b, .a, .up, .down, .left, .right, .start, .select, .turboA, .turboB:
            return true
        case .y, .x, .l, .r:
            return false
        }
    }

    var gbRelevant: Bool { fcRelevant }
}

/// 单个可拖动按键（坐标相对屏幕归一化 0-1）
struct ControlButton: Codable, Equatable {
    var button: JoypadButton
    var relativeX: CGFloat
    var relativeY: CGFloat
    /// 相对屏幕短边的（高度）尺寸比例
    var relativeSize: CGFloat
    /// 单键不透明度（0-1），与全局 controlOpacity 相乘后生效
    var opacity: CGFloat
    /// 宽高比：1.0 = 圆形；>1 为横向椭圆（如 SELECT/START）
    var aspect: CGFloat

    init(
        button: JoypadButton,
        relativeX: CGFloat,
        relativeY: CGFloat,
        relativeSize: CGFloat,
        opacity: CGFloat,
        aspect: CGFloat = 1.0
    ) {
        self.button = button
        self.relativeX = relativeX
        self.relativeY = relativeY
        self.relativeSize = relativeSize
        self.opacity = opacity
        self.aspect = aspect
    }

    // 兼容旧版布局 JSON（缺 aspect 字段时按圆形处理）
    private enum CodingKeys: String, CodingKey {
        case button, relativeX, relativeY, relativeSize, opacity, aspect
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        button = try c.decode(JoypadButton.self, forKey: .button)
        relativeX = try c.decode(CGFloat.self, forKey: .relativeX)
        relativeY = try c.decode(CGFloat.self, forKey: .relativeY)
        relativeSize = try c.decode(CGFloat.self, forKey: .relativeSize)
        opacity = try c.decode(CGFloat.self, forKey: .opacity)
        aspect = try c.decodeIfPresent(CGFloat.self, forKey: .aspect) ?? 1.0
    }

    static func == (lhs: ControlButton, rhs: ControlButton) -> Bool {
        lhs.button == rhs.button
            && lhs.relativeX == rhs.relativeX
            && lhs.relativeY == rhs.relativeY
            && lhs.relativeSize == rhs.relativeSize
            && lhs.opacity == rhs.opacity
            && lhs.aspect == rhs.aspect
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
    // 统一基准线：方向键与 A/B 同高，连发键在其上方，SELECT/START 在中下
    private static let dpadCenterX: CGFloat = 0.150
    private static let dpadY: CGFloat = 0.700
    // 水平/垂直偏移分别按宽、高归一化，需按屏幕宽高比补偿，
    // 否则十字会被拉成长方形（横屏宽>高时水平间距偏大）
    private static let dpadStepX: CGFloat = 0.092
    private static let dpadStepY: CGFloat = 0.125
    private static let dpadSize: CGFloat = 0.115
    private static let actionY: CGFloat = 0.700        // 与方向键同高
    private static let actionSize: CGFloat = 0.104
    private static let turboY: CGFloat = 0.585         // A/B 上方
    private static let turboSize: CGFloat = 0.088
    private static let systemButtonY: CGFloat = 0.868  // 中下
    private static let systemButtonSize: CGFloat = 0.068
    private static let systemButtonAspect: CGFloat = 1.9  // 椭圆

    /// 十字方向键（左下角）
    private static func dpad(opacity: CGFloat) -> [ControlButton] {
        [
            ControlButton(button: .up, relativeX: dpadCenterX, relativeY: dpadY - dpadStepY,
                          relativeSize: dpadSize, opacity: opacity),
            ControlButton(button: .down, relativeX: dpadCenterX, relativeY: dpadY + dpadStepY,
                          relativeSize: dpadSize, opacity: opacity),
            ControlButton(button: .left, relativeX: dpadCenterX - dpadStepX, relativeY: dpadY,
                          relativeSize: dpadSize, opacity: opacity),
            ControlButton(button: .right, relativeX: dpadCenterX + dpadStepX, relativeY: dpadY,
                          relativeSize: dpadSize, opacity: opacity),
        ]
    }

    /// A/B + 连发 A/B（右下）
    /// 顺序：A 在左、B 在右（与需求一致，同 FC 传统左右互换）
    private static func actionButtons(opacity: CGFloat) -> [ControlButton] {
        [
            ControlButton(button: .turboA, relativeX: 0.840, relativeY: turboY,
                          relativeSize: turboSize, opacity: opacity),
            ControlButton(button: .turboB, relativeX: 0.935, relativeY: turboY,
                          relativeSize: turboSize, opacity: opacity),
            ControlButton(button: .a, relativeX: 0.840, relativeY: actionY,
                          relativeSize: actionSize, opacity: opacity),
            ControlButton(button: .b, relativeX: 0.935, relativeY: actionY,
                          relativeSize: actionSize, opacity: opacity),
        ]
    }

    /// SELECT / START（中下，椭圆）
    private static func systemButtons(opacity: CGFloat) -> [ControlButton] {
        [
            ControlButton(button: .select, relativeX: 0.395, relativeY: systemButtonY,
                          relativeSize: systemButtonSize, opacity: opacity,
                          aspect: systemButtonAspect),
            ControlButton(button: .start, relativeX: 0.520, relativeY: systemButtonY,
                          relativeSize: systemButtonSize, opacity: opacity,
                          aspect: systemButtonAspect),
        ]
    }

    /// FC：十字键左下、SELECT/START 中下、A/B + 连发右下
    static func fc(skin: SkinType) -> ControlLayout {
        ControlLayout(system: .fc, skin: skin, buttons:
            dpad(opacity: 1.0) + systemButtons(opacity: 1.0) + actionButtons(opacity: 1.0)
        )
    }

    /// GB：与 FC 同构（无 LR）
    static func gb(system: SystemType, skin: SkinType) -> ControlLayout {
        ControlLayout(system: system, skin: skin, buttons:
            dpad(opacity: 1.0) + systemButtons(opacity: 1.0) + actionButtons(opacity: 1.0)
        )
    }

    /// GBA：十字 + A/B + 连发 + LR 肩键（顶部两角）
    static func gba(skin: SkinType) -> ControlLayout {
        var buttons = dpad(opacity: 1.0) + systemButtons(opacity: 1.0) + actionButtons(opacity: 1.0)
        buttons.append(ControlButton(button: .l, relativeX: 0.075, relativeY: 0.085,
                                     relativeSize: 0.090, opacity: 1.0))
        buttons.append(ControlButton(button: .r, relativeX: 0.925, relativeY: 0.085,
                                     relativeSize: 0.090, opacity: 1.0))
        return ControlLayout(system: .gba, skin: skin, buttons: buttons)
    }

    static func `default`(system: SystemType, skin: SkinType) -> ControlLayout {
        switch system {
        case .fc, .fds: return fc(skin: skin)
        case .gb, .gbc: return gb(system: system, skin: skin)
        case .gba: return gba(skin: skin)
        }
    }
}

// MARK: - 持久化

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
        guard let data = try? Data(contentsOf: url),
              let layout = try? JSONDecoder().decode(ControlLayout.self, from: data) else {
            return ControlLayouts.default(system: system, skin: skin)
        }
        return migrated(layout)
    }

    /// 旧版本布局补充新增按键（如连发键），保留用户已调整的位置
    private static func migrated(_ layout: ControlLayout) -> ControlLayout {
        var result = layout
        let fallback = ControlLayouts.default(system: layout.system, skin: layout.skin)
        for button in [JoypadButton.turboA, .turboB] where result.button(button) == nil {
            if let control = fallback.button(button) {
                result.buttons.append(control)
            }
        }
        return result
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
