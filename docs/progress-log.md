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

**v1.6：布局 v5 修复「按键挤到一起」（2026-10-21，用户反馈）** — v1.5 把 dpadPitch 从「误用的半距」改成全距后，十字键四键几乎相切（间隙仅 6.6pt@440），连发键与 A/B 也只剩 7.3pt，用户反馈「全部挤到一起」。
布局 v5：dpadPitch 0.140→0.260（键间留空 ≈59pt，恢复散开十字观感）、turboPitchY 0.132→0.151（留空 ≈16pt）；方向键右移与 A/B 等大/对称保持不变（两组水平宽度都 ≈0.385×短边，镜像对称）。
模拟器截图验证（docs/screenshots/11-layout-v5.png）。顺带根治 Xcode 27 构建假错误：根因是宏服务需嵌套 sandbox-exec，受沙箱终端里必然失败，build.sh 现内置 `OTHER_SWIFT_FLAGS="-disable-sandbox"`。版本 1.6（build 7）。

**v1.7：六项功能与缺陷修复（2026-10-21，用户需求）**

1. **「每次重启多出一个文件已损坏条目」根治** — 根因有两层：① 旧索引里 `relativePath` 带 `ROMs/` 前缀
   （早期版本写法），实际文件在 `fc/x.nes`，于是校验必然失败被标 corrupted；② `scanExisting` 只打标记
   从不清理，幽灵条目永久残留；③ `remove()` 只删索引不删文件，删掉后下次扫描又回来。
   修复：`LibraryIndex.normalize()` 归一化路径 + 合并重复；`scanExisting` 直接删除文件不存在的条目；
   `remove()` 同时删文件/存档/金手指；导入按「文件名+字节数+系统」去重，不再生成 `x-1.nes`。
2. **快进 16×** + **进菜单/设置自动暂停**（设置项 `pauseOnOpenMenu`，关闭菜单恢复到打开前状态）。
3. **金手指社区查找** — 预生成 `App/Resources/CheatIndex.json`（libretro-database 的 FC/GB/GBC/GBA 共 5231 条
   游戏条目，227KB），搜索离线；命中后从 raw.githubusercontent.com 抓 `.cht` 解析。
   新增 `CheatType.rawRAM`（社区库主流格式 `00AE:41`，与 Game Genie 区分）。
4. **手柄方向输入可选**：十字键 / 左摇杆 / 两者（死区 45%），映射界面不变。
5. **街机支持（FBNeo）** — 见 ADR-012。新增 `SystemType.arcade`、zip 双语义、BIOS 自动安装到 `System/`、
   街机布局（十字键 + A/B/C/D 2×2 + SELECT/START）。
6. **自测** — 新增 `Tools/run_romlib_test.sh`（28 项断言，含真实 ROM 与脏索引注入），
   模拟器实测：脏索引 4 条 → 重启后 2 条且无损坏标记；菜单打开 `paused=1`。

版本 1.7（build 8），ipa 15MB（FBNeo 49MB/切片）。

**v1.8：App 图标 + 手柄连接自动隐藏虚拟按键（2026-10-22，用户需求）**

1. **App 图标**：此前 `AppIcon.appiconset` 只有空的 Contents.json，装到桌面是白底占位。
   新增 `Tools/gen_app_icon.py` 程序化生成 1024×1024 无 alpha 图标（米白底 + 红白机手柄正面：
   朱红机身 + 米白十字键 + 并排双键），产物 `App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`。
   为什么程序生成而不是找素材：形状可控、可复现、无版权问题，40pt 下仍能认出是手柄。
2. **连接手柄自动隐藏虚拟按键**：新增设置 `autoHideControlsOnController`（默认开，设置页与游戏内菜单都可切）。
   检测到手柄连接时 `GameView` 不渲染 `VirtualGamepad`（带淡入淡出）；HUD 右上角图标可临时调回（hand.tap），
   手柄断开自动复位。虚拟按键层消失后画面完全不被遮挡，适合手柄玩家。
3. 调试钩子：`-MRFakeController` / `-MRNoController` 强制两种连接状态，便于无手柄环境验证。

**实测**：模拟器（iPhone Duo）`connected=1 → hidden=1`（画面无按键、HUD 出现 hand.tap）、
`connected=0 → hidden=0`（按键正常显示）；桌面图标渲染正常。版本 1.8（build 9）。

**v1.9：街机黑屏根因 + 手柄方向 + 远程导入（2026-10-23，用户反馈）**

1. **手柄方向「按一下动一下」** — 根因：十字键与摇杆共用一张方向状态表，摇杆每帧回调（停在死区内=全 false）
   立刻把十字键按住的方向清掉。抽成 `DirectionInputMerger`（两源分开记录后取或），
   并补了 4 项单测，其中一条直接复现旧 bug 场景。
2. **街机导入后打不开 —— 两个真原因**
   - ① **壳包**：`kovsh_v13.zip` 里套着 `kovsh.zip`（外加 ini/说明）。FBNeo 按**文件名**认驱动名，
     喂外层壳包必然 no driver。导入改为自动拆包（BIOS 装 System/、内层 romset 逐个入库），
     并对 v1.8 已入库的壳包做启动自愈。
   - ② **帧尺寸上限**：`FramePipeline` 写死 512×512，PGM 输出 640×480 → **每帧被静默丢弃** → 黑屏。
     上限提到 1024×1024，超限时打日志（静默丢弃是最难查的一类 bug）。
   - 顺带修：`statusMessage` 从来没在界面上显示过（加载失败/缺 BIOS 全是哑的），现已做成可点掉的提示条。
   - 验证：真包实测 `Romset name: kovsh` → 640×480 出帧 60fps → FBNeo 自绘「缺 pgm BIOS 中的 6 个文件」。
     **结论：包本身还缺 PGM BIOS（pgm.zip），App 不内置、也不能内置。**
3. **远程导入**（直链 + WebDAV）：游戏库右上角 🌐 → 粘贴 http(s) 直链，或连 WebDAV
   （群晖/坚果云/Nextcloud/InfiniCLOUD）浏览下载；下载后走同一套导入流程（压缩包/壳包自动处理）。
   WebDAV 密码进钥匙串，服务器/用户名进 UserDefaults。
   实测：本地 HTTP 服务器下载 21,158,101 字节 → 导入 1 款（拆出 kovsh.zip）；
   WebDAV 列目录 3 项、中文名解码正常。ATS 增加 NSAllowsLocalNetworking（局域网 http）。
4. **未做：ROM 站点自动搜索下载** — 见交付说明（版权 + 站点安全性），改为通用远程导入 + 手动链接。

版本 1.9（build 10）。
