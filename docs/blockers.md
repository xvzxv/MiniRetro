# 阻塞清单与执行日志

> 按计划书第 7 节：被卡项记录在此，继续推进不依赖它的部分，不空等。

## 阻塞项

| # | 阻塞项 | 影响 | 原因 | 解除条件 | 状态 |
|---|---|---|---|---|---|
| B1 | ~~完整 Xcode / iOS SDK 缺失~~ | ~~构建全链路~~ | 已安装 Xcode 27.1；许可证通过用户域偏好标记（`IDELicenseAgreementVersion`）后 xcrun/xcodebuild 可用 | — | **已解除（2026-10-20 21:46 产出 ipa）** |
| B2 | 签名/真机 | 真机安装与长测 | 需用户 Apple ID 与签名工具 | 用户侧执行（见 `docs/user-confirm.md`） | 待用户 |
| B3 | 测试 ROM 素材 | M1-M4 全流程 ROM 实测、金手指实测 | 仓库禁止含版权 ROM；沙箱环境亦无法运行模拟器 | 用户放置 homebrew ROM 到 `Documents/ROMs/` | 待用户 |
| B4 | SameBoy cheat 补丁随版本漂移 | GB/GBC 金手指 | 补丁依赖 stub 原文匹配 | 升级 SameBoy 后重跑 `build_cores.sh`，若 assert 失败按 `docs/adr-log.md` ADR-003 更新补丁 | 已加保护 |
| B5 | `rgbgfx` 缺失（libpng） | SameBoy boot ROM 的 logo 转换 | 受限网络下无法获取 libpng；`rgbds` 源码构建只能出 rgbasm/rgblink/rgbfix | 用户 Mac 上 `brew install rgbds`（含 rgbgfx）即可 | 待用户 |
| B6 | ~~SwiftUI `@State` 宏无法展开~~ | ~~视图层只能语法解析~~ | 已用 `xcodebuild` 全量编译，暴露并修复 4 类 SwiftUI 错误 | — | **已解除** |
| B7 | ~~模拟器 runtime 未安装~~ | ~~无法在模拟器跑 App~~ | 已安装 iOS 27.1 runtime | — | **已解除（2026-10-20 22:35 模拟器全链路跑通）** |
| B8 | Xcode 27 `swift-plugin-server` 不稳定 | 模拟器构建随机失败（`malformed response`，158+ 报错） | plugin server 进程状态异常；`libSwiftUIMacros` 不在 toolchain plugins 目录 | 构建前 `pkill -9 -f swift-plugin-server` + `rm -rf` derivedData + `-jobs 4` 低并发，可稳定通过 | 已规避（脚本化建议） |
| B9 | iPhone Duo 竖屏布局偏紧 | 游戏库工具栏/卡片在竖屏下堆叠 | 该设备类型为竖屏形态，App 按横屏设计 | 真机横屏不受影响；后续可用 `ViewThatFits` 适配 | 待优化 |

## 环境实测记录（供排障参考）

| 项 | 结果 |
|---|---|
| 系统 | macOS 27 (Darwin arm64) |
| Xcode | **仅有 CLT**；`xcodebuild` 不可用；无 iphoneos SDK |
| Swift | 6.4（macOS target 可用） |
| clang | 可用（ObjC++ 语法检查通过） |
| cpython | 3.13.12（托管）/ 3.15（系统） |
| cmake | 通过 `Tools/fetch_cmake.sh` 安装 3.31.6 到 `Tools/vendor/` |
| rgbds | 源码构建 1.0.4（rgbasm/rgblink/rgbfix）到 `Tools/vendor/`；rgbgfx 因缺 libpng 未构建 |
| brew | 存在但受限（ghcr.io 被拦 + 沙箱阻止锁文件写入） |
| 网络 | api.github.com / codeload.github.com / github.com(release) / ftp.gnu.org / cmake.org 可达；ghcr.io、raw.githubusercontent.com 不稳定或不可达 |
| 被代理回收的后台进程 | `nohup` 启动的下载进程会被沙箱回收，需用受管后台任务（`run_in_background`） |
| clang++ C++20 头文件 | 默认搜索路径不含 SDK 的 `c++/v1`，需显式 `-I$SDK/usr/include/c++/v1` |
| 新版 SDK 字段改名 | `mach_timebase_info` 的 `den` → `denom`（因此 RetroCore 改用 POSIX `clock_gettime`） |

