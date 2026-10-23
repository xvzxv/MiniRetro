# 维护指南

面向后续迭代的实用手册。目标：**接手的人（或未来的我）能在 10 分钟内跑起来、改起来、发出去。**

---

## 1. 目录职责

```
App/                     SwiftUI 应用层（26 个文件）
  Models/                数据与状态：AppTypes（ROMEntry/SaveStateEntry/JoypadButton）、
                         ControlLayout（按键布局与持久化）、SettingsStore（UserDefaults）
  Library/               游戏库：LibraryView、LibraryViewModel、ROMImporter、ZipArchive
  Game/                  游戏会话：EmulatorViewModel（中枢）、EmulatorRenderer（Metal）、
                         RetroAudioEngine、VirtualGamepad、GameView、InGameMenuView…
  Settings/              设置页
  Utilities/             CrossImage（跨平台图片）、Haptics、Utilities（MRLog 等）
  Resources/             Assets.xcassets（AppIcon/AccentColor）

CoreBridge/              C/ObjC++ 桥接层（唯一能 #import "libretro.h" 的地方）
  RetroCore.mm           会话核心：dlopen、run 线程、输入、存档、金手指、环境回调
  FramePipeline.mm       软渲帧双缓冲 + 像素格式转换（XRGB8888/RGB565 → BGRA）
  AudioRingBuffer.mm     音频环形缓冲（含快进抽取配合）
  CoreRegistry.c         ROM 识别（魔数 + 扩展名）

Cores/                   上游内核源码快照 + 构建脚本（版本锁定见 .gitmodules 头部）
  artifacts/             ← 构建产物（xcframework），git 不跟踪
Tools/                   构建与验证脚本（vendor/ 为本地工具，git 不跟踪）
Tests/                   单元测试 + 端到端测试程序（e2e_test.mm）
docs/                    里程碑、测试用例、ADR、阻塞、截图
specs/                   联机设计（只设计不实现）
dist/                    交付产物 ipa（本地保留，git 不跟踪）
```

---

## 2. 三条命令

```bash
./Tools/build.sh              # 全量：三 core → xcframework → xcodebuild → dist/*.ipa（约 1.5 分钟）
./Tools/build.sh --skip-cores # 只重编 App（core 未改动时用，约 40 秒）
./Tools/run_e2e.sh            # macOS 端到端：三 core 各 15 项断言（改 CoreBridge 后必跑）
```

模拟器验证（需已装 runtime）：

```bash
xcodebuild -scheme MiniRetro -configuration Release \
  -destination 'platform=iOS Simulator,name=<设备名>' \
  -derivedDataPath build-sim CODE_SIGNING_ALLOWED=NO -jobs 4 build
xcrun simctl install <UDID> build-sim/Build/Products/Release-iphonesimulator/MiniRetro.app
xcrun simctl launch <UDID> com.miniretro.app -MRAutoPlayFirst     # 自动进游戏
xcrun simctl launch <UDID> com.miniretro.app -MRAutoPlayFirst -MRShowMenu  # 自动进游戏并开菜单
xcrun simctl launch <UDID> com.miniretro.app -MRShowSettings      # 直接进设置页
xcrun simctl io <UDID> screenshot /tmp/shot.png
```

> 调试参数是给自动化/排查用的，正常启动无任何影响。

---

## 3. 改动前必读的三条约束

| 约束 | 原因 |
|---|---|
| 只有 CoreBridge 能 `#import "libretro.h"` | App 层通过 `RetroCore` + bridging header 访问；跨层直接引用会让内核符号泄漏到 Swift |
| `retro_run()` 只在专用串行线程；其他 libretro API 走 `_coreMutex` | libretro 不是线程安全的 |
| 帧缓冲/纹理/环形缓冲预分配，run 循环内不 malloc | iPad 6（A10）上逐帧分配会掉帧 |

完整清单见 `.workbuddy/memory/MEMORY.md`（含 iOS 运行期约束、跨层契约、渲染/音频/存档规则）。

---

## 4. 改完代码怎么验

