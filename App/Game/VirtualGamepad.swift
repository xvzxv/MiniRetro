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
    /// 全局按键透明度（与单键 opacity 相乘）
    var globalOpacity: CGFloat = 0.6
    let onButtonChange: (JoypadButton, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(layout: $layout, isEditing: isEditing, onButtonChange: onButtonChange)
    }

    func makeUIView(context: Context) -> GamepadCanvasView {
        let view = GamepadCanvasView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        context.coordinator.attach(view: view)
        view.apply(layout: layout, system: system, skin: skin,
                   globalOpacity: globalOpacity, editing: isEditing)
        return view
    }

    func updateUIView(_ uiView: GamepadCanvasView, context: Context) {
        context.coordinator.layoutBinding = $layout
        context.coordinator.isEditing = isEditing
        uiView.apply(layout: layout, system: system, skin: skin,
                     globalOpacity: globalOpacity, editing: isEditing)
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
                let relY = min(max(point.y / bounds.height, 0.03), 0.97)
                var current = self.layoutBinding.wrappedValue
                if let idx = current.buttons.firstIndex(where: { $0.button == button }) {
                    let anchor = current.buttons[idx].anchor
                    let rawX = canvas.relativeX(for: point.x, anchor: anchor)
                    current.buttons[idx].relativeX = min(max(rawX, 0.01), 1.01)
                    current.buttons[idx].relativeY = relY
                    self.layoutBinding.wrappedValue = current
                    canvas.apply(
                        layout: current,
                        system: current.system,
                        skin: current.skin,
                        globalOpacity: canvas.globalOpacity,
                        editing: true
                    )
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
    fileprivate var globalOpacity: CGFloat = 0.6
    private var editing = false

    /// bounds 变化时重排按键（首次 apply 时 bounds 常为 0，必须靠 layoutSubviews 兜底）
    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildButtons()
    }

    /// 把按键的归一化 x 换算成像素。
    /// 左组按「距左边缘的短边倍数」，右组按「距右边缘的短边倍数」（镜像），
    /// 居中组按屏幕宽度比例 —— 这样 iPad(1.33:1) 与 iPhone(2.17:1) 都是贴边、
    /// 对称、间距一致，不会被横向拉开。
    private func resolveX(_ control: ControlButton) -> CGFloat {
        let shortSide = min(bounds.width, bounds.height)
        switch control.anchor {
        case .leading:
            return control.relativeX * shortSide
        case .trailing:
            return bounds.width - (1 - control.relativeX) * shortSide
        case .center:
            return bounds.width * control.relativeX
        case .centerOffset:
            // 相对屏幕中心的短边偏移：居中但间距按短边算，宽高比变化时不会拉开
            return bounds.width / 2 + control.relativeX * shortSide
        }
    }

    /// 拖拽反算：像素 → 归一化（保持该键的锚点语义）
    func relativeX(for x: CGFloat, anchor: HorizontalAnchor) -> CGFloat {
        let shortSide = min(bounds.width, bounds.height)
        guard shortSide > 0, bounds.width > 0 else { return 0.5 }
        switch anchor {
        case .leading:
            return x / shortSide
        case .trailing:
            return 1 - (bounds.width - x) / shortSide
        case .center:
            return x / bounds.width
        case .centerOffset:
            return (x - bounds.width / 2) / shortSide
        }
    }

    /// 按键圆半径（相对短边）
    private var buttonRadius: CGFloat { min(bounds.width, bounds.height) * 0.075 }

    func apply(
        layout: ControlLayout,
        system: SystemType,
        skin: SkinType,
        globalOpacity: CGFloat,
        editing: Bool
    ) {
        currentLayout = layout
        currentSystem = system
        currentSkin = skin
        self.globalOpacity = globalOpacity
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
            // 高度按短边比例，宽度乘 aspect（>1 为横向椭圆，用于 SELECT/START）
            let height = max(shortSide * control.relativeSize, 40)
            let width = height * max(control.aspect, 1.0)
            let center = CGPoint(x: resolveX(control), y: bounds.height * control.relativeY)
            view.frame = CGRect(
                x: center.x - width / 2,
                y: center.y - height / 2,
                width: width,
                height: height
            )
            view.layer.cornerRadius = height / 2
            // 实际透明度 = 单键值 × 全局值（设置页滑杆实时生效）
            view.alpha = max(0.15, min(1.0, control.opacity * globalOpacity))
            view.isUserInteractionEnabled = false // 统一由 touches 分发
            view.setTitle(control.displayLabel, for: .normal)
            // 椭圆键文字略小，避免 SELECT/START 挤出边界
            let fontScale: CGFloat = control.aspect > 1.3 ? 0.24 : 0.28
            view.titleLabel?.font = .systemFont(ofSize: height * fontScale, weight: .bold)
            // 皮肤配色
            switch (skin, editing) {
            case (.classic, false):
                // 常见手柄的灰色半透明：中灰底 + 淡白描边
                view.backgroundColor = UIColor(white: 0.42, alpha: 1.0)
                view.setTitleColor(UIColor(white: 1.0, alpha: 0.92), for: .normal)
                view.layer.borderWidth = 1.5
                view.layer.borderColor = UIColor(white: 1.0, alpha: 0.26).cgColor
            case (.classic, true):
                // 编辑态：淡灰底 + 黄框提示
                view.backgroundColor = UIColor(white: 0.48, alpha: 1.0)
                view.setTitleColor(.white, for: .normal)
                view.layer.borderWidth = 2
                view.layer.borderColor = UIColor.systemYellow.cgColor
            case (.minimal, false):
                view.backgroundColor = UIColor(white: 0.32, alpha: 1.0)
                view.setTitleColor(UIColor(white: 1.0, alpha: 0.88), for: .normal)
                view.layer.borderWidth = 1
                view.layer.borderColor = UIColor(white: 1.0, alpha: 0.18).cgColor
            default:
                view.backgroundColor = UIColor(white: 0.38, alpha: 1.0)
                view.setTitleColor(.white, for: .normal)
                view.layer.borderWidth = 1.5
                view.layer.borderColor = UIColor.systemYellow.cgColor
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
            let base = (self.currentLayout?.button(button)?.opacity ?? 1.0) * self.globalOpacity
            view.alpha = on ? 1.0 : max(0.15, min(1.0, base))
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
