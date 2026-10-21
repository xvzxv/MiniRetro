# ADR 变更记录（执行期实测修订）

> 计划书第 3.1 节的 ADR 为初始决策。执行中出现与假设不符的实测结果，按计划书第 7 节要求「不静默偏离」在此记录。

---

## ADR-003 修订：金手指实现路径（2026-10-20）

**原假设**：四个 core 均已支持 `retro_cheat_set`，统一走 libretro 接口即可。

**实测结果**：

| core | `retro_cheat_set` 实现 | 结论 |
|---|---|---|
| fceumm | `src/drivers/libretro/libretro.c:3474` 真实实现（Game Genie） | ✅ 走标准接口 |
| mGBA 0.10.5 | `src/platform/libretro/libretro.c` 真实实现 | ✅ 走标准接口 |
| SameBoy 1.0.4 | `libretro/libretro.c:1904-1912` **空 stub**（函数体仅 `(void)` 抑制警告） | ❌ 标准接口无效 |

**决策**：SameBoy 采用「构建期补丁 + 原生 cheat API 桥接」：

1. `build_cores.sh` 在构建副本（`$TMPDIR/miniretro-cores-build`）中打补丁，**不修改仓库内上游快照**
2. 补丁 1：`libretro/Makefile.common` 去掉 `-DGB_DISABLE_CHEATS`，并把 `Core/cheats.c` 加入 `SOURCES_C`（原构建未编译该文件，去掉宏后需要链接实现）
3. 补丁 2：把 `retro_cheat_reset` / `retro_cheat_set` 的空 stub **替换**为调用 `GB_remove_all_cheats` / `GB_import_cheat`（SameBoy 双实例 `gameboy[2]`，两份都导入以覆盖 SGB 双机模式）
4. 补丁缺失保护：若上游改动导致 stub 原文不匹配，脚本 `assert` 失败并提示更新补丁，不静默产出错误二进制

**验证**：macOS 冒烟编译通过，`nm` 确认 `_retro_cheat_reset` / `_retro_cheat_set` 为 `T`（已定义导出），`cheats_libretro.c.o` 参与链接。

**影响**：GB/GBC 金手指可用；补丁随 core 版本升级需复核（已在 `docs/blockers.md` B4 登记）。

---

## ADR-001/002 补充：core 源码获取方式（2026-10-20）

**原方案**：git submodule 锁定 tag。

**实测**：当前网络环境 `git clone/ls-remote` 被代理拦截（401 需交互凭证），codeload.github.com 的 tarball 直连可用。

**决策**：仓库内 `Cores/{mgba,sameboy,fceumm}` 为**上游 tag 源码快照**，版本锁定记录在 `.gitmodules` 头部注释与本节：

| core | 上游 | 版本 | 获取 |
|---|---|---|---|
| mGBA | mgba-emu/mgba | 0.10.5 (tag) | `codeload.github.com/mgba-emu/mgba/tar.gz/refs/tags/0.10.5` |
| SameBoy | LIJI32/SameBoy | v1.0.4 (tag) | `.../LIJI32/SameBoy/tar.gz/refs/tags/v1.0.4` |
| fceumm | libretro/libretro-fceumm | ac0d00a（master） | `.../libretro-fceumm/tar.gz/ac0d00a7...` |

有凭证的环境可改回 submodule（`.gitmodules` 内有命令），无需改动代码。

**合规清理**：删除上游仓库中的测试 ROM 与非构建必需二进制：
`mgba/cinema/`（GBA/GB 测试 ROM 套件）、`mgba/src/platform/python/tests`、`mgba/src/third-party/libpng/tests`、`fceumm/tests/`、`sameboy/.github/`（CI 测试 ROM）。复查后仓库内 `.nes/.gba/.gb/.gbc/.fds` 数量为 **0**。

---

## ADR-004 补充：libretro.h 来源（2026-10-20）

**原方案**：`libretro/libretro.h` 仓库固定版本。

**实测**：该独立仓库已下线（API 404）。改从 `libretro/libretro-common` 的 `include/libretro.h` 获取：

- 来源：`libretro/libretro-common @ a3194c18ba65ef89734e1898a2f61403c255d368`
- 校验：`RETRO_API_VERSION == 1`（9105 行）
- 该副本即各 core 构建时实际引用的同源头文件

---

## ADR-006 补充：构建路径必须无空格（2026-10-20）

