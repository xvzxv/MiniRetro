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

    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        NavigationStack {
            List {
                Section("即时存档") {
                    ForEach(states) { state in
                        HStack {
                            if let image = viewModel.thumbnailImage(for: state) {
                                Image(crossImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 72, height: 54)
                                    .cornerRadius(4)
                            } else {
                                Rectangle()
                                    .fill(.quaternary)
                                    .frame(width: 72, height: 54)
                                    .cornerRadius(4)
                                    .overlay(Text("无截图").font(.caption2))
                            }
                            VStack(alignment: .leading) {
                                Text(state.isAutoSave ? "自动存档" : "槽位 \(state.slot)")
                                    .font(.headline)
                                Text(state.timestamp, style: .time)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("读取") { load(state) }
                                .buttonStyle(.bordered)
                            Button("保存") { save(state) }
                                .buttonStyle(.borderedProminent)
                            Button(role: .destructive) {
                                viewModel.deleteState(slot: state.slot, auto: state.isAutoSave)
                                refreshStates()
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    if states.isEmpty {
                        Text("暂无存档，点击「保存」创建")
                            .foregroundColor(.secondary)
                    }
                }

                Section("游戏") {
                    Button("金手指管理") { showCheatEditor = true }
                    Toggle("快进（\(settings.fastForwardMultiplier)×）", isOn: fastForwardBinding)
                    Picker("快进倍率", selection: $settings.fastForwardMultiplier) {
                        Text("2×").tag(2)
                        Text("4×").tag(4)
                    }
                    Button("软复位") { viewModel.resetGame() }
                    Button("保存电池存档") {
                        viewModel.flushBatterySave()
                        message = "电池存档已保存"
                    }
                }

                Section("显示与操作") {
                    Picker("滤镜", selection: $settings.filterMode) {
                        ForEach(FilterMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    Toggle("显示 FPS", isOn: $settings.showFPS)
                    Toggle("按键震动", isOn: $settings.hapticsEnabled)
                    Slider(value: $settings.volume, in: 0...1) {
                        Text("音量")
                    }
                    Button("虚拟按键布局编辑") { showLayoutEditor = true }
                    Button("手柄键位设置") { showKeyRemap = true }
                }

                Section("关于本机") {
                    LabeledContent("核心", value: viewModel.rom.system.coreName)
                    LabeledContent("分辨率", value: "\(Int(viewModel.retroCore.videoBaseSize.width))×\(Int(viewModel.retroCore.videoBaseSize.height))")
                    LabeledContent("音频延迟", value: String(format: "%.1f ms", viewModel.audioLatencyMs))
                    if GameControllerManager.shared.isConnected {
                        LabeledContent("手柄", value: GameControllerManager.shared.connectedControllerName ?? "已连接")
                    } else {
                        Text("未检测到蓝牙手柄")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("菜单")
            
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("退出游戏", role: .destructive) {
                        isPresented = false
                        viewModel.exitGame?()
                    }
                }
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
        states = viewModel.existingStates()
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
