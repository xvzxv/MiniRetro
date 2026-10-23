// DirectionInputMerger.swift — 方向输入合并（十字键 + 左摇杆）
//
// 为什么单独抽出来：v1.8 的实现把两个输入源写进同一张状态表，
// 摇杆每帧回调（停在死区内 → 全 false）会立刻把十字键按住的方向清掉，
// 表现是「按一下动一下」。这里的规则是「按输入源分别记录，取或合并」，
// 并且是纯数据结构，可以脱离 GameController 框架做单元测试。
import Foundation

struct DirectionInputMerger {
    private(set) var dpad: [JoypadButton: Bool] = [:]
    private(set) var stick: [JoypadButton: Bool] = [:]

    static let directions: [JoypadButton] = [.up, .down, .left, .right]

    mutating func setDpad(_ button: JoypadButton, _ pressed: Bool) {
        dpad[button] = pressed
    }

    mutating func setStick(_ button: JoypadButton, _ pressed: Bool) {
        stick[button] = pressed
    }

    mutating func clearDpad() { dpad.removeAll() }
    mutating func clearStick() { stick.removeAll() }

    mutating func reset() {
        dpad.removeAll()
        stick.removeAll()
    }

    /// 任一输入源按住即视为按下
    func merged(_ button: JoypadButton) -> Bool {
        (dpad[button] ?? false) || (stick[button] ?? false)
    }

    /// 摇杆轴向 → 四个方向（含死区）
    static func stickDirections(x: Float, y: Float, deadzone: Float = 0.45) -> [JoypadButton: Bool] {
        [
            .left: x <= -deadzone,
            .right: x >= deadzone,
            .up: y >= deadzone,
            .down: y <= -deadzone,
        ]
    }

    /// 十字键布尔值 → 四个方向
    static func dpadDirections(up: Bool, down: Bool, left: Bool, right: Bool) -> [JoypadButton: Bool] {
        [.up: up, .down: down, .left: left, .right: right]
    }
}