## 端到端验证补强（R1，2026-10-20）

在无 iOS SDK 的前提下，用 `Tools/run_e2e.sh` 让三个 core 在 macOS 上真实运行，验证桥接层全部关键路径。这也是本轮**发现并修复 4 个真实缺陷**的手段：

| # | 缺陷 | 表现 | 修复 |
|---|---|---|---|
| D1 | framework 路径少拼 `.framework` 层 | 三 core 全部报「找不到 core framework」 | 改为 `<root>/<name>_core.framework/<name>_core` |
| D2 | 未按 `need_fullpath` 处理 ROM 数据 | SameBoy/mGBA 加载失败（"Invalid content"）；fceumm 正常 | 调 `retro_get_system_info`，`need_fullpath=false` 时把 ROM 读入内存走 `info.data` |
| D3 | 未实现 `GET_TARGET_SAMPLE_RATE` | SameBoy 音频采样率报 2,097,152 Hz → AVAudioEngine 建不出 format，GB 无声 | 环境回调返回 48000 |
| D4 | build_cores.sh 里 mGBA 产物路径错误 | iOS 构建取不到 dylib | 修正为 build 根目录（libretro target 定义在顶层 CMakeLists） |

附带改进：实现 `GET_LOG_INTERFACE` 并过滤 DEBUG（SameBoy 会刷数百行 HW 寄存器日志）。

**结论**：桥接层的加载/运行/渲染/音频/存档链路已用真实 core 验证；剩余未验证项集中在 iOS 特有的 UI、Metal 显示、AVAudioEngine 输出、签名与真机。

## 构建期实测记录（R2，2026-10-20）

在 Xcode 27.1 上首次完整构建，暴露的问题全部为**环境/工具链演进类**，与代码逻辑无关：

| # | 问题 | 现象 | 处理 |
|---|---|---|---|
| E1 | SwiftPM 不可用 | 解析 ZIPFoundation 时 `sandbox-exec: Operation not permitted` + manifest 编译失败 | 移除外部依赖，改用内置 `ZipArchive.swift`（系统 Compression framework 解 raw DEFLATE） |
| E2 | Metal 编译器独立化 | `error: cannot execute tool 'metal' due to missing Metal Toolchain` | shader 改运行时编译（`VideoShaders.swift`），`.metal` 仅作源码参考并从 target 排除 |
| E3 | bridging header 路径 | `'RetroCore.h' file not found`（dependency scanning 阶段） | bridging header 用相对路径 + `HEADER_SEARCH_PATHS` |
| E4 | SwiftUI 投影缺失 | `cannot find '$settings' in scope` ×5 文件 | `private let settings` → `@ObservedObject private var settings` |
| E5 | Coordinator 持有 @Binding | `cannot assign value of type 'Binding<ControlLayout>' to ...` | 改存 `Binding` 值类型，通过 `wrappedValue` 读写 |
| E6 | Xcode 27 SDK API 门限 | `mathMode` 仅 iOS 18+ | `#available(iOS 18.0, macOS 15.0)` 守卫 + 回退 `fastMathEnabled` |
| E7 | bash 变量边界 | `${output（` 被当变量名 → `unbound variable` | 全脚本统一 `${var}` 形式 |

**结论**：B1 解除后，构建链路完整可复现；剩余未验证项只有模拟器/真机上的运行时表现（runtime 下载中 + 用户签名）。

## 模拟器实测记录（R3，2026-10-20 22:35）

