// SettingsView.swift — 设置页与关于页（M7）
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var controllerManager = GameControllerManager.shared
    @ObservedObject private var controller = GameControllerManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("快进倍率", selection: $settings.fastForwardMultiplier) {
                        Text("2×").tag(2)
                        Text("3×").tag(3)
                        Text("4×").tag(4)
                        Text("6×").tag(6)
                        Text("8×").tag(8)
                        Text("16×").tag(16)
                    }
                    HintText("快进按钮按住/点按后按这个倍数跑。16× 适合跳过重复剧情，画面会明显卡顿（音频仍按倍率抽取，不会静音）。")
                    Toggle("进后台自动暂停", isOn: $settings.autoPauseOnBackground)
                    HintText("切到别的 App 时暂停，回来继续。关闭后游戏会在后台继续跑（费电，音游/放置类才需要关）。")
                    Toggle("进后台自动即时存档", isOn: $settings.autoSaveOnBackground)
                    HintText("进后台时写一次「自动存档」槽位，防止被系统杀掉丢进度。")
                    Toggle("打开游戏时载入自动存档", isOn: $settings.autoLoadOnStart)
                    HintText("开启后进入游戏接着上次进度；关闭则从头开始（不会删除已有存档）。")
                    Toggle("打开菜单/设置时自动暂停", isOn: $settings.pauseOnOpenMenu)
                    HintText("打开游戏内菜单会暂停，关闭菜单恢复到打开前的状态——你手动暂停的游戏不会被这个开关唤醒。")
                } header: {
                    Text("运行")
                } footer: {
                    HintText("存档结构：1 个自动槽 + 3 个手动槽，每槽都会存一张当时的画面做封面。")
                }

                Section {
                    Picker("视频滤镜", selection: $settings.filterMode) {
                        ForEach(FilterMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    HintText("像素：整数倍放大，最锐利；平滑：模糊边缘；CRT：扫描线+暗角；LCD：GB 点阵。滤镜越花越耗电。")
                    Toggle("保持游戏原始比例", isOn: $settings.preserveAspectRatio)
                    HintText("开启：按原生比例显示，两侧留黑边；关闭：拉伸铺满（超宽屏上会明显变形）。虚拟按键不受影响，永远按屏幕布局。")
                    Toggle("显示 FPS", isOn: $settings.showFPS)
                    HintText("右上角显示实测帧率，用来判断掉帧是性能问题还是 ROM 问题。")
                    Toggle("低性能模式（老机型降级）", isOn: $settings.lowPerformanceMode)
                    HintText("iPad 6 / A10 这类老机器建议开：会强制关掉 CRT 滤镜并降低缓冲。")
                } header: {
                    Text("显示")
                }

                Section {
                    Picker("皮肤", selection: $settings.skin) {
                        ForEach(SkinType.allCases) { skin in
                            Text(skin.displayName).tag(skin)
                        }
                    }
                    HintText("只影响配色，不影响按键位置。切换后每个系统会各记一套布局。")
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
                    HintText("全局透明度，与单个按键自身的透明度相乘。看不清画面时往左拉。")
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
                    HintText("A+/B+ 是连发键：按住就按这个频率自动连点对应的 A/B。射击游戏 12–15 次/秒比较稳。")
                    Toggle("按键震动", isOn: $settings.hapticsEnabled)
                    HintText("按下虚拟按键时的触感反馈，对耗电影响很小。")
                } header: {
                    Text("虚拟按键")
                } footer: {
                    HintText("按键位置在游戏内「菜单 → 虚拟按键布局编辑」里拖动调整，松手自动保存，每个系统各存一份。")
                }

                Section {
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
                    HintText("手柄由系统蓝牙配对，本 App 只能读取连接状态，无法主动搜索设备。刚连上没反应就点一下「刷新」。")

                    NavigationLink("手柄键位映射") {
                        KeyRemapView()
                    }
                    HintText("把物理按键映射成 FC/GB/GBA 的 A/B/L/R 等。默认映射已经适配大多数 Xbox/PS 手柄，不用改。")

                    Picker("方向输入", selection: $settings.directionInput) {
                        ForEach(DirectionInputMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    HintText("摇杆要推过 45% 才触发，避免误触；十字键与摇杆可以同时启用，按住任意一个都有效。")

                    Toggle("连接手柄时隐藏虚拟按键", isOn: $settings.autoHideControlsOnController)
                    HintText("连上手柄后屏幕按键自动消失，画面完整可见。想临时调回：点游戏画面右上角的手掌图标；拔掉手柄自动恢复。")
                } header: {
                    Text("蓝牙手柄")
                } footer: {
                    DisclosureGroup("如何连接 Xbox / 蓝牙手柄") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("1. Xbox 手柄：按住顶部配对键（⌂ 旁的圆形键）约 3 秒，指示灯快闪")
                            Text("2. 打开 iOS「设置 → 蓝牙」，在列表中选择你的手柄")
                            Text("3. 配对成功后回到本 App，状态会自动更新")
                            Text("4. PS / Switch Pro / 其他标准手柄同理；第三方杂牌手柄可能只被识别为键盘")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    ForEach(ArcadeSupport.biosRequirements) { item in
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
                            Text(item.installed ? "已安装" : "未安装")
                                .font(.caption)
                                .foregroundStyle(item.installed ? .green : .secondary)
                        }
                    }
                    NoticeRow(
                        kind: .warning,
                        title: "BIOS 为什么没有内置",
                        detail: "neogeo.zip / pgm.zip 是厂商版权数据，随 App 分发属于侵权行为。它们通常就在你下载的街机 romset 包里，导入后 App 会自动装到 System 目录。"
                    )
                } header: {
                    Text("街机（FBNeo）")
                } footer: {
                    HintText("游戏请导入整套 romset（.zip/.7z，不要解压）；整合包（外层 zip 里套 romset）会自动拆开。若提示缺文件，把缺的 BIOS 用「+」导入即可。")
                }

                Section {
                    Slider(value: $settings.volume, in: 0...1) {
                        Text("音量")
                    }
                    HintText("这是 App 内部音量，和系统音量叠加；戴耳机时建议先把系统音量调低再进游戏。")
                } header: {
                    Text("音频")
                }

                Section {
                    ForEach(BuiltInResources.cores) { core in
                        HStack {
                            Image(systemName: core.isIncluded ? "checkmark.seal.fill" : "xmark.seal")
                                .foregroundStyle(core.isIncluded ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(core.name)
                                Text(core.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    HintText("四个内核都随 App 打包，首次进游戏即可用，无需联网下载或额外安装。")
                    NoticeRow(kind: .info, title: "不内置的内容", detail: BuiltInResources.romNotice)
                    NoticeRow(kind: .info, title: "BIOS", detail: BuiltInResources.biosNotice)
                } header: {
                    Text("内置资源")
                }

                Section {
                    LabeledContent("版本", value: Self.versionString)
                    LabeledContent("内核", value: "fceumm / SameBoy 1.0.4 / mGBA 0.10.5 / FBNeo")
                    NavigationLink("开源许可") {
                        LicensesView()
                    }
                } header: {
                    Text("关于")
                } footer: {
                    HintText("遇到问题：游戏内菜单 → 关于本机可看到当前内核与分辨率；日志可用 Xcode 的 Console 过滤 MiniRetro。")
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
