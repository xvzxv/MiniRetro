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

    /// 手柄电量（0-1），不支持或无数据时返回 nil
    var batteryLevel: Float? {
        guard let controller = GCController.controllers().first else { return nil }
        if #available(iOS 14.0, *) {
            guard let battery = controller.battery, battery.batteryState != .unknown else {
                return nil
            }
            return battery.batteryLevel
        }
        return nil
    }

    /// 手动刷新连接状态（设置页「刷新」按钮）
    func refreshConnectionState() {
        let args = ProcessInfo.processInfo.arguments
        // 自动化/调试入口：模拟器会把宿主机手柄透传进来，这里可强制两种状态做对照验证
        if args.contains("-MRFakeController") {
            connectedControllerName = "调试虚拟手柄"
            isConnected = true
            return
        }
        if args.contains("-MRNoController") {
            connectedControllerName = nil
            isConnected = false
            return
        }
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
        directionState.removeAll()
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
                    // 十字键与左摇杆都折算成「方向四键」，用哪个由设置决定（默认十字键）
                    if dpad == pad.dpad {
                        self.handleDirectionPad(dpad)
                    } else if dpad == pad.leftThumbstick {
                        self.handleThumbstick(dpad)
                    }
                }
            }
        }
    }

    /// 方向键状态缓存：GameController 会高频回调，只在状态真正翻转时下发，
    /// 否则每帧几十次 setButton 会把输入表刷爆（还会让连发相位抖动）。
    private var directionState: [JoypadButton: Bool] = [:]

    private func handleDirectionPad(_ dpad: GCControllerDirectionPad) {
        guard SettingsStore.shared.directionInput.usesDpad else { return }
        emitDirection(.up, dpad.up.isPressed)
        emitDirection(.down, dpad.down.isPressed)
        emitDirection(.left, dpad.left.isPressed)
        emitDirection(.right, dpad.right.isPressed)
    }

    /// 摇杆转方向：超过死区（0.45）才算按下，避免手指轻触就乱走
    private func handleThumbstick(_ stick: GCControllerDirectionPad) {
        guard SettingsStore.shared.directionInput.usesLeftStick else { return }
        let deadzone: Float = 0.45
        let x = stick.xAxis.value
        let y = stick.yAxis.value
        emitDirection(.left, x <= -deadzone)
        emitDirection(.right, x >= deadzone)
        emitDirection(.up, y >= deadzone)
        emitDirection(.down, y <= -deadzone)
    }

    private func emitDirection(_ button: JoypadButton, _ pressed: Bool) {
        if directionState[button] == pressed { return }
        directionState[button] = pressed
        buttonSink?(button, pressed)
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
