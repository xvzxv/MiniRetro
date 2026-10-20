# 阻塞清单与执行日志

> 按计划书第 7 节：被卡项记录在此，继续推进不依赖它的部分，不空等。

## 阻塞项

| # | 阻塞项 | 影响 | 原因 | 解除条件 | 状态 |
|---|---|---|---|---|---|
| B1 | 完整 Xcode / iOS SDK 缺失 | `xcodebuild`、iOS 模拟器、xcframework 交叉编译、`.ipa` 产出、Instruments 检测 | 当前机器只有 Command Line Tools（`xcode-select` 指向 CLT，`xcrun --sdk iphoneos` 报 SDK 不存在） | 安装完整 Xcode 16+ 并 `sudo xcode-select -s /Applications/Xcode.app` | 待解除 |
| B2 | 签名/真机 | 真机安装与长测 | 需用户 Apple ID 与签名工具 | 用户侧执行（见 `docs/user-confirm.md`） | 待用户 |
| B3 | 测试 ROM 素材 | M1-M4 全流程 ROM 实测、金手指实测 | 仓库禁止含版权 ROM；沙箱环境亦无法运行模拟器 | 用户放置 homebrew ROM 到 `Documents/ROMs/` | 待用户 |
| B4 | SameBoy cheat 补丁随版本漂移 | GB/GBC 金手指 | 补丁依赖 stub 原文匹配 | 升级 SameBoy 后重跑 `build_cores.sh`，若 assert 失败按 `docs/adr-log.md` ADR-003 更新补丁 | 已加保护 |
| B5 | `rgbgfx` 缺失（libpng） | SameBoy boot ROM 的 logo 转换 | 受限网络下无法获取 libpng；`rgbds` 源码构建只能出 rgbasm/rgblink/rgbfix | 用户 Mac 上 `brew install rgbds`（含 rgbgfx）即可 | 待用户 |
| B6 | SwiftUI `@State` 宏无法展开 | 视图层只能做语法解析，不能全量类型检查 | CLT 的 Swift 工具链不含 `libSwiftUIMacros`（仅完整 Xcode 提供） | 安装完整 Xcode 后 `xcodebuild` 自然覆盖 | 待解除 |

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
