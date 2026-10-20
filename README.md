# MiniRetro — 小霸王复古模拟器（iOS/iPadOS）

FC/NES、GB/GBC、GBA 三格式原生模拟器。SwiftUI + Metal + libretro 内核（mGBA / SameBoy / fceumm）。
侧载自签名安装，不上 App Store。**不含任何 ROM**——游戏数据由你自行导入。

- 部署目标：iOS / iPadOS **17.0+**（iPad 6 起，向上兼容当前系统）
- 架构：App（SwiftUI）→ CoreBridge（C/ObjC++ 唯一内核入口）→ libretro core（动态 framework）
- 构建：XcodeGen 单源工程 + `Tools/build.sh` 一键产出未签名 `.ipa`

---

## 快速开始（Mac）

```bash
# 1. 依赖（一次）
brew install xcodegen cmake rgbds

# 2. 一键构建：编译三个 core → 生成工程 → xcodebuild → 打包未签名 ipa
./Tools/build.sh

# 产物
#   build/MiniRetro-1.0-1-unsigned.ipa
```

若签名工具不接受完全无签名 ipa：

```bash
./Tools/build.sh --adhoc     # ad-hoc 签名（CODE_SIGN_IDENTITY=-）
```

调试 App 层时可跳过 core 编译（需先成功构建过一次）：

```bash
./Tools/build.sh --skip-cores
```

### 无 iOS SDK 时的端到端自检（macOS）

```bash
./Tools/run_e2e.sh            # 三 core 全测；也可 ./Tools/run_e2e.sh sameboy
```

脚本会自动生成极简 homebrew 测试 ROM、编译 macOS 版 core、复刻 iOS 的
`Frameworks/*.framework` 布局，然后验证加载 / 帧率 / 像素 / 音频 / 存档往返。
这是在没有完整 Xcode 时对桥接层能做的最强验证。

### 依赖说明

| 依赖 | 用途 | 安装 |
|---|---|---|
| Xcode 16+ | 编译 iOS App、打包 xcframework | App Store / 开发者站点 |
| XcodeGen | 由 `project.yml` 生成 `.xcodeproj` | `brew install xcodegen` |
| cmake | 编译 mGBA（其 upstream 只提供 CMake 构建） | `brew install cmake`；若 brew 不可用：`./Tools/fetch_cmake.sh` |
| rgbds | Assembling SameBoy 的 boot ROM（来自 `.asm`） | `brew install rgbds`；若 brew 不可用：`./Tools/fetch_rgbds.sh` |
| ~~ZIPFoundation~~ | ~~zip 解压~~ → 已改为内置实现（`App/Library/ZipArchive.swift`，系统 Compression framework） | 无需安装 |

> `Tools/vendor/`（自行下载的 cmake/rgbds 二进制）已在 `.gitignore` 中，不入库。

---

## 侧载安装（用户自备签名工具）

本仓库**不内置签名/重签脚本**，签名流程由你自行管理：

1. 用 **Sideloadly / AltStore / 自签证书** 对 `build/*.ipa` 签名
2. 免费 Apple ID 的 7 天过期需自行重签（Sideloadly 可一键重签）
3. 若工具拒绝未签名 ipa，改用 `./Tools/build.sh --adhoc`

---

## 使用

1. 打开 App → 右上角 `+` → 从「文件」App 选择 `.nes/.fds/.gb/.gbc/.gba`（支持 `.zip` 批量，自动解压分类）
2. 点击游戏卡片进入，横屏游玩
3. 左上角菜单：即时存档（4 槽 + 自动存）/ 金手指 / 快进 / 滤镜 / 布局编辑 / 手柄键位

**虚拟按键**：FC（AB 并列小霸王风格）、GB、GBA（含 LR）三套默认布局，均可在菜单 →「虚拟按键布局编辑」中拖动调整并持久化。

**金手指**：FC → Game Genie；GB/GBC → GameShark / Game Genie；GBA → GameShark / Action Replay / CodeBreaker。

---

## 目录结构

```
App/              SwiftUI 源码（Library / Game / Settings / Models / Utilities）
CoreBridge/       C/ObjC++ 桥接层（libretro.h、RetroCore、FramePipeline、
                  AudioRingBuffer、CoreRegistry）——App 层唯一可碰内核的边界
Cores/
  mgba/ sameboy/ fceumm/   上游源码快照（版本见 .gitmodules）
  libretro.h               libretro API 头文件（固定版本）
  build_cores.sh           交叉编译三 core → artifacts/*.xcframework
Tools/
  build.sh                 一键构建
  package_ipa.sh           打包未签名 ipa
  fetch_cmake.sh           备用获取 cmake
  fetch_rgbds.sh           备用获取 rgbds
Tests/                   单元测试（ROM 识别 / 布局持久化 / 存档往返）
docs/                    里程碑、测试用例、用户确认清单、ADR 记录、阻塞清单
specs/                   联机设计文档（本期只设计不实现）
```

---

## 设计约束（实现必须遵守）

- **只有 CoreBridge 能 `#import "libretro.h"`**，App 层不得直接调用内核
- `retro_run()` 在专用串行线程；主线程只做 UI 与事件投递
- 输入统一走「键位状态表」：虚拟按键 / 蓝牙手柄 → 原子位掩码 → `retro_input_state`
- 新系统 API 一律 `#available` 守卫；部署目标固定 17.0

---

## 已知限制与合规

- **不含 ROM**：仓库不提交任何有版权 ROM；测试用 homebrew/free ROM 请自行准备
- **SameBoy 金手指**：上游 `retro_cheat_set` 为空 stub，构建时打补丁桥接 SameBoy 原生 cheat API（见 `docs/adr-log.md` ADR-003）
- **联机**：本期只输出设计文档（`specs/online-play-design.md`），无实现代码
- **签名**：仓库不承担签名/重签，仅产未签名 ipa
- 三个 core 的 LICENSE 保留在各自目录；App 内「设置 → 关于 → 开源许可」汇总展示

---

## 构建验证状态

当前仓库的验证程度（详见 `docs/blockers.md`）：

| 项目 | 状态 |
|---|---|
| CoreBridge（C/ObjC++） | ✅ clang `-Wall` 编译零警告 |
| App 逻辑层（Swift） | ✅ macOS SDK `swiftc -typecheck` 零错误 |
| App 视图层（SwiftUI） | ✅ 语法解析通过（`@State` 宏需完整 Xcode 展开，见限制） |
| mgba / SameBoy / fceumm | ✅ 三 core 均在 macOS 上编译通过 |
| **端到端运行**（加载 → 60fps → 抓帧 → 存档往返） | ✅ 三 core 全部通过，各 15 项断言（`./Tools/run_e2e.sh`） |
| ROM 识别逻辑 | ✅ 13 条用例运行时全部通过 |
| **iOS 完整构建** | ✅ `xcodebuild` Release 成功，产出 `build/MiniRetro-1.0-1-unsigned.ipa`（1.5MB，arm64 / iOS 17.0，三个 core 全部嵌入） |
| iOS 模拟器运行 | ⏳ 需下载模拟器 runtime（`xcodebuild -downloadPlatform iOS`） |
