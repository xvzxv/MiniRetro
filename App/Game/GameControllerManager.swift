// GameControllerManager.swift — 蓝牙手柄支持（M2/M6）
// 标准映射 + 可自定义键位（M6 KeyRemapView 编辑，持久化 UserDefaults）
import Foundation
import GameController

/// GC 按键标识 → JoypadButton 的标准映射
enum GameControllerMapping {
    /// 可重映射的物理按键
    enum PhysicalButton: String, CaseIterable {
        case buttonA
        case buttonB
        case buttonX
        case buttonY
        case leftShoulder
        case rightShoulder
        case leftTrigger
        case rightTrigger
        case dpadUp
        case dpadDown
        case dpadLeft
        case dpadRight
        case buttonMenu      // +
        case buttonOptions   // 三条线

        var displayName: String {
            switch self {
            case .buttonA: return "A"
            case .buttonB: return "B"
            case .buttonX: return "X"
            case .buttonY: return "Y"
            case .leftShoulder: return "L1"
            case .rightShoulder: return "R1"
            case .leftTrigger: return "L2"
            case .rightTrigger: return "R2"
            case .dpadUp: return "十字键 上"
            case .dpadDown: return "十字键 下"
            case .dpadLeft: return "十字键 左"
            case .dpadRight: return "十字键 右"
            case .buttonMenu: return "Menu（+）"
            case .buttonOptions: return "Options"
            }
        }
    }

    /// 标准映射（SFC 风格手柄布局在 GBA/FC/GB 上的通用映射）
    static func standard(physical: PhysicalButton) -> JoypadButton {
        switch physical {
        case .buttonB: return .b
        case .buttonA: return .a
        case .buttonY: return .b       // 部分手柄 B 在右侧：Y→B 备选
        case .buttonX: return .a
        case .leftShoulder: return .l
        case .rightShoulder: return .r
        case .leftTrigger: return .l
        case .rightTrigger: return .r
        case .dpadUp: return .up
        case .dpadDown: return .down
        case .dpadLeft: return .left
        case .dpadRight: return .right
        case .buttonMenu: return .start
        case .buttonOptions: return .select
        }
    }
}

final class GameControllerManager: ObservableObject {
    static let shared = GameControllerManager()

    @Published private(set) var connectedControllerName: String?
    @Published private(set) var isConnected = false

    private let remapKey = "gamecontroller.remap.v1"
    /// 物理按键 → JoypadButton（持久化）
    private(set) var remap: [String: String]

    /// 按键回调（由 GameView 绑定，onDisappear 时 unbind 清理，避免循环引用）
    private var buttonSink: ((JoypadButton, Bool) -> Void)?

    private init() {
        if let data = UserDefaults.standard.data(forKey: remapKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            remap = decoded
        } else {
            remap = [:]
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerDidConnect),
            name: .GCControllerDidConnect, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerDidDisconnect),
            name: .GCControllerDidDisconnect, object: nil
        )
        refreshConnectionState()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 连接状态

    @objc private func controllerDidConnect() {
        refreshConnectionState()
        registerHandlers()
    }

    @objc private func controllerDidDisconnect() {
        refreshConnectionState()
    }

    private func refreshConnectionState() {
        if let controller = GCController.controllers().first {
            connectedControllerName = controller.vendorName ?? "蓝牙手柄"
            isConnected = true
        } else {
            connectedControllerName = nil
            isConnected = false
        }
    }

    // MARK: - 事件注册

    func bind(buttonSink: @escaping (JoypadButton, Bool) -> Void) {
        self.buttonSink = buttonSink
        registerHandlers()
    }

    func unbind() {
        buttonSink = nil
        for controller in GCController.controllers() {
            controller.extendedGamepad?.valueChangedHandler = nil
        }
    }

    private func registerHandlers() {
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            pad.valueChangedHandler = { [weak self] _, element in
                guard let self else { return }
                if let button = element as? GCControllerButtonInput,
                   let physical = self.physicalButton(for: button),
                   let mapped = self.mappedButton(for: physical) {
                    self.buttonSink?(mapped, button.isPressed)
                } else if let dpad = element as? GCControllerDirectionPad {
                    // 十字键逐方向处理（iOS 会为每个方向分别回调）
                    if dpad == pad.dpad {
                        self.emit(.up, pressed: dpad.up.isPressed)
                        self.emit(.down, pressed: dpad.down.isPressed)
                        self.emit(.left, pressed: dpad.left.isPressed)
                        self.emit(.right, pressed: dpad.right.isPressed)
                    }
                }
            }
        }
    }

    private func emit(_ button: JoypadButton, pressed: Bool) {
        buttonSink?(button, pressed)
    }

    /// GC 元素 → 物理按键标识
    private func physicalButton(for button: GCControllerButtonInput) -> GameControllerMapping.PhysicalButton? {
        guard let pad = GCController.controllers().first?.extendedGamepad else { return nil }
        switch button {
        case pad.buttonA: return .buttonA
        case pad.buttonB: return .buttonB
        case pad.buttonX: return .buttonX
        case pad.buttonY: return .buttonY
        case pad.leftShoulder: return .leftShoulder
        case pad.rightShoulder: return .rightShoulder
        case pad.leftTrigger: return .leftTrigger
        case pad.rightTrigger: return .rightTrigger
        case pad.buttonMenu: return .buttonMenu
        case pad.buttonOptions: return .buttonOptions
        default: return nil
        }
    }

    private func mappedButton(for physical: GameControllerMapping.PhysicalButton) -> JoypadButton? {
        if let raw = remap[physical.rawValue], let button = JoypadButton(rawValue: UInt16(raw) ?? 0xFF) {
            return button
        }
        return GameControllerMapping.standard(physical: physical)
    }

    // MARK: - 键位自定义（M6）

    func setRemap(physical: GameControllerMapping.PhysicalButton, to button: JoypadButton) {
        remap[physical.rawValue] = String(button.rawValue)
        persist()
    }

    func resetRemap() {
        remap = [:]
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(remap) {
            UserDefaults.standard.set(data, forKey: remapKey)
        }
    }
}
