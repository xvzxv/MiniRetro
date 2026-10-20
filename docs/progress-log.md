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
