// LayoutEditorView.swift — 虚拟按键布局编辑器（M6）
import SwiftUI

struct LayoutEditorView: View {
    let rom: ROMEntry
    @Environment(\.dismiss) private var dismiss
    @State private var layout: ControlLayout
    @State private var selectedButton: JoypadButton?
    @State private var editingSize: CGFloat = 0.11
    @State private var editingOpacity: CGFloat = 0.85

    private let settings = SettingsStore.shared

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
                    isEditing: true
                ) { _, _ in }
                .background(Color.black.opacity(0.92))
                .cornerRadius(12)
                .padding(.horizontal)
                .frame(maxHeight: .infinity)

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
                    }
                }
                .frame(height: 170)
            }
            .navigationTitle("按键布局")
            
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("恢复默认") {
                        layout = ControlLayouts.default(system: rom.system, skin: settings.skin)
                        LayoutStore.save(layout)
                    }
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
