// KeyRemapView.swift — 蓝牙手柄键位自定义（M6）
import SwiftUI

struct KeyRemapView: View {
    @ObservedObject private var manager = GameControllerManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var remapping: GameControllerMapping.PhysicalButton?

    var body: some View {
        NavigationStack {
            List {
                if !manager.isConnected {
                    Section {
                        Text("未检测到蓝牙手柄。请前往系统「设置 > 蓝牙」连接后重试。")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section {
                        LabeledContent("已连接", value: manager.connectedControllerName ?? "")
                    }
                }

                Section {
                    ForEach(GameControllerMapping.PhysicalButton.allCases, id: \.self) { physical in
                        HStack {
                            Text(physical.displayName)
                            Spacer()
                            if remapping == physical {
                                Text("按下目标按键…")
                                    .foregroundColor(.accentColor)
                            } else {
                                Text(currentMappingName(physical))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            remapping = physical
                        }
                    }
                } header: {
                    Text("物理按键 → 模拟器按键")
                } footer: {
                    Text("点击某一行进入重映射，然后在上方预览中按下目标模拟器按键。")
                }
            }
            .navigationTitle("手柄键位")
            
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("恢复默认") { manager.resetRemap() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if remapping != nil {
                    // 重映射模式：全屏小键盘供选择目标
                    targetPad
                }
            }
        }
    }

    /// 目标按键选择盘（重映射模式）
    private var targetPad: some View {
        VStack {
            Text("选择映射目标").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56))], spacing: 8) {
                ForEach(JoypadButton.allCases, id: \.rawValue) { button in
                    Button(button.symbol) {
                        if let physical = remapping {
                            manager.setRemap(physical: physical, to: button)
                        }
                        remapping = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding()
    }

    private func currentMappingName(_ physical: GameControllerMapping.PhysicalButton) -> String {
        let button: JoypadButton
        if let raw = UserDefaults.standard.data(forKey: "gamecontroller.remap.v1"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: raw),
           let value = decoded[physical.rawValue],
           let mapped = JoypadButton(rawValue: UInt16(value) ?? 0xFF) {
            button = mapped
        } else {
            button = GameControllerMapping.standard(physical: physical)
        }
        return button.symbol
    }
}
