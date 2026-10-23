// LayoutEditorView.swift — 虚拟按键布局编辑器（M6）
import SwiftUI

struct LayoutEditorView: View {
    let rom: ROMEntry
    @Environment(\.dismiss) private var dismiss
    @State private var layout: ControlLayout
    @State private var selectedButton: JoypadButton?
    @State private var editingSize: CGFloat = 0.11
    @State private var editingOpacity: CGFloat = 0.85
    @State private var confirmReset = false

    @ObservedObject private var settings = SettingsStore.shared

    init(rom: ROMEntry) {
        self.rom = rom
        _layout = State(initialValue: LayoutStore.load(system: rom.system, skin: SettingsStore.shared.skin))
    }

    var body: some View {
        NavigationStack {
            VStack {
                // 预览层（可拖动）
                VirtualGamepad(
                    system: rom.system,
                    skin: settings.skin,
                    layout: $layout,
                    isEditing: true,
                    globalOpacity: 1.0   // 编辑时全不透明，便于定位
                ) { _, _ in }
                .background(Color.black.opacity(0.92))
                .cornerRadius(12)
                .padding(.horizontal)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .top) {
                    Text("直接拖动按键改位置 · 松手自动保存 · 每个系统各一套")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 6)
                }

                // 属性编辑
                Form {
                    Picker("调整按键", selection: $selectedButton) {
                        Text("未选择").tag(JoypadButton?.none)
                        ForEach(layout.buttons, id: \.button) { control in
                            Text(control.button.symbol).tag(JoypadButton?.some(control.button))
                        }
                    }
                    if let selectedButton, let control = layout.button(selectedButton) {
                        Stepper("大小：\(Int(control.relativeSize * 1000))", value: sizeBinding(for: selectedButton), in: 0.06...0.16, step: 0.005)
                        Slider(value: opacityBinding(for: selectedButton), in: 0.2...1.0) {
                            Text("透明度")
                        }
                        HintText("数值是相对屏幕短边的比例：110 ≈ 短边的 11%。改完立即生效。")
                    } else {
                        HintText("先在上方点一个按键，或在「调整按键」里选一个，才能调大小和透明度。")
                    }
                }
                .frame(height: 190)
            }
            .navigationTitle("按键布局")
            .alert("恢复默认布局？", isPresented: $confirmReset) {
                Button("取消", role: .cancel) {}
                Button("恢复", role: .destructive) {
                    layout = ControlLayouts.default(system: rom.system, skin: settings.skin)
                    LayoutStore.save(layout)
                }
            } message: {
                Text("只会重置当前系统（\(rom.system.displayName)）的布局，其他系统不受影响。")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("恢复默认") { confirmReset = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        LayoutStore.save(layout)
                        dismiss()
                    }
                }
            }
        }
    }

    private func sizeBinding(for button: JoypadButton) -> Binding<CGFloat> {
        Binding(
            get: { layout.button(button)?.relativeSize ?? 0.11 },
            set: { newValue in
                if let idx = layout.buttons.firstIndex(where: { $0.button == button }) {
                    layout.buttons[idx].relativeSize = newValue
                }
            }
        )
    }

    private func opacityBinding(for button: JoypadButton) -> Binding<CGFloat> {
        Binding(
            get: { layout.button(button)?.opacity ?? 0.85 },
            set: { newValue in
                if let idx = layout.buttons.firstIndex(where: { $0.button == button }) {
                    layout.buttons[idx].opacity = newValue
                }
            }
        )
    }
}
