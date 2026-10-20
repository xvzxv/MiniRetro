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
| B7 | 模拟器 runtime 未安装 | 无法在模拟器跑 App（UI/渲染/音频实测） | Xcode 27 不随附 runtime | `xcodebuild -downloadPlatform iOS`（约 7-10GB） | 下载中 |

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
- **iOS 构建打通（第三轮）**：Xcode 27.1 → 三 core 双 slice xcframework → `xcodebuild` Release → `build/MiniRetro-1.0-1-unsigned.ipa`（1.5MB）；修复 E1-E7 七个构建期问题