**实测**：SameBoy / fceumm 官方 libretro Makefile 使用 `$(abspath ...)` 且未加引号，路径含空格（如 `.../Project Alpha/...`）时被截断，报 `No rule to make target`。

**决策**：`build_cores.sh` 统一在 `${TMPDIR}/miniretro-cores-build`（无空格）下构建，产物再拷回 `Cores/artifacts/`。已在脚本注释中说明原因。

---

## ADR-001 补充：桥接层四处实测修订（2026-10-20）

端到端测试（`Tools/run_e2e.sh`，真实 core + 极简 ROM）暴露并修复：

1. **framework 布局**：嵌入路径必须是 `<root>/<name>_core.framework/<name>_core`，此前漏了 `.framework` 一层。
2. **`need_fullpath` 语义**：`retro_get_system_info` 必须查询后再决定传 `info.data` 还是 `info.path`。
   fceumm = true（自行 fopen）；SameBoy / mGBA = false（必须内存注入）。只传 path 会导致后两者 `retro_load_game` 失败。
3. **`GET_TARGET_SAMPLE_RATE`（实验性，81）必须实现**：SameBoy 用它决定内部重采样率；不实现则回退到 clock/2 = 2,097,152 Hz，AVAudioEngine 无法创建 `AVAudioFormat`，GB/GBC 无声。现返回 48000。
4. **`GET_LOG_INTERFACE`**：实现并把 DEBUG 级日志丢弃（SameBoy 的 HW 寄存器日志会刷数百行），只透传 INFO/ERROR。

**验证结果**（各 15 项断言全通过）：

| core | 几何 | pixel format | 帧率 | 快照 |
|---|---|---|---|---|
| fceumm | 256×240 | XRGB8888 | 60.3 fps | 13,758 B |
| SameBoy | 160×144 | XRGB8888 | 59.5 fps | 252,666 B |
| mGBA | 240×160 | **RGB565** | 59.5 fps | 528,448 B |

mGBA 的 RGB565 实测确认了 FramePipeline 的 16bpp → BGRA 转换路径正确（非仅代码审查）。

---

## ADR-009 补充：布局算法 v3（2026-10-23，用户二次反馈）

**现象**：真机上方向键散开、SELECT 跑到左侧、组间不对称。

**根因（两层）**：
1. **旧布局文件仍在生效**：`LayoutStore.load` 会优先读取 `Layouts/*.json`，
   而 v1.1/v1.2 时期保存的坐标用的是旧公式（`dpadStepX 0.09` 等），
   间距与现在的尺寸不匹配 → 十字散开、重叠。
2. **SELECT/START 用屏幕宽度比例**：`anchor = .center` 时 x = 屏宽 × 比例，
   而按钮尺寸按短边。iPhone 2.17:1 下两者比例失衡，两个椭圆会贴在一起或分得过开。

**方案（算法 v3）**：
1. **布局版本号**：`ControlLayout.version`，当前 `ControlLayouts.currentVersion = 3`。
   加载时 `version < currentVersion` 的文件**直接删除并回落默认布局** ——
   坐标体系变更后旧坐标必然错位，不能沿用。
2. **间距统一为「直径 × 系数」**：`dpadPitch = dpadSize × 1.12`、`actionPitch = actionSize × 1.15`、
   `turboPitchY = 0.14`。任何屏幕下组内间距一致，不会因为宽高比变形。
3. **新增 `.centerOffset` 锚点**：`x = 屏宽/2 + relativeX × 短边`。
   SELECT/START 用它，既能真正居中，间距又按短边计算（iPhone/iPad 都合适）。
4. 组锚点全部由 `sideMargin` 推导：`dpadLeftX = sideMargin + dpadSize/2`、
   `bX = 1 - (sideMargin + actionSize/2)`，左右天然镜像。

**验算**（iPhone 18 PM 956×440，短边 440）：
- 方向键左边距 22pt、十字间距 61.6pt（直径 55 → 间隙 6.6pt）
- B 右边距 19pt、A/B 间距 56.8pt（直径 49 → 间隙 7.5pt）
- SELECT/START 距屏幕中心 ±33.7pt，间距 67pt（宽 58.5 → 间隙 8.9pt）

**教训**：布局这类"跨设备比例"的问题，坐标体系一变就必须让旧数据失效，
否则用户升级后看到的是新旧混合的错位布局——比不做还糟。

