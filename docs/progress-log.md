# 进度日志

> 每个里程碑完成时追加 3 行以内总结（计划书第 7 节）。

## 2026-10-20

**M0 脚手架与构建管线** — 完成仓库骨架、`project.yml`、三 core 源码快照（codeload 锁定版本）、`build_cores.sh` / `build.sh` / `package_ipa.sh`。
三 core 在 macOS 上编译冒烟通过（mgba / SameBoy / fceumm 均产出 dylib）；iOS 交叉编译与 ipa 待完整 Xcode。

**M1 Core 桥接框架** — RetroCore（dlopen + 串行 run 线程 + 帧限速）、FramePipeline（双缓冲 + 三格式转换）、AudioRingBuffer + AVAudioEngine、原子键位表、多指虚拟按键。
全部通过 `clang -Wall` 零警告；运行实测需模拟器。

**M2/M3/M4 三格式接入** — CoreRegistry 魔数+扩展名双保险（13 条用例实测通过）；存档/金手指/快进/手柄统一抽象；SameBoy 金手指走上游 stub 补丁 + 原生 API 桥接（ADR-003 修订）。
金手指与 ROM 全流程实测需用户提供 ROM。

**M5 游戏库** — 文档选择器 + zip 批量解压（ZIPFoundation）+ 沙盒增量扫描 + JSON 索引 + 网格/列表/收藏/搜索/最近游玩。

**M6 按键/手柄/皮肤** — 三套默认布局、UIKit 多指按键层、拖动式布局编辑器（JSON 持久化）、手柄键位重映射、两套皮肤。

**M7 滤镜/设置** — Metal 四档滤镜（整数倍/平滑/CRT/LCD）、震动开关、设置页全项持久化、低性能模式自动降级、许可页。

**M8 文档** — `testing.md` 用例表、`user-confirm.md` 真机清单、`blockers.md` 阻塞登记、README 补齐。

**M9 联机设计** — `specs/online-play-design.md`：三 core 确定性评估、四方案对比、锁步+快照纠正方案、接口预留点、3–4 周工作量估算；无实现代码。

**端到端验证（第二轮，同日）** — 新增 `Tools/run_e2e.sh`：自动生成极简 homebrew ROM（NES/GB/GBA）、编译 macOS 版三 core、复刻 iOS 的 framework 嵌入布局，用真实 RetroCore 跑完整链路。
三 core 各 15 项断言全通过（60fps / 像素有效 / 音频有数据 / 存档往返）；过程中修复 framework 路径、need_fullpath、GET_TARGET_SAMPLE_RATE、mGBA 产物路径四个真实缺陷。

**iOS 构建打通（2026-10-20 21:46）** — Xcode 27.1 + iOS SDK 27.1 环境下完成全量构建：三 core 交叉编译（device + simulator）→ xcframework → `xcodebuild` Release → `MiniRetro-1.0-1-unsigned.ipa`（1.5MB，arm64/iOS 17.0，三 core 已嵌入）。
处理了 7 个构建期问题：移除 ZIPFoundation（SwiftPM 在沙箱不可用，改内置 zip 解压）、Metal 编译器独立组件化（改运行时编译 shader）、bridging header 路径、SwiftUI `$settings` 投影、Coordinator 的 @Binding、`mathMode` 的 iOS 18 门限、bash 全角括号变量边界。

**缺陷修复：.nes 导入全部失败（2026-10-20 22:06，用户反馈）** — 根因是 C 层返回 `system_id="nes"` 而 `SystemType` 的 case 名是 `fc`，`SystemType(rawValue:)` 直接返回 nil；同时失败分支只建索引不落盘导致「文件损坏」卡片无法处理。已改为显式映射表 + 失败落盘 + 补 UNIF 识别；新增 7 项 XCTest 与真实 ROMImporter 可执行验证（6 项），ipa 重建。

**按键布局重构 + 连发 + 手柄管理（2026-10-20 22:46，用户需求）** — 虚拟按键改为传统有线手柄形态：方向键左下、SELECT/START 椭圆居中偏下、A 左 B 右且与方向键同高、连发 A+/B+ 在正上方（十字做了横屏宽高比补偿，避免拉成长方形）。
新增连发键（前端 ID 100/101 + 定时翻转相位，频率可调 5–20/s）、全局按键透明度（默认 60%，设置页滑杆实时生效）、设置页蓝牙手柄区块（连接状态/电量/引导/映射入口）。模拟器截图验证布局，ipa 重建。

**v1.1：布局跨宽高比自适应 + 灰色配色（2026-10-20 22:56，用户反馈）** — iPhone 18 Pro Max（2.17:1）上按键比例失真、左右不对称、配色偏红。
引入 `HorizontalAnchor` 模型（左组按左边缘、右组按右边缘镜像、居中组按屏宽），尺寸与十字间距统一按短边，边距由同一 sideMargin 推导；配色改为灰色半透明并修正 highlight 漏乘全局透明度。版本号升至 1.1（build 2），ipa 重建。

**v1.2：画面比例 + 快进 8 倍 + 快进音频修复（2026-10-20 23:00，用户反馈）** — 新增 MTLViewport aspect-fit（设置项「保持游戏原始比例」默认开启，可关全屏拉伸）；快进倍率上限提到 8×（2/3/4/6/8）；游戏界面 HUD 增加快进快捷开关；修复快进时完全静音的缺陷（原代码 `if (!fastForwardActive)` 直接丢弃音频，改为按倍率抽取，输出速率恒定）。版本号 1.2（build 3），ipa 重建。

**v1.3：存档槽位重构 + 自动存档闭环（2026-10-23，用户需求）** — 槽位明确为「1 个自动槽 + 3 个手动槽」，空槽也展示（虚线占位 + 「空」），每槽保存当时的游戏画面作为封面。
自动存档闭环：进后台/退出游戏时写自动槽 → 下次进入游戏自动载入（设置项可关闭）。
修复 auto 槽原本缺缩略图与真实时间戳的问题（原来用 `Date()` 且 thumbnailName 为 nil）。版本号 1.3（build 4）。

**v1.4：布局算法 v3（2026-10-23，用户二次反馈）** — 真机上按键散开、SELECT 跑到左侧，根因是旧布局 JSON 仍生效（坐标公式已变）+ SELECT/START 用屏宽比例定间距。
引入 `ControlLayout.version`（旧文件自动作废）、新增 `.centerOffset` 锚点（居中但按短边定间距）、组内 pitch 统一为「直径 × 系数」。SELECT/START 间隙调到 0.048 短边倍数，不再粘连。版本 1.4（build 5）。

**v1.5：快进倍率修正 + 布局 v4（2026-10-23 23:36，用户反馈）** — 快进「2×/4× 快太多」的根因是 `runLoopBody` 里限速被 `if (!fast)` 包住，快进时完全不休眠，实际速度取决于 CPU。改为每轮固定推进一个显示帧时长，e2e 实测 4× = 4.00×（240 帧/秒）。
布局：方向键右移（sideMargin 0.05→0.115）、A/B 尺寸 0.112→0.125 与方向键一致、修正 dpadPitch 被当半距使用导致间距翻倍的错误。版本 1.5（build 6）。
