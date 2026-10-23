// InGameMenuView.swift — 游戏中菜单（M2-M7）
// 即时存档/读档（缩略图）、金手指、快进、滤镜、音量、复位、退出
import SwiftUI

struct InGameMenuView: View {
    @ObservedObject var viewModel: EmulatorViewModel
    @Binding var isPresented: Bool

    @State private var states: [SaveStateEntry] = []
    @State private var message: String?
    @State private var showCheatEditor = false
    @State private var showLayoutEditor = false
    @State private var showKeyRemap = false
    @State private var confirmReset = false
    @State private var confirmExit = false

    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(states) { state in
                        HStack(spacing: 10) {
                            // 封面：存档时抓取的游戏画面
                            if let image = viewModel.thumbnailImage(for: state) {
                                Image(crossImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 84, height: 60)
                                    .clipped()
                                    .cornerRadius(6)
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.quaternary)
                                    .frame(width: 84, height: 60)
                                    .overlay(
                                        Image(systemName: state.isOccupied ? "photo" : "square.dashed")
                                            .foregroundStyle(.secondary)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(state.isAutoSave ? "自动存档" : "槽位 \(state.slot)")
                                        .font(.headline)
                                    if state.isAutoSave {
                                        Text("AUTO")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(.tint.opacity(0.15), in: Capsule())
                                    }
                                }
                                if state.isOccupied {
                                    Text(state.timestamp, format: .dateTime.month().day().hour().minute())
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("空")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if state.isAutoSave {
                                    Text("进入游戏时自动载入")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer(minLength: 4)

                            Button("读取") { load(state) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(!state.isOccupied)
                            Button(state.isAutoSave ? "更新" : "保存") { save(state) }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            Button(role: .destructive) {
                                viewModel.deleteState(slot: state.slot, auto: state.isAutoSave)
                                refreshStates()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!state.isOccupied)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("存档")
                } footer: {
                    HintText("自动槽：进游戏时自动载入、退出/切后台时自动写入。手动槽 3 个，可随时存/读/删；删除同时清掉存档文件与封面。")
                }

                Section {
                    Button("金手指管理") { showCheatEditor = true }
                    HintText("支持手动录入、从社区库搜索，以及导入外部 .cht 文件。修改后立即生效。")
                    Toggle("快进（\(settings.fastForwardMultiplier)×）", isOn: fastForwardBinding)
                    Picker("快进倍率", selection: $settings.fastForwardMultiplier) {
                        Text("2×").tag(2)
                        Text("3×").tag(3)
                        Text("4×").tag(4)
                        Text("6×").tag(6)
                        Text("8×").tag(8)
                        Text("16×").tag(16)
                    }
                    HintText("软复位 = 按主机 Reset，不读档、不清存档；存档里的进度仍然保留。")
                    Button("软复位") { confirmReset = true }
                    Button("保存电池存档") {
                        viewModel.flushBatterySave()
                        message = "电池存档已保存"
                    }
                    HintText("电池存档（.sav/.srm）是游戏自己的进度存档，和即时存档不同：游戏内正常保存后，这里可强制立刻写盘。")
                } footer: {
                    HintText("快进倍率越大越省时间，但画面更新会跟不上（声音已按倍率抽取，不会静音）。")
                }

                Section {
                    Picker("滤镜", selection: $settings.filterMode) {
                        ForEach(FilterMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    HintText("CRT/LCD 滤镜在老机型上会掉帧，卡就切回「像素」。")
                    Toggle("显示 FPS", isOn: $settings.showFPS)
                    Toggle("按键震动", isOn: $settings.hapticsEnabled)
                    Slider(value: $settings.volume, in: 0...1) {
                        Text("音量")
                    }
                    HintText("App 内部音量，与系统音量叠加。")
                    Button("虚拟按键布局编辑") { showLayoutEditor = true }
                    HintText("拖动按键改位置，松手自动保存；每个系统一套，可随时恢复默认。")
                    Button("手柄键位设置") { showKeyRemap = true }
                    HintText("改物理按键映射，方向键与摇杆的取舍在设置页「方向输入」里。")
                    Toggle("连接手柄时隐藏虚拟按键", isOn: $settings.autoHideControlsOnController)
                    HintText("连上手柄后屏幕按键消失；想临时调回点画面右上角的手掌图标。")
                } header: {
                    Text("显示与操作")
                }

                Section {
                    LabeledContent("内核", value: viewModel.rom.system.coreName)
                    LabeledContent("分辨率", value: "\(Int(viewModel.retroCore.videoBaseSize.width))×\(Int(viewModel.retroCore.videoBaseSize.height))")
                    LabeledContent("音频延迟", value: String(format: "%.1f ms", viewModel.audioLatencyMs))
                    if GameControllerManager.shared.isConnected {
                        LabeledContent("手柄", value: GameControllerManager.shared.connectedControllerName ?? "已连接")
                    } else {
                        Text("未检测到蓝牙手柄")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("关于本机")
                } footer: {
                    HintText("分辨率是内核输出的画面尺寸（不是屏幕分辨率）。街机若显示 640×480 但画面不动，多半是缺 BIOS。")
                }
            }
            .navigationTitle("菜单")
            
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("退出游戏", role: .destructive) {
                        confirmExit = true
                    }
                }
            }
            .alert("软复位？", isPresented: $confirmReset) {
                Button("取消", role: .cancel) {}
                Button("复位", role: .destructive) { viewModel.resetGame() }
            } message: {
                Text("相当于按主机 Reset：未保存的游戏进度会丢失，即时存档不受影响。")
            }
            .alert("退出游戏？", isPresented: $confirmExit) {
                Button("取消", role: .cancel) {}
                Button("退出", role: .destructive) {
                    isPresented = false
                    viewModel.exitGame?()
                }
            } message: {
                Text("会自动写一次自动存档，下次进来可以接着玩。")
            }
            .alert("提示", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
            .sheet(isPresented: $showCheatEditor) {
                CheatEditorView(viewModel: viewModel)
            }
            .sheet(isPresented: $showLayoutEditor) {
                LayoutEditorView(rom: viewModel.rom)
            }
            .sheet(isPresented: $showKeyRemap) {
                KeyRemapView()
            }
            .onAppear { refreshStates() }
        }
    }

    private var fastForwardBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isFastForwarding },
            set: { viewModel.setFastForward($0) }
        )
    }

    private func refreshStates() {
        states = viewModel.saveSlots()
    }

    private func save(_ state: SaveStateEntry) {
        if let error = viewModel.saveState(slot: state.slot, auto: state.isAutoSave) {
            message = error
        } else {
            message = "已保存到槽位 \(state.slot)"
            refreshStates()
        }
    }

    private func load(_ state: SaveStateEntry) {
        if let error = viewModel.loadState(slot: state.slot, auto: state.isAutoSave) {
            message = error
        } else {
            message = "读取成功"
        }
    }
}
