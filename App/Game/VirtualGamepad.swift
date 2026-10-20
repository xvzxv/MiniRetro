// VirtualGamepad.swift — 虚拟按键层（M1/M6）
// 多指触摸必须走 UIKit（SwiftUI Button 不支持可靠多指），
// 位置/大小/透明度来自 ControlLayout（可拖动编辑，持久化 JSON）
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)

// MARK: - SwiftUI 包装

struct VirtualGamepad: UIViewRepresentable {
    let system: SystemType
    let skin: SkinType
    @Binding var layout: ControlLayout
    let isEditing: Bool
    let onButtonChange: (JoypadButton, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(layout: $layout, isEditing: isEditing, onButtonChange: onButtonChange)
    }

    func makeUIView(context: Context) -> GamepadCanvasView {
        let view = GamepadCanvasView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        context.coordinator.attach(view: view)
        view.apply(layout: layout, system: system, skin: skin, editing: isEditing)
        return view
    }

    func updateUIView(_ uiView: GamepadCanvasView, context: Context) {
        context.coordinator.layoutBinding = $layout
        context.coordinator.isEditing = isEditing
        uiView.apply(layout: layout, system: system, skin: skin, editing: isEditing)
    }

    // MARK: - Coordinator（协调布局编辑与按键事件）

    final class Coordinator: NSObject {
        /// 用 Binding 值类型保存（Coordinator 非 View，不能直接持有 @Binding 属性）
        var layoutBinding: Binding<ControlLayout>
        var isEditing: Bool
        let onButtonChange: (JoypadButton, Bool) -> Void
        private weak var canvas: GamepadCanvasView?
        private var dragTarget: JoypadButton?

        init(layout: Binding<ControlLayout>, isEditing: Bool, onButtonChange: @escaping (JoypadButton, Bool) -> Void) {
            self.layoutBinding = layout
            self.isEditing = isEditing
            self.onButtonChange = onButtonChange
        }

        func attach(view: GamepadCanvasView) {
            canvas = view
            view.onTouchBegan = { [weak self] button, point in
                guard let self, self.isEditing else {
                    self?.onButtonChange(button, true)
                    return
                }
                self.dragTarget = button
            }
            view.onTouchEnded = { [weak self] button in
                guard let self else { return }
                if !self.isEditing {
                    self.onButtonChange(button, false)
                } else {
                    self.dragTarget = nil
                }
            }
            view.onTouchMoved = { [weak self] button, point in
                guard let self, self.isEditing, button == self.dragTarget,
                      let canvas = self.canvas else { return }
                let bounds = canvas.bounds
                guard bounds.width > 0, bounds.height > 0 else { return }
                let relX = min(max(point.x / bounds.width, 0.03), 0.97)
                let relY = min(max(point.y / bounds.height, 0.03), 0.97)
                var current = self.layoutBinding.wrappedValue
                if let idx = current.buttons.firstIndex(where: { $0.button == button }) {
                    current.buttons[idx].relativeX = relX
                    current.buttons[idx].relativeY = relY
                    self.layoutBinding.wrappedValue = current
                    canvas.apply(layout: current, system: current.system, skin: current.skin, editing: true)
                }
            }
        }
    }
}

// MARK: - UIKit 画布

final class GamepadCanvasView: UIView {
    var onTouchBegan: ((JoypadButton, CGPoint) -> Void)?
    var onTouchMoved: ((JoypadButton, CGPoint) -> Void)?
    var onTouchEnded: ((JoypadButton) -> Void)?

    private var buttons: [JoypadButton: UIButton] = [:]
    private var currentLayout: ControlLayout?
    private var currentSystem: SystemType = .fc
    private var currentSkin: SkinType = .classic
    private var editing = false

