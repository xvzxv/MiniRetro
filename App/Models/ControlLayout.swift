// ControlLayout.swift — 虚拟按键布局模型与默认布局（M6）
//
// 布局按传统有线手柄（FC/小霸王 → Xbox）的排布：
//   左下 十字方向键 · 中下 SELECT/START（椭圆）· 右下 A/B（与方向键同高）
//   A/B 上方为连发键（TURBO）
//
// 坐标体系（关键）：不同设备横屏宽高比差异极大（iPad 1.33:1、iPhone 2.17:1）。
// 若 x 统一按屏幕宽度归一化，超宽屏上按键会被横向拉开、离边缘很远。
// 因此每个按键带 anchor：
//   .leading  — relativeX 是「距左边缘的短边倍数」（左组）
//   .trailing — relativeX 是 1−(距右边缘的短边倍数)（右组，与左组镜像对称）
//   .center   — relativeX 是屏幕宽度的比例（居中组，如 SELECT/START）
// 按键尺寸与水平间距都以短边为基准，任何宽高比下视觉比例一致。
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

/// 水平锚点：决定 relativeX 相对哪条边换算成像素
enum HorizontalAnchor: String, Codable {
    case leading
    case center
    case trailing
}

/// 单个可拖动按键
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
    /// 水平锚点（见文件头说明）
    var anchor: HorizontalAnchor

    init(
        button: JoypadButton,
        relativeX: CGFloat,
        relativeY: CGFloat,
        relativeSize: CGFloat,
        opacity: CGFloat,
        aspect: CGFloat = 1.0,
        anchor: HorizontalAnchor = .leading
    ) {
        self.button = button
        self.relativeX = relativeX
        self.relativeY = relativeY
        self.relativeSize = relativeSize
        self.opacity = opacity
        self.aspect = aspect
        self.anchor = anchor
    }

    // 兼容旧版布局 JSON（缺 aspect / anchor 字段）
    private enum CodingKeys: String, CodingKey {
        case button, relativeX, relativeY, relativeSize, opacity, aspect, anchor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        button = try c.decode(JoypadButton.self, forKey: .button)
        relativeX = try c.decode(CGFloat.self, forKey: .relativeX)
        relativeY = try c.decode(CGFloat.self, forKey: .relativeY)
        relativeSize = try c.decode(CGFloat.self, forKey: .relativeSize)
        opacity = try c.decode(CGFloat.self, forKey: .opacity)
        aspect = try c.decodeIfPresent(CGFloat.self, forKey: .aspect) ?? 1.0
        anchor = try c.decodeIfPresent(HorizontalAnchor.self, forKey: .anchor)
            ?? Self.inferredAnchor(relativeX)
    }

    /// 旧布局没有 anchor，按位置推断（左侧组 / 居中组 / 右侧组）
    private static func inferredAnchor(_ x: CGFloat) -> HorizontalAnchor {
        if x < 0.42 { return .leading }
        if x > 0.62 { return .trailing }
        return .center
    }

    static func == (lhs: ControlButton, rhs: ControlButton) -> Bool {
        lhs.button == rhs.button
            && lhs.relativeX == rhs.relativeX
            && lhs.relativeY == rhs.relativeY
            && lhs.relativeSize == rhs.relativeSize
            && lhs.opacity == rhs.opacity
            && lhs.aspect == rhs.aspect
            && lhs.anchor == rhs.anchor
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
    /// 左右安全边距（短边倍数）——两组一致，保证对称
    private static let sideMargin: CGFloat = 0.050
    private static let dpadSize: CGFloat = 0.125
    private static let dpadCenterY: CGFloat = 0.720
    private static let actionSize: CGFloat = 0.112
    private static let turboSize: CGFloat = 0.095
    private static let actionY: CGFloat = 0.720
    private static let turboY: CGFloat = 0.585
    private static let systemButtonY: CGFloat = 0.880
    private static let systemButtonSize: CGFloat = 0.070
    private static let systemButtonAspect: CGFloat = 1.9

    // 锚点推导（左右镜像）
    /// 方向键最左键中心（距左边缘 = sideMargin + 半径）
    private static var dpadLeftX: CGFloat { sideMargin + dpadSize / 2 }
    /// 方向键中列（上/下键）
    private static var dpadCenterX: CGFloat { dpadLeftX + dpadSize }
    /// 方向键最右键
    private static var dpadRightX: CGFloat { dpadLeftX + dpadSize * 2 }
    /// B 键中心（距右边缘 = sideMargin + 半径）
    private static var bX: CGFloat { 1 - (sideMargin + actionSize / 2) }
    /// A 键中心（与 B 相距一个按钮直径）
    private static var aX: CGFloat { bX - actionSize }

    /// 十字方向键（左下角）
    private static func dpad(opacity: CGFloat) -> [ControlButton] {
        let stepY = dpadSize   // 垂直间距 = 直径，十字紧贴
        return [
            ControlButton(button: .up, relativeX: dpadCenterX, relativeY: dpadCenterY - stepY,
                          relativeSize: dpadSize, opacity: opacity, anchor: .leading),
            ControlButton(button: .down, relativeX: dpadCenterX, relativeY: dpadCenterY + stepY,
                          relativeSize: dpadSize, opacity: opacity, anchor: .leading),
            ControlButton(button: .left, relativeX: dpadLeftX, relativeY: dpadCenterY,
                          relativeSize: dpadSize, opacity: opacity, anchor: .leading),
            ControlButton(button: .right, relativeX: dpadRightX, relativeY: dpadCenterY,
                          relativeSize: dpadSize, opacity: opacity, anchor: .leading),
        ]
    }

    /// A/B + 连发 A/B（右下，A 在左 B 在右）
    private static func actionButtons(opacity: CGFloat) -> [ControlButton] {
        [
            ControlButton(button: .turboA, relativeX: aX, relativeY: turboY,
                          relativeSize: turboSize, opacity: opacity, anchor: .trailing),
            ControlButton(button: .turboB, relativeX: bX, relativeY: turboY,
                          relativeSize: turboSize, opacity: opacity, anchor: .trailing),
            ControlButton(button: .a, relativeX: aX, relativeY: actionY,
                          relativeSize: actionSize, opacity: opacity, anchor: .trailing),
            ControlButton(button: .b, relativeX: bX, relativeY: actionY,
                          relativeSize: actionSize, opacity: opacity, anchor: .trailing),
        ]
    }

    /// SELECT / START（屏幕水平居中，椭圆）
    private static func systemButtons(opacity: CGFloat) -> [ControlButton] {
        [
            ControlButton(button: .select, relativeX: 0.440, relativeY: systemButtonY,
                          relativeSize: systemButtonSize, opacity: opacity,
                          aspect: systemButtonAspect, anchor: .center),
            ControlButton(button: .start, relativeX: 0.560, relativeY: systemButtonY,
                          relativeSize: systemButtonSize, opacity: opacity,
                          aspect: systemButtonAspect, anchor: .center),
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

    /// GBA：十字 + A/B + 连发 + LR 肩键（顶部两角，镜像对称）
    static func gba(skin: SkinType) -> ControlLayout {
        var buttons = dpad(opacity: 1.0) + systemButtons(opacity: 1.0) + actionButtons(opacity: 1.0)
        let shoulderSize: CGFloat = 0.095
        let shoulderX = sideMargin + shoulderSize / 2
        buttons.append(ControlButton(button: .l, relativeX: shoulderX, relativeY: 0.085,
                                     relativeSize: shoulderSize, opacity: 1.0, anchor: .leading))
        buttons.append(ControlButton(button: .r, relativeX: 1 - shoulderX, relativeY: 0.085,
                                     relativeSize: shoulderSize, opacity: 1.0, anchor: .trailing))
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
