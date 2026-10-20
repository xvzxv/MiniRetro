// SettingsView.swift — 设置页与关于页（M7）
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var controller = GameControllerManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section("核心") {
                    Picker("快进倍率", selection: $settings.fastForwardMultiplier) {
                        Text("2×").tag(2)
                        Text("4×").tag(4)
                    }
                    Toggle("进后台自动暂停", isOn: $settings.autoPauseOnBackground)
                    Toggle("进后台自动即时存档", isOn: $settings.autoSaveOnBackground)
                }

                Section("显示") {
                    Picker("视频滤镜", selection: $settings.filterMode) {
                        ForEach(FilterMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    Toggle("显示 FPS", isOn: $settings.showFPS)
                    Toggle("低性能模式（老机型降级）", isOn: $settings.lowPerformanceMode)
                }

                Section("操作") {
                    Picker("皮肤", selection: $settings.skin) {
                        ForEach(SkinType.allCases) { skin in
                            Text(skin.displayName).tag(skin)
                        }
                    }
                    Toggle("按键震动", isOn: $settings.hapticsEnabled)
                    NavigationLink("手柄键位映射") {
                        KeyRemapView()
                    }
                }

                Section("音频") {
                    Slider(value: $settings.volume, in: 0...1) {
                        Text("音量")
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: "1.0 (1)")
                    LabeledContent("内核", value: "mGBA 0.10.5 / SameBoy 1.0.4 / fceumm")
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
}

// MARK: - 许可汇总（M8）

struct LicensesView: View {
    var body: some View {
        List {
            Section("mGBA") {
                Text("MPL-2.0\n© 2013-2026 Jeffrey Pfau\nhttps://github.com/mgba-emu/mgba")
            }
            Section("SameBoy") {
                Text("MPL-2.0\n© 2015-2026 Lior Halphon\nhttps://github.com/LIJI32/SameBoy")
            }
            Section("fceumm (libretro-fceumm)") {
                Text("GPL-2.0\nhttps://github.com/libretro/libretro-fceumm")
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
