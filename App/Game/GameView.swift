// GameView.swift — 游戏运行主界面（M1-M7）
// 横屏优先；ZStack = 画面 + 虚拟按键 + HUD + 菜单
import SwiftUI

struct GameView: View {
    @StateObject var viewModel: EmulatorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showMenu = false
    @State private var isEditingLayout = false
    @State private var layout: ControlLayout

    private let settings = SettingsStore.shared

    init(rom: ROMEntry) {
        _viewModel = StateObject(wrappedValue: EmulatorViewModel(rom: rom))
        _layout = State(initialValue: LayoutStore.load(
            system: rom.system,
            skin: SettingsStore.shared.skin
        ))
    }

    var body: some View {
        ZStack {
            GameDisplayView(viewModel: viewModel)
                .ignoresSafeArea()

            VirtualGamepad(
                system: viewModel.rom.system,
                skin: settings.skin,
                layout: $layout,
                isEditing: isEditingLayout
            ) { button, pressed in
                viewModel.setButton(button, pressed: pressed)
                if pressed { Haptics.tap() }
            }
            .ignoresSafeArea()
            .allowsHitTesting(true)

            // HUD
            VStack {
                HStack {
                    Button {
                        showMenu = true
                    } label: {
                        Image(systemName: "menucard")
                            .font(.title2)
                            .padding(10)
                            .background(.black.opacity(0.5), in: Circle())
                    }

                    Spacer()

                    if viewModel.isFastForwarding {
                        Label("快进 \(settings.fastForwardMultiplier)×", systemImage: "forward.fill")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.6), in: Capsule())
                    }

                    if viewModel.isPaused {
                        Label("已暂停", systemImage: "pause.fill")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.6), in: Capsule())
                    }

                    if settings.showFPS {
                        Text(String(format: "%.0f FPS", viewModel.measuredFPS))
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.6), in: Capsule())
                    }

                    if GameControllerManager.shared.isConnected {
                        Image(systemName: "gamecontroller.fill")
                            .font(.caption)
                            .padding(6)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                }
                .foregroundColor(.white)
                .padding([.top, .leading, .trailing], 8)

                Spacer()

                if isEditingLayout {
                    Text("布局编辑中：拖动按键调整位置，松手自动保存")
                        .font(.caption)
                        .padding(8)
                        .background(.black.opacity(0.7), in: Capsule())
                        .foregroundColor(.yellow)
                        .padding(.bottom, 12)
                }
            }
        }
        .onAppear {
            viewModel.loadROM()
            viewModel.exitGame = { dismiss() }
            GameControllerManager.shared.bind { button, pressed in
                viewModel.setButton(button, pressed: pressed)
            }
        }
        .onDisappear {
            GameControllerManager.shared.unbind()
            viewModel.unload()
        }
        .sheet(isPresented: $showMenu) {
            InGameMenuView(viewModel: viewModel, isPresented: $showMenu)
        }
        .toolbar(.hidden)
        .onChange(of: layout) { newValue in
            LayoutStore.save(newValue)
        }
        .onChange(of: settings.skin) { newSkin in
            layout = LayoutStore.load(system: viewModel.rom.system, skin: newSkin)
        }
    }
}