| 改了什么 | 至少跑 |
|---|---|
| Swift 逻辑层（Models/ViewModel/Manager） | `swiftc -typecheck`（见下）+ 模拟器启动 |
| SwiftUI 视图 | **必须 xcodebuild + 模拟器截图**（typecheck 展不开 `@State` 宏，会漏错） |
| CoreBridge（C/ObjC++） | `clang -fsyntax-only` + `./Tools/run_e2e.sh` |
| ROM 识别（CoreRegistry） | `cd Tests && clang -o /tmp/t CoreRegistryTests.c ../CoreBridge/CoreRegistry.c && /tmp/t` |
| 键位布局（ControlLayout） | 改坐标必须递增 `ControlLayouts.currentVersion`，并更新 `LayoutStoreTests` 的几何断言 |
| shader（VideoShaders.swift） | `xcrun -sdk iphoneos metal -c` 无法验证（源码在 Swift 字符串里），只能模拟器看画面 |

Swift 逻辑层快速检查（不需要 Xcode 工程）：

```bash
SDK=$(xcrun --sdk macosx --show-sdk-path)
swiftc -typecheck -sdk "$SDK" -swift-version 5 -target arm64-apple-macosx14.0 \
  -I CoreBridge -import-objc-header App/MiniRetro-Bridging-Header.h \
  App/Models/*.swift App/Utilities/*.swift App/Library/*.swift \
  App/Game/EmulatorViewModel.swift App/Game/CheatManager.swift \
  App/Game/RetroAudioEngine.swift App/Game/EmulatorRenderer.swift \
  App/Game/GameControllerManager.swift App/Game/VideoShaders.swift
```

---

## 5. 发版清单

1. **升版本号**（`project.yml`）
   ```yaml
   MARKETING_VERSION: "1.5"      # 用户可见版本
   CURRENT_PROJECT_VERSION: "6"  # build 号，每次 +1
   ```
2. `./Tools/build.sh` → `dist/MiniRetro-<版本>-<build>-unsigned.ipa`
3. 模拟器启动 + 截图，确认没白屏/没崩
4. 更新 `docs/milestones.md` 与 `docs/progress-log.md`（改了什么、为什么）
5. 新增 ADR（如果是决策类改动）→ `docs/adr-log.md`
6. 提交 + 打 tag：
   ```bash
   git add -A && git commit -m "feat(Mx): ..."
   git tag -a v1.5 -m "v1.5: 一句话说明"
   ```
7. 交付：`dist/*.ipa` 交用户签名装机

---

## 6. 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| `swift-plugin-server produced malformed response`（158+ 报错） | Xcode 27 的宏服务两类故障：① 进程僵死；② 宏服务自身要再套一层 sandbox-exec，在已受沙箱约束的终端里 `sandbox_apply: Operation not permitted` | ① `pkill -9 -f swift-plugin-server` → `-jobs 4` 重编；② 根治：`OTHER_SWIFT_FLAGS="-disable-sandbox"`（build.sh 已内置，swiftc 不再为宏服务套沙箱） |
| `xcrun: You have not agreed to the Xcode license` | 许可证未同意 | `sudo xcodebuild -license accept`；或用 `defaults write com.apple.dt.Xcode IDELicenseAgreementVersion -int 999999` |
| `cannot execute tool 'metal' due to missing Metal Toolchain` | Xcode 26+ Metal 编译器为独立组件 | 本项目已改为运行时编译 shader，不需要该组件；如需 `xcodebuild -downloadComponent MetalToolchain` |
| 模拟器 `Unable to create a device ... Incompatible device` | 该 runtime 不支持所选设备类型 | 换一个已存在的设备，或 `xcodebuild -downloadPlatform iOS` |
| 游戏黑屏、日志 `tex=0x0 hasTex=0` | core 未加载（framework 探测失败） | 检查 `Frameworks/*.framework` 是否嵌入；判断存在只能用 `fileExistsAtPath`（simctl 会剥掉 +x） |
| 按键布局错位 | 旧布局 JSON 与新坐标体系不匹配 | 已用 `ControlLayout.version` 自动作废；如需手动重置，删 App 沙盒 `Documents/Layouts/` |
| 快进没声音 | 旧实现直接丢弃音频 | 已改为按倍率抽取；若仍异常，检查 `mr_audio_sample_batch` 的 decimation 分支 |