    /// bounds 变化时重排按键（首次 apply 时 bounds 常为 0，必须靠 layoutSubviews 兜底）
    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildButtons()
    }

    /// 按键圆半径（相对短边）
    private var buttonRadius: CGFloat { min(bounds.width, bounds.height) * 0.075 }

    func apply(layout: ControlLayout, system: SystemType, skin: SkinType, editing: Bool) {
        currentLayout = layout
        currentSystem = system
        currentSkin = skin
        self.editing = editing
        rebuildButtons()
    }

    private func rebuildButtons() {
        guard let layout = currentLayout, bounds.width > 0, bounds.height > 0 else { return }
        let system = currentSystem
        let skin = currentSkin
        // 清理失效按键
        for (button, view) in buttons where layout.button(button) == nil {
            view.removeFromSuperview()
            buttons.removeValue(forKey: button)
        }
        for control in layout.buttons {
            let view = buttons[control.button] ?? createButton(control.button)
            buttons[control.button] = view
            let shortSide = min(bounds.width, bounds.height)
            let size = max(shortSide * control.relativeSize, 44)
            view.frame = CGRect(
                x: bounds.width * control.relativeX - size / 2,
                y: bounds.height * control.relativeY - size / 2,
                width: size,
                height: size
            )
            view.layer.cornerRadius = size / 2
            view.alpha = control.opacity
            view.isUserInteractionEnabled = false // 统一由 touches 分发
            view.setTitle(control.button.symbol, for: .normal)
            view.titleLabel?.font = .systemFont(ofSize: size * 0.28, weight: .bold)
            // 皮肤配色
            switch (skin, editing) {
            case (.classic, false):
                view.backgroundColor = UIColor(red: 0.62, green: 0.13, blue: 0.13, alpha: 1.0)
                view.setTitleColor(.white, for: .normal)
                view.layer.borderWidth = 2
                view.layer.borderColor = UIColor(white: 0.9, alpha: 0.7).cgColor
            case (.classic, true):
                view.backgroundColor = UIColor(red: 0.62, green: 0.13, blue: 0.13, alpha: 0.6)
                view.setTitleColor(.white, for: .normal)
                view.layer.borderWidth = 2
                view.layer.borderColor = UIColor.systemYellow.cgColor
            default:
                view.backgroundColor = UIColor(white: 0.2, alpha: 0.5)
                view.setTitleColor(.white, for: .normal)
                view.layer.borderWidth = 1
                view.layer.borderColor = UIColor(white: 1.0, alpha: 0.4).cgColor
            }
            if view.superview == nil {
                addSubview(view)
            }
        }
    }

    private func createButton(_ button: JoypadButton) -> UIButton {
        let buttonView = UIButton(type: .custom)
        buttonView.accessibilityLabel = button.symbol
        return buttonView
    }

    /// 命中测试：圆形区域（允许超出短边的热区扩展，防误触缺失）
    private func buttonAt(_ point: CGPoint) -> JoypadButton? {
        for (button, view) in buttons {
            let center = CGPoint(x: view.frame.midX, y: view.frame.midY)
            let radius = max(view.frame.width / 2, 28)
            let dx = point.x - center.x
            let dy = point.y - center.y
            if dx * dx + dy * dy <= radius * radius {
                return button
            }
        }
        return nil
    }

    private var activeTouches: [ObjectIdentifier: JoypadButton] = [:]

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            guard let button = buttonAt(point) else { continue }
            activeTouches[ObjectIdentifier(touch)] = button
            highlight(button, on: true)
            onTouchBegan?(button, point)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            guard let button = activeTouches[key] else { continue }
            onTouchMoved?(button, touch.location(in: self))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            guard let button = activeTouches[key] else { continue }
            activeTouches.removeValue(forKey: key)
            highlight(button, on: false)
            onTouchEnded?(button)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            guard let button = activeTouches[key] else { continue }
            activeTouches.removeValue(forKey: key)
            highlight(button, on: false)
            onTouchEnded?(button)
        }
    }

    private func highlight(_ button: JoypadButton, on: Bool) {
        guard let view = buttons[button] else { return }
        UIView.animate(withDuration: 0.05) {
            view.alpha = on ? 1.0 : (self.currentLayout?.button(button)?.opacity ?? 0.85)
            view.transform = on ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
        }
    }
}


#else

/// macOS 占位（仅在跨平台类型检查时使用；iOS 上为完整 UIKit 实现）
struct VirtualGamepad: View {
    var body: some View { EmptyView() }
}

#endif
