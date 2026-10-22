// SettingsView.swift — 设置页与关于页（M7）
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var controllerManager = GameControllerManager.shared
    @ObservedObject private var controller = GameControllerManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section("核心") {
                    Picker("快进倍率", selection: $settings.fastForwardMultiplier) {
                        Text("2×").tag(2)
                        Text("3×").tag(3)
                        Text("4×").tag(4)
                        Text("6×").tag(6)
                        Text("8×").tag(8)
                        Text("16×").tag(16)
                    }
                    Toggle("进后台自动暂停", isOn: $settings.autoPauseOnBackground)
                    Toggle("进后台自动即时存档", isOn: $settings.autoSaveOnBackground)
                    Toggle("打开游戏时载入自动存档", isOn: $settings.autoLoadOnStart)
                    Toggle("打开菜单/设置时自动暂停", isOn: $settings.pauseOnOpenMenu)
                    Text("开启后每次进入游戏会接着上次的进度；关闭则从头开始。手动槽位共 3 个，另有 1 个自动槽。\n「打开菜单/设置时自动暂停」关闭菜单后会恢复到打开前的运行状态。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("显示") {
                    Picker("视频滤镜", selection: $settings.filterMode) {
                        ForEach(FilterMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    Toggle("保持游戏原始比例", isOn: $settings.preserveAspectRatio)
                    Text("开启：按游戏原生比例显示，多余区域留黑边；关闭：全屏拉伸填满（画面会变形）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("显示 FPS", isOn: $settings.showFPS)
                    Toggle("低性能模式（老机型降级）", isOn: $settings.lowPerformanceMode)
                }

                Section("虚拟按键") {
                    Picker("皮肤", selection: $settings.skin) {
                        ForEach(SkinType.allCases) { skin in
                            Text(skin.displayName).tag(skin)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("按键透明度")
                            Spacer()
                            Text("\(Int(settings.controlOpacity * 100))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.controlOpacity, in: 0.25...1.0, step: 0.05)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("连发频率")
                            Spacer()
                            Text("\(settings.turboRate) 次/秒")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { Double(settings.turboRate) },
                                set: { settings.turboRate = Int($0.rounded()) }
                            ),
                            in: 5...20,
                            step: 1
                        )
                    }
                    Toggle("按键震动", isOn: $settings.hapticsEnabled)
                    Text("A+/B+ 为连发键：按住即自动连发对应按键。所有按键位置可在游戏中「菜单 → 编辑按键布局」拖动调整。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("蓝牙手柄") {
                    HStack {
                        Image(systemName: controllerManager.isConnected
                              ? "gamecontroller.fill" : "gamecontroller")
                            .foregroundStyle(controllerManager.isConnected ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(controllerManager.isConnected
                                 ? (controllerManager.connectedControllerName ?? "已连接手柄")
                                 : "未连接手柄")
                            if controllerManager.isConnected,
                               let battery = controllerManager.batteryLevel {
                                Text("电量 \(Int(battery * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("刷新") {
                            controllerManager.refreshConnectionState()
                        }
                        .font(.footnote)
                    }
                    NavigationLink("手柄键位映射") {
                        KeyRemapView()
                    }
                    Picker("方向输入", selection: $settings.directionInput) {
                        ForEach(DirectionInputMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    Text("选择用手柄的十字键还是左摇杆控制方向（摇杆需推动超过约 45% 才触发，避免误触）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("连接手柄时隐藏虚拟按键", isOn: $settings.autoHideControlsOnController)
                    Text("检测到蓝牙手柄连接后自动隐藏屏幕按键（游戏内 HUD 右上角图标可临时调回），断开手柄后自动恢复。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DisclosureGroup("如何连接 Xbox / 蓝牙手柄") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("1. Xbox 手柄：按住顶部配对键（⌂ 旁的圆形键）约 3 秒，指示灯快闪")
                            Text("2. 打开「设置 → 蓝牙」，在列表中选择你的手柄")
                            Text("3. 系统配对成功后回到本 App，状态会自动更新")
                            Text("4. PS / 其他标准蓝牙手柄同理；本 App 通过系统 GameController 框架接入，无法主动搜索设备")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("街机（FBNeo）") {
                    ForEach(ArcadeSupport.biosRequirements, id: \.fileName) { item in
                        HStack {
                            Image(systemName: item.installed ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(item.installed ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.fileName)
                                Text(item.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    Text("把 neogeo.zip / pgm.zip 用游戏库右上角 + 导入，会自动装到 System 目录；也可在「文件」App 里放进本 App 的 System 文件夹。\n街机游戏请导入整套 romset（.zip/.7z），不要解压。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("音频") {
                    Slider(value: $settings.volume, in: 0...1) {
                        Text("音量")
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: Self.versionString)
                    LabeledContent("内核", value: "fceumm / SameBoy 1.0.4 / mGBA 0.10.5 / FBNeo")
                    NavigationLink("开源许可") {
                        LicensesView()
                    }
                    Text("本 App 不含任何 ROM。请使用你合法拥有的游戏备份或自由/homebrew ROM。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("设置")
        }
    }

    /// 版本号从 Bundle 读取（避免写死后与 project.yml 漂移）
    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

// MARK: - 许可汇总（M8）

struct LicensesView: View {
    var body: some View {
        List {
            Section("mGBA") {
                Text("MPL-2.0\n© 2013-2026 Jeffrey Pfau\nhttps://github.com/mgba-emu/mgba")
            }
            Section("SameBoy") {
                Text("Expat (MIT)\n© 2015-2026 Lior Halphon\nhttps://github.com/LIJI32/SameBoy")
            }
            Section("fceumm (libretro-fceumm)") {
                Text("GPL-2.0\nhttps://github.com/libretro/libretro-fceumm")
            }
            Section("FBNeo (FinalBurn Neo)") {
                Text("FBNeo 许可（非商业使用）\n© FinalBurn Neo team\nhttps://github.com/libretro/fbneo\n街机核心：CPS1/CPS2/Neo Geo/PGM（西游释厄传、三国战纪、拳皇等）")
            }
            Section("libretro") {
                Text("MIT\nhttps://github.com/libretro/libretro.h")
            }
            Section("ZIP 解压") {
                Text("内置实现（App/Library/ZipArchive.swift）\n基于系统 Compression framework，无第三方依赖")
            }
            Section("XcodeGen") {
                Text("MIT\n© Yonas Kolb\nhttps://github.com/yonaskolb/XcodeGen")
            }
        }
        .navigationTitle("开源许可")
        
    }
}
