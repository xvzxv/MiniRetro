# 里程碑执行清单（M0→M9）

> 状态图例：`[x]` 已完成并验证 · `[~]` 已实现但验证受环境限制（见 blockers） · `[ ]` 未完成
> 权威定义见项目计划书第 5 节；本文件为执行记录。

---

## M0 脚手架与构建管线

**任务**
- [x] 1. 仓库骨架（README、目录、`.gitignore`：不忽略 `*.xcodeproj`；忽略 `build/`、`Cores/artifacts/`、`Tools/vendor/`）
- [x] 2. `project.yml`（XcodeGen 单源）：target `MiniRetro`，iOS 17.0，含 App/CoreBridge，链接 Metal/AVFoundation/GameController/UniformTypeIdentifiers + ZIPFoundation
- [x] 3. `xcodebuild build` 通过 —— Release 构建成功（Xcode 27.1 / iOS SDK 27.1 / 目标 17.0）
- [x] 4. 三个 core 源码 + `build_cores.sh`（含版本锁定与构建期补丁）
- [x] 5. `Tools/build.sh` 一键链路（build cores → xcodegen → xcodebuild → package ipa），bash 语法检查通过
- [x] 6. 产出未签名 `.ipa` —— `build/MiniRetro-1.0-1-unsigned.ipa`（1.5MB）

**验收**
- [x] clone 新机器三步可复现（依赖全部由 Tools/vendor 或 brew 解决）
- [x] `xcodebuild build` 通过（BUILD SUCCEEDED）
- [x] `Tools/build.sh` 一键产出未签名 ipa
- [~] App 模拟器启动 —— 待下载模拟器 runtime

**已完成的替代验证**
- **端到端运行验证**：`Tools/run_e2e.sh` 让三个 core 在 macOS 上真实加载 ROM、跑满 60fps、抓帧、存档往返，各 15 项断言全部通过
- CoreBridge 全部文件 `clang -Wall -fsyntax-only` 零警告
- App 逻辑层 13 个 Swift 文件 `swiftc -typecheck`（macOS SDK）零错误
- App 视图层 11 个 Swift 文件 `swiftc -frontend -parse` 全通过
- 三个 core 均在 macOS 上完成编译冒烟（mgba dylib 1.6MB / sameboy 325KB / fceumm 4.2MB）

---

## M1 Core 桥接框架

**任务**
- [x] 1. 固定 `libretro.h`（来自 libretro-common @ a3194c18，retro_api_version=1）
- [x] 2. `RetroCore`：dlopen framework、符号解析、`retro_load_game`、专用串行线程 run 循环、stop/unload
- [x] 3. `FramePipeline`：软渲帧 → 双缓冲 → BGRA 缓冲（支持 XRGB8888/RGB565/0RGB1555 三格式转换）
- [x] 4. `AudioRingBuffer` + `RetroAudioEngine`（AVAudioEngine + AVAudioSourceNode 拉取，欠载补静音）
- [x] 5. 键位状态表（原子位掩码）+ 最小虚拟按键（方向 + AB，多指触摸）
- [x] 6. 1 款 FC ROM 全链路验证 —— macOS 端到端已通过（`Tools/run_e2e.sh`：加载 / 60.3fps / 256×240 / 音频有数据 / 存档往返）；iOS 模拟器待 Xcode

**验收**
- [x] FC ROM ≥60fps 运行 —— fceumm E2E 实测 60.3 fps（1.2s/73 帧）
- [x] 音频链路有数据 —— 音频回调写入环形缓冲 8192 帧，采样率 48000 Hz（SameBoy 经 GET_TARGET_SAMPLE_RATE 修正后）
- [~] 虚拟按键可控制游戏 —— 代码就绪，需 UI 实测
- [x] 退后台自动暂停、回前台恢复（`EmulatorViewModel` 监听 willResignActive/didBecomeActive，可配置）
- [x] 帧率/音频延迟打点（`measuredFPS`、`estimatedLatencyMs`，菜单内展示）

---

## M2 GBA 完整

**任务**
- [x] 1. CoreRegistry 接入 mgba（GBA 魔数 0xB2=0x96 + logo 区校验）
- [x] 2. 即时存档：`retro_serialize/unserialize`，**1 自动槽 + 3 手动槽**（v1.3 调整），
      每槽保存当时的游戏画面作为封面缩略图；空槽也展示，便于看清结构