---

## ADR-009 补充 2：布局 v4（2026-10-23，用户第三次调布局）

用户要求：方向键整体右移约 5mm、A/B 与方向键同尺寸、两组在画布上对称。

1. `sideMargin` 0.050 → **0.115**：方向键左边距由 22pt 增至 50.6pt（iPhone 18 PM 上约 4.6mm）
2. `actionSize` 0.112 → **0.125**（= `dpadSize`）：两组按键直径完全一致，
   左右边距因此严格相等 → 视觉重量对称
3. 修正 `dpadPitch` **语义错误**：原代码把「相邻键中心距」当成「半距」用
   （`up = centerY - pitch`、`right = leftX + pitch * 2`），导致十字间距是设计值的 2 倍。
   现明确 `dpadPitch` = 相邻键中心距（= 直径 × 1.12），上下键用 ±pitch/2、左右键差一个 pitch。
4. `turboSize` 0.106（= actionSize × 0.85）、`turboPitchY` 0.132

`currentVersion` → **4**，旧布局 JSON 自动作废。

---

## ADR-011：快进倍率失准（2026-10-23，用户反馈「2×/4× 快太多了」）

**根因**：`runLoopBody` 里限速被 `if (!fast)` 包住 —— **快进时完全不休眠**：

```objc
NSInteger frames = fast ? MAX(1, multiplier) : 1;
for (i = 0; i < frames; i++) p_retro_run();   // 一次跑 N 帧
if (!fast) { ...nanosleep(frameInterval)... }  // 只有非快进才等
```

快进时每轮跑 N 帧后立刻进入下一轮，**循环速度取决于 CPU 跑多快**，
实测可达设定值的数十倍（用户的直观感受就是"快得没法玩"）。

**修复**：每轮循环都推进「一个显示帧」的时长，与是否快进无关：

```objc
nextFrame += frameInterval;   // 固定 16.67ms/轮
nanosleep(...);               // 唯一区别是这一轮里跑了 frames 帧 → 恰好 frames 倍速
```

**验证**（macOS e2e，`./Tools/run_e2e.sh`）：
设定 4× → 实测 **4.00×（240 帧 / 1.00s）**，已加入 e2e 断言防回归。

> 若某 core 单帧耗时 × N 超过 16.67ms，实机达不到设定倍率（受 CPU 限制）——
> 这是物理上限，不是 bug；`nextFrame = now` 的追赶保护会避免积压。

---

## ADR-010：画面比例与快进音频（2026-10-20，用户反馈）

**问题 1：画面被拉伸**
MTKView 用一个铺满全屏的 quad 绘制，纹理 256×240（1.07:1）在 iPhone 2.17:1 屏幕上必然变形。

**方案**：按纹理比例设置 `MTLRenderCommandEncoder.setViewport(...)` 做 aspect-fit：
- 纹理更宽 → 宽度撑满、上下黑边；纹理更高 → 高度撑满、左右黑边
- 设置项「保持游戏原始比例」默认开启，关闭则回到全屏铺满（拉伸）
- 按键层仍按**屏幕**布局（不跟画面收缩），否则在超宽屏上按键会挤在中间窄条里无法操作

**问题 2：快进时没有背景音乐**
`mr_audio_sample_batch` 里写了 `if (!self.fastForwardActive)` —— **快进时直接丢弃全部音频**，
等于静音。而且即便写入，8 倍速下每秒产出 384k 样本 vs 消费 48k，环形缓冲必被灌爆。

**方案**：按倍率**抽取**（decimation）后写入：
- 每 `multiplier` 帧取 1 帧 → 输出速率恒定 48k/s，与播放速率匹配，缓冲不再溢出
- 内容仍按倍率跳跃 → 音调升高（典型"快进音效"），但音乐/音效可辨
- 抽取缓冲预分配为静态数组（8192 帧），回调内零 malloc
- 同时去掉 `setFastForward` 里的 `audioRingBuffer reset`（会在开启瞬间造成断音）

---

## ADR-009：跨宽高比的按键布局（锚点模型）（2026-10-20，用户反馈）

**问题**：iPhone 18 Pro Max 横屏约 **2.17:1**，iPad 约 1.33:1。
原实现 x 坐标统一按屏幕宽度归一化、按键尺寸按短边计算，两者在超宽屏上冲突：
- 间距被横向放大（0.09×956=86pt）而直径仍按短边（0.115×440=50pt）→ 十字散开
- 左右边距不均（左 0.05、右 0.065 且随宽高比漂移）