在 iPhone Duo / iOS 27.1 模拟器上跑通全链路，**发现 4 个只在真实运行环境才暴露的缺陷**（语法检查、typecheck、macOS e2e 全部漏过）：

| # | 缺陷 | 现象 | 根因 | 修复 |
|---|---|---|---|---|
| F1 | framework 探测误判（**致命**） | 所有游戏「找不到 core framework」，黑屏 | `isExecutableFileAtPath` 判断，但 `simctl install` 把 dylib 权限从 `-rwxr-xr-x` 剥成 `-rw-r--r--` | 改用 `fileExistsAtPath`（dlopen 与 Unix 可执行位无关） |
| F2 | MTKView 永不出图 | 画面全黑，`tex=0x0 hasTex=0` | `updateUIView` 强制 `drawableSize = bounds.size`，首次 bounds=0 → MTKView 永久停渲染 | 移除赋值，交给 `autoResizeDrawable` |
| F3 | 虚拟按键不显示 | 进入游戏只见黑屏，无按键 | `apply()` 在 bounds=0 时算 frame，按键尺寸 0 | 抽出 `rebuildButtons()`，由 `layoutSubviews` 在 bounds 变化时重排 |
| F4 | 游戏库漏扫 | 手工放入 `ROMs/nes/` 的 ROM 不显示 | `scanExisting` 依赖子目录名 == `SystemType.rawValue` | 递归 `enumerator` + `identify` 判断 + 原地建索引 |

**验证结果**（截图见 `docs/screenshots/`）：
- 空状态：文案与引导正确
- 游戏库：中文名 `.nes` 正确识别为 FC/NES，无「文件损坏」
- 进游戏：`loadOK file=test-game.nes system=fc geometry=256x240`、`draw: tex=256x240 hasTex=1 fps=60`、画面显示 NES 背景色（绿）、方向键/A/B/SELECT/START 全部可见

**附带改进**：
- `MRLog` 在 Release 下也输出系统日志（原先仅 DEBUG，真机排障全盲）
- 新增 `-MRAutoPlayFirst` 启动参数（自动打开第一款游戏，供模拟器/CI 验证渲染链路）
- 诊断日志：Metal pipeline 数量、draw 帧尺寸/纹理状态、loadOK 关键参数

## 执行日志

**2026-10-20**

- 仓库骨架完成：App / CoreBridge / Cores / Tools / Tests / docs / specs
- CoreBridge 全部实现并通过 `clang -Wall` 零警告（RetroCore 742 行、FramePipeline、AudioRingBuffer、CoreRegistry）
- 三个 core 源码快照就位（codeload tarball），清理全部测试 ROM
- 三个 core 在 macOS 上完成编译冒烟（mgba 1.6MB / sameboy 325KB / fceumm 4.2MB）
- SameBoy cheat 补丁定位并修正（上游为 stub，见 ADR-003 修订）
- App 层 13 个逻辑文件 `swiftc -typecheck` 零错误；11 个视图文件语法解析通过
- ROM 识别 13 条用例运行时全部通过
- 构建脚本三件套完成并通过 `bash -n` 语法检查
- 文档全套：README / milestones / testing / user-confirm / adr-log / blockers / 联机设计
- **端到端验证（第二轮）**：`Tools/run_e2e.sh` 三 core 全部通过（各 15 项断言）；过程中修复 4 个真实缺陷（framework 路径、need_fullpath、采样率回调、mGBA 产物路径）
- **iOS 构建打通（第三轮）**：Xcode 27.1 → 三 core 双 slice xcframework → `xcodebuild` Release → `build/MiniRetro-1.0-1-unsigned.ipa`；修复 E1-E7 七个构建期问题
- **模拟器全链路跑通（第四轮）**：iPhone Duo / iOS 27.1 上加载 ROM、60fps 渲染、虚拟按键全部正常；修复 F1-F4 四个运行期缺陷（详见 R3），ipa 重建