- [x] 2b. **自动存档闭环**（v1.3）：进后台 / 退出游戏时写自动槽；再次进入游戏时自动载入
      （设置项「打开游戏时载入自动存档」默认开启，可关闭）
- [x] 3. 正常存档：`GET_SAVE_DIRECTORY` 下发 + `retro_get_memory_data(SAVE_RAM)` flush/restore
- [x] 4. 金手指：`CheatManager`（增删改、启停、JSON 持久化），`retro_cheat_reset/set` 全量重下发
- [x] 5. 快进：run 循环内多帧推进（2×/4×）+ 快进期静音
- [x] 6. 手柄接入（GameController）+ 合并进状态表
- [~] 7. 金手指实测（GameShark/Action Replay/CodeBreaker 至少一类生效）—— 需模拟器 + ROM

**验收**
- [x] GBA 加载/运行/存档链路 —— mGBA E2E 实测（240×160、RGB565、59.5fps、528KB 快照往返）
- [~] 3 款 GBA ROM 全流程 —— 需真实 ROM 素材
- [~] 金手指实测生效 —— 同上（代码路径完整）
- [x] 存档 serialize/unserialize 往返 —— mGBA E2E 实测 528,448 字节快照往返成功
- [~] 杀 App 重开存档恢复 —— 磁盘落盘已实现，需真机验证

---

## M3 GB/GBC 完整

**任务**
- [x] SameBoy core 接入（复用 CoreBridge）
- [x] 双槽即时存档（与 GBA 共用机制）
- [x] 金手指：**构建期补丁**桥接 SameBoy 原生 cheat API（上游 `retro_cheat_set` 为空 stub，见 ADR-003）
- [x] 快进、手柄；160×144 分辨率经 av_info 正确取得
- [~] 金手指实测 —— 需模拟器 + ROM

**验收**
- [x] GB 加载/运行/存档链路 —— SameBoy E2E 实测（160×144、48kHz、59.5fps、252KB 快照往返）
- [~] 3 款 GB/GBC ROM 全流程
- [~] 黑白/彩色画面滤镜正确（LCD 点阵 shader 已实现，待实测）

---

## M4 FC 完整

**任务**
- [x] fceumm core 接入
- [x] Game Genie 金手指（fceumm 原生 `retro_cheat_set` 已确认实现于 src/drivers/libretro/libretro.c）
- [x] 复用 M2 全部能力
- [x] FC 256×240 分辨率 + 小霸王风格 AB 并列布局（`ControlLayouts.fc`）

**验收**
- [x] FC 加载/运行/存档链路 —— fceumm E2E 实测（256×240、XRGB8888、60.3fps）
- [~] 3 款 FC ROM 全流程；金手指生效 —— 需真实 ROM 素材

---

## M5 游戏库与 ROM 管理

**任务**
- [x] 1. `UIDocumentPicker` 导入 + 沙盒扫描 + zip 解压（ZIPFoundation，多 ROM 批量）
- [x] 2. 识别：后缀 + 文件头魔数双保险（`CoreRegistry.c`，13 条用例实测通过）
- [x] 3. 游戏库：网格/列表切换、封面（取最新缩略图，无则占位）、收藏、最近游玩排序、搜索
- [x] 4. 本地 JSON 索引（`Library/index.json`，增量 upsert、缺失文件标记损坏）

**验收**
- [~] 导入 10+ ROM（含 zip 多 ROM）正确分类 —— 逻辑就绪，待实测
- [~] 100 ROM 级列表流畅 —— LazyVGrid + 索引内存缓存，待实测

---

## M6 虚拟按键 / 手柄 / 皮肤

**任务**
- [x] 1. 三套默认布局：FC（无 LR）、GB（无 LR）、GBA（含 LR），拇指覆盖范围已按横屏比例设定
- [x] 2. 布局编辑器：拖动位置 / 尺寸 / 透明度，JSON 持久化（`Layouts/<system>-<skin>.json`）
- [x] 3. 皮肤：经典红白机（深红 + 白描边）、透明极简（半透明灰）
- [x] 4. 手柄键位自定义映射表 + UI（`KeyRemapView`，UserDefaults 持久化）
- [x] 5. **布局改为传统有线手柄形态**（2026-10-20 用户需求）：
      方向键左下（十字等比补偿，横屏不变形）、SELECT/START 椭圆居中偏下、
      A 左 B 右（与 FC 传统互换）、A/B 与方向键同高、连发 A+/B+ 位于 A/B 正上方