**方案**：给每个按键加 `HorizontalAnchor`，x 换算按锚点分别处理：

| anchor | 换算 | 用于 |
|---|---|---|
| `.leading` | `x = relativeX × 短边` | 左组（方向键、GBA L） |
| `.trailing` | `x = 屏宽 − (1−relativeX) × 短边` | 右组（A/B、连发、GBA R） |
| `.center` | `x = 屏宽 × relativeX` | SELECT/START（需真正居中） |

配套：按键尺寸与「十字间距」都以短边为基准（间距 = 直径，十字紧贴）；
左右组的边距由同一个 `sideMargin` 推导，天然镜像对称。

**效果**（像素验算）：
- iPhone 18 PM（956×440）：方向键左边距 22pt、十字间距 55pt（=直径）、B 右边距 19pt
- iPad（1024×768）：左边距 19pt、间距 96pt（=直径）——视觉比例一致

**兼容**：旧布局 JSON 无 `anchor` 字段，解码时按 relativeX 推断（<0.42 左组、>0.62 右组、其间居中）。

**顺带**：按键配色从「经典红」改为常见手柄的灰色半透明（`white 0.42` × 全局透明度），
并修正 `highlight()` 松开后只恢复单键透明度、漏乘全局值的缺陷。

---

## ADR-008：模拟器/真机环境差异（权限、渲染尺寸、视图时序）（2026-10-20）

模拟器实测暴露三类「只在真实运行环境出现」的问题，已固化为实现约束：

1. **`simctl install` 会剥掉 dylib 可执行位**：`-rwxr-xr-x` → `-rw-r--r--`。
   → 判断 framework 是否存在**只能用 `fileExistsAtPath`**，禁止用 `isExecutableFileAtPath`。
2. **MTKView 的 `drawableSize` 不要手动赋值**：`UIViewRepresentable.updateUIView` 首次调用时
   `bounds` 常为 0，一旦写入 `drawableSize = .zero`，MTKView 会永久停止出图（`currentDrawable` 恒为 nil）。
   → 交给 `autoResizeDrawable = true`；仅在尺寸有效时取消 `isPaused`。
3. **自绘 UIView 必须由 `layoutSubviews` 驱动重排**：`UIViewRepresentable` 的 `makeUIView`
   发生时 `bounds` 仍为 0，此时按 bounds 计算子视图 frame 会得到全 0（按键不可见）。
   → `apply()` 只记录参数，实际排布放进 `rebuildButtons()`，由 `layoutSubviews` 在尺寸变化时调用。

**教训**：`swiftc -typecheck`、`-parse`、甚至 macOS 端到端（无 UIKit/SwiftUI）都无法覆盖
这三类问题——它们是布局时序与安装行为问题。**必须在 iOS 模拟器（或真机）跑一次**。

---

## ADR-007：识别层 system_id 契约与损坏条目的落盘（2026-10-20，用户反馈缺陷）

**现象**：导入 `.nes` 报「无法识别的格式」，导入 0 款；库中出现一张永久显示「文件损坏」的卡片（GB/GBA 导入正常）。

**根因**（两层）：
1. **契约断裂**：C 层 `CoreRegistry` 返回的 `system_id` 是 `"nes"`，而 Swift 侧 `SystemType` 的 case 名是 `fc`，`rawValue` 自然是 `"fc"`。
   原实现 `SystemType.from(systemID:)` 直接 `SystemType(rawValue:)` → `"nes"` 映射为 `nil` → `identify()` 返回 `nil` → 所有 NES 文件被判为无法识别。
   GB/GBC/GBA 的 case 名恰好与 C 层字符串一致，所以只有 NES 中招。
2. **失败分支不落盘**：无法识别时只 `index.upsert` 一条 `Unknown/<name>` 索引，**没有拷贝文件**，导致卡片显示「文件损坏」却无法删除或重试。

**修复**：
1. `SystemType.from(systemID:)` 改为显式映射表：`nes|fc|unf|unif → .fc`、`fds → .fds`、`gb/gbc/gba` 对应；大小写不敏感。
2. 无法识别的文件改为 `store(...)` 落盘后再标 `isCorrupted`，并给出明确的支持格式列表。
3. C 层补充 `UNIF` 魔数（早期汉化/外星科技常见封装）与 `unf/unif` 扩展名 → `fceumm`。