---

## 7. 性能基线（iPad 6 / A10）

| 项目 | 目标 | 当前观测 |
|---|---|---|
| 帧率 | ≥ 59 fps | 模拟器 60 fps（macOS e2e 亦 59.5–60.3） |
| 内存 | < 300 MB | 待真机 Instruments 实测 |
| 音频延迟 | < 80 ms | `estimatedLatencyMs` 可在菜单查看 |
| 快照尺寸 | — | fceumm 13.7KB / SameBoy 252KB / mGBA 528KB |

---

## 8. 不要做的事

- ❌ 往仓库塞 ROM（合规红线）
- ❌ 在 run 循环里 malloc / 建纹理 / 拼字符串
- ❌ 改 core 版本却不更新 `.gitmodules` 头部与 `docs/adr-log.md`
- ❌ 改布局坐标体系却不递增 `ControlLayouts.currentVersion`
- ❌ 在 `App/` 里引入任何第三方 SPM 包（SwiftPM 在受限环境不可用，本项目刻意零依赖）

## 街机核心（FBNeo）维护要点（v1.7 起）

| 项 | 说明 |
|---|---|
| 源码 | 不做 submodule（204MB）；首次 `./Tools/build_cores.sh fbneo` 会浅克隆到 `$TMPDIR/miniretro-cores-build/fbneo-src` 并切到锁定 commit（见 ADR-012） |
| 编译 | `make -f Makefile platform=ios-arm64 CC/CXX=... -j`；simulator 需把 CC/CXX 换成 `-target arm64-apple-ios17.0-simulator` |
| 产物 | `fbneo_libretro_ios.dylib`（约 55MB，strip 后 49MB），`install_name` 必须改成 `@rpath/fbneo_core.framework/fbneo_core`，否则 App 启动即 dyld 崩溃 |
| 打包 | `./Tools/make_xcframework.sh fbneo <device.dylib> <sim.dylib>`（脚本已内置 install_name 修正） |
| BIOS | 用户提供：`Documents/System/neogeo.zip`（Neo Geo）、`pgm.zip`（IGS PGM）；导入时按文件名自动识别安装 |
| romset | 整套 `.zip/.7z` 原样入库（`ROMs/arcade/`），**不得解压**；缺文件时 core 报 romset 不完整，App 会提示补 BIOS |
| 已知限制 | 游戏库无法校验 romset 完整性；不支持 CHD（`CHD_LIBRETRO=0`）与街机金手指社区检索 |

## App 图标

图标由 `Tools/gen_app_icon.py` 程序化生成（纯 Python，无外部素材）：
```bash
python3 Tools/gen_app_icon.py     # 产出 App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
```
改配色/形状直接改脚本常量，再重新生成即可；iOS 会自动裁圆角，因此**不要**自己画圆角底板。

## 街机排错顺序（v1.9 实测）

按顺序查，能覆盖 90% 的「街机打不开」：

1. **文件名是不是驱动名**：FBNeo 按 romset 文件名认驱动（`kovsh.zip` 对 `kovsh` 驱动）。
   整合包（外层 zip 里套 romset）必须拆包 —— v1.9 起导入会自动拆，历史条目在启动扫描时自愈。
2. **BIOS 在不在**：`Documents/System/pgm.zip`（PGM）或 `neogeo.zip`（Neo Geo）。
   缺失时内核会自己画一张错误页，列出缺哪几个文件（比前台猜得准）。
3. **帧尺寸**：`FramePipeline` 上限必须 ≥ 内核输出。PGM 实测 640×480，
   旧上限 512×512 会让每帧被静默丢弃 → 加载成功但永久黑屏。现在上限 1024×1024，超限会打日志。

日志抓取：`xcrun simctl spawn booted log show --last 3m --predicate 'process == "MiniRetro"' | grep -E "core:INFO|FramePipeline"`
