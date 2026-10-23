// GameView.swift — 游戏运行主界面（M1-M7）
// 横屏优先；ZStack = 画面 + 虚拟按键 + HUD + 菜单
import SwiftUI

struct GameView: View {
    @StateObject var viewModel: EmulatorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showMenu = false
    @State private var isEditingLayout = false
    @State private var layout: ControlLayout
    /// 打开菜单前游戏是否在运行（用于关闭菜单后精确恢复，避免把用户手动暂停的游戏唤醒）
    @State private var wasRunningBeforeMenu = false
    /// 手柄已连接但用户临时要求显示按键（断开手柄后自动复位）
    @State private var forceShowControls = false

    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var controller = GameControllerManager.shared

    init(rom: ROMEntry) {
        _viewModel = StateObject(wrappedValue: EmulatorViewModel(rom: rom))
        _layout = State(initialValue: LayoutStore.load(
            system: rom.system,
            skin: SettingsStore.shared.skin
        ))
    }

    /// 是否隐藏虚拟按键：手柄已连接 + 开关打开 + 用户没有临时要求显示
    private var controlsHidden: Bool {
        controller.isConnected
            && settings.autoHideControlsOnController
            && !forceShowControls
    }

    var body: some View {
        ZStack {
            GameDisplayView(viewModel: viewModel)
                .ignoresSafeArea()

            if !controlsHidden {
                VirtualGamepad(
                    system: viewModel.rom.system,
                    skin: settings.skin,
                    layout: $layout,
                    isEditing: isEditingLayout,
                    globalOpacity: settings.controlOpacity
                ) { button, pressed in
                    viewModel.setButton(button, pressed: pressed)
                    if pressed { Haptics.tap() }
                }
                .ignoresSafeArea()
                .allowsHitTesting(true)
                .transition(.opacity)
            }

            // 状态提示（加载失败 / 缺 BIOS / 已载入进度）——
            // 这些消息以前只写进 statusMessage 从不显示，用户遇到失败只能看黑屏
            if let message = viewModel.statusMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 40)
                    Spacer()
                }
                .transition(.opacity)
                .onTapGesture { viewModel.statusMessage = nil }
                .task(id: message) {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    if viewModel.statusMessage == message { viewModel.statusMessage = nil }
                }
            }

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

                    // 快进快捷开关（不用进菜单）
                    Button {
                        viewModel.setFastForward(!viewModel.isFastForwarding)
                        Haptics.tap()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                            .padding(10)
                            .foregroundStyle(viewModel.isFastForwarding ? Color.black : Color.white)
                            .background(
                                viewModel.isFastForwarding
                                    ? Color.green
                                    : Color.black.opacity(0.5),
                                in: Circle()
                            )
                    }
                    .accessibilityLabel(viewModel.isFastForwarding ? "关闭快进" : "开启快进")

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

                    if controller.isConnected {
                        Button {
                            guard settings.autoHideControlsOnController else { return }
                            forceShowControls.toggle()
                            Haptics.tap()
                        } label: {
                            Image(systemName: controlsHidden ? "hand.tap" : "gamecontroller.fill")
                                .font(.caption)
                                .padding(6)
                                .background(.black.opacity(0.5), in: Circle())
                        }
                        .accessibilityLabel(controlsHidden ? "显示虚拟按键" : "隐藏虚拟按键")
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
        .task {
            // 自动化/调试入口：-MRShowMenu 打开菜单（模拟器验证存档/金手指 UI）
            guard ProcessInfo.processInfo.arguments.contains("-MRShowMenu") else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            NSLog("[MiniRetro] MRShowMenu 触发，showMenu = true")
            showMenu = true
        }
        .onDisappear {
            GameControllerManager.shared.unbind()
            viewModel.unload()
        }
        .sheet(isPresented: $showMenu) {
            InGameMenuView(viewModel: viewModel, isPresented: $showMenu)
        }
        // 进入菜单/设置界面自动暂停：设置页、存档槽、金手指都在这个 sheet 里，
        // 打开时暂停能避免「一边调设置一边游戏在跑/掉血」。
        .onChange(of: showMenu) { presented in
            if presented {
                wasRunningBeforeMenu = viewModel.isLoaded && !viewModel.isPaused
                if settings.pauseOnOpenMenu && wasRunningBeforeMenu {
                    viewModel.pause()
                }
                NSLog("[MiniRetro] 菜单打开 pauseOnOpenMenu=%d wasRunning=%d paused=%d",
                      settings.pauseOnOpenMenu ? 1 : 0,
                      wasRunningBeforeMenu ? 1 : 0,
                      viewModel.isPaused ? 1 : 0)
            } else if wasRunningBeforeMenu {
                viewModel.resume()
                wasRunningBeforeMenu = false
                NSLog("[MiniRetro] 菜单关闭 恢复运行 paused=%d", viewModel.isPaused ? 1 : 0)
            }
        }
        .toolbar(.hidden)
        .animation(.easeInOut(duration: 0.2), value: controlsHidden)
        .onChange(of: controller.isConnected) { connected in
            // 手柄断开后复位「临时显示」，下次连接仍按设置自动隐藏
            if !connected { forceShowControls = false }
            NSLog("[MiniRetro] 手柄状态变化 connected=%d controlsHidden=%d",
                  connected ? 1 : 0, controlsHidden ? 1 : 0)
        }
        .onChange(of: layout) { newValue in
            LayoutStore.save(newValue)
        }
        .onChange(of: settings.skin) { newSkin in
            layout = LayoutStore.load(system: viewModel.rom.system, skin: newSkin)
        }
    }
}