**验证**：
- 用**真实 ROMImporter**（而非副本）编译执行 6 项用例：中文名 `.nes` 扩展名兜底、iNES 魔数、UNIF 容器、GB 魔数、未知格式、空文件——全通过。
- C 层测试增至 16 项（新增 UNIF 魔数、`.unf`、`.UNIF` 大小写）全通过。
- 新增 `Tests/MiniRetroTests/SystemTypeMappingTests.swift`（7 项）防回归，其中一条专门遍历 C 层所有可能输出，确保「新增 system 时不会静默断裂」。

**教训**：跨语言（C ↔ Swift）的枚举/ID 映射不能依赖字符串巧合，必须有显式映射表 + 覆盖「C 层全部可能输出」的测试。

---

## ADR-006 补充：cmake / rgbds 获取备用路径（2026-10-20）

**实测**：`brew install cmake` / `brew install rgbds` 在受限网络下失败（bottle 走 `ghcr.io` 被拦截；沙箱还阻止 homebrew 锁文件写入）。

**决策**：
- mGBA 上游无 libretro Makefile，必须 cmake → 提供 `Tools/fetch_cmake.sh`（cmake.org 官方 tarball，已验证 3.31.6 可用）
- SameBoy boot ROM 需 rgbds → 提供 `Tools/fetch_rgbds.sh`（源码构建，自动处理系统 bison 过旧的问题；`rgbgfx` 需 libpng，缺失时跳过并在构建时提示）
- `build_cores.sh` 自动检测 PATH → `Tools/vendor/` → 提示安装，三级回退

---

## ADR-012 接入 FBNeo 支持街机（CPS1/CPS2/Neo Geo/PGM）（2026-10-21）

**背景**：用户要求支持西游释厄传（IGS PGM）、三国战纪（PGM）、拳皇（Neo Geo MVS）。
这些都不是家用主机平台，现有三个 core（fceumm/SameBoy/mGBA）完全不覆盖。

**调研结论**：
- 职业/家用机 core 无法运行街机 romset，必须接街机 core。libretro 生态里唯一同时覆盖
  CPS1/CPS2/Neo Geo/PGM 的是 **FBNeo**（FinalBurn Neo）。
- 上游 `Makefile.libretro` 自带 `platform=ios-arm64` 分支（`else ifneq (,$(findstring ios,$(platform)))`），
  交叉编译可用；CC/CXX 需在命令行覆盖以换成 simulator target。
- 仓库体积 204MB，不适合做 git submodule（本项目其余 core 都是 submodule）。
  → 首次构建时浅克隆到 `$TMPDIR/miniretro-cores-build/fbneo-src`，锁定 commit
  `2b0c1c0679df115cada7df9199ea2762222e58fd`。

**决策**：
1. 新增 `SystemType.arcade`（rawValue `arcade`，core `fbneo`）。
2. **zip 双语义**：压缩包（内含 nes/gb/…）解压入库；解不出主机 ROM 时按街机 romset 整包入库
   （`ROMs/arcade/<romset>.zip`），`.7z` 一律按 romset 处理。
3. BIOS 走 `Documents/System`（`GET_SYSTEM_DIRECTORY`）。用户用同一个 + 按钮导入
   `neogeo.zip` / `pgm.zip`，App 按文件名识别后直接装到 System，不进游戏库。
4. 街机布局单独一套：十字键 + A/B/C/D 2×2 + SELECT（投币）/START。
   Neo Geo 的 C/D 复用 libretro 的 Y/X 位，靠 `ControlButton.label` 覆盖显示文字。

**代价**：
- 二进制 49MB/切片（strip 后），ipa 从 1.6MB → 15MB。
- 需要用户自备 romset 与 BIOS；仓库不含任何 ROM/BIOS。

**验证**：
- device/simulator 两个切片分别编译通过，`vtool -showBuild` 平台分别为 `IOS` / `IOSSIMULATOR`，
  minos 17.0。
- `./Tools/run_romlib_test.sh` 覆盖：真实 ROM 识别、重复导入去重、旧索引幽灵条目自愈、
  街机 zip 入库为 `arcade/kov.zip`（15 项全通过）。