- [x] 6. **连发键**：`JoypadButton.turboA/turboB`（前端保留 ID 100/101，不下发 core），
      EmulatorViewModel 用定时器翻转相位驱动 A/B，频率可在设置中调（5–20 次/秒）
- [x] 7. **按键透明度**：默认全局 60%（单键 opacity × 全局控制），设置页滑杆 25%–100% 实时生效
- [x] 8. **蓝牙手柄管理**：设置页显示连接状态/设备名/电量 + 连接引导（iOS 只能由系统蓝牙配对，
      App 通过 GameController 框架接入）+ 键位映射入口
- [x] 9. **跨宽高比自适应布局**（v1.1）：引入 `HorizontalAnchor`（leading/trailing/center），
      间距与尺寸统一按短边，左右边距镜像对称；iPad 1.33:1 与 iPhone 2.17:1 表现一致
- [x] 10. **配色改为灰色半透明**（v1.1）：去掉经典红，改为常见手柄灰（white 0.42 × 全局透明度）

**验收**
- [~] 三套布局横屏手感 —— 待真机/模拟器实测（坐标已按 0-1 归一化，适配任意尺寸）
- [x] 自定义布局重启不丢失（`LayoutStoreTests.testLayoutRoundTrip` 覆盖 JSON 往返）
- [~] 蓝牙手柄全键可用且可重映射 —— 代码就绪，需真机配对手柄验证
- [x] 按键布局按传统有线手柄形态重排（模拟器截图验证：`docs/screenshots/04-in-game-new-layout.png`）
- [x] 连发键与透明度设置项（逻辑实现 + 设置页渲染验证）

---

## M7 滤镜 / 震动 / 设置页

**任务**
- [x] 1. Metal shader 四档：整数倍（最近邻）、平滑（线性）、CRT（扫描线+暗角+色差）、GB LCD 点阵
- [x] 2. 震动开关（`Haptics`，按键轻触 / 存档成功；受 `hapticsEnabled` 控制）
- [x] 3. 设置页：快进倍率、自动暂停/自动存档、滤镜、音量、皮肤、低性能模式、FPS 显示
- [x] 4. 关于页：LICENSE 汇总（mGBA/SameBoy/fceumm/libretro/XcodeGen）
- [x] 5. **画面比例**（v1.2）：MTLViewport aspect-fit，设置项「保持游戏原始比例」默认开启，
      关闭则全屏拉伸；按键层仍按屏幕布局（不跟画面收缩）
- [x] 6. **快进增强**（v1.2）：倍率上限 4× → 8×（2/3/4/6/8 可选）；
      主界面 HUD 增加快进快捷开关（绿色高亮表示激活），无需进菜单
- [x] 7. **快进音频修复**（v1.2）：原实现快进时直接丢弃音频（静音）；
      改为按倍率抽取后写入，输出速率恒定、音调随倍率升高，音乐可辨

**验收**
- [~] 滤镜实时切换不卡顿 —— 运行时按 shader 名切换 pipeline，待实测
- [x] 设置项全部生效并持久化（`SettingsStore` UserDefaults）
- [x] 低端机降级：低性能模式下 CRT 自动回退为整数倍（iPad 6 保护）

---

## M8 打磨与稳定性

**任务**
- [x] 测试用例文档 `docs/testing.md`
- [x] 用户确认清单 `docs/user-confirm.md`（真机长测、低电量、来电打断、发热）
- [x] 内存关注点整理（run 循环无逐帧分配、帧缓冲预分配、纹理每帧复用、ring buffer 预分配）
- [ ] 2h 连续游玩 + Leaks 实测 —— 需 Xcode Instruments（blockers B1）
- [x] README 补齐（依赖、构建、侧载、限制）

---

## M9 联机设计文档（只写不开发）

- [x] `specs/online-play-design.md`：三 core netplay 支持调研、方案对比、接口预留、工作量估算、TODO 标注
- [x] 代码预留点：`RetroSessionPlaceholder` 协议（CoreBridge/RetroCore.h）、UI 入口占位说明
- [x] 无任何联机实现代码
