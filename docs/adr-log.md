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
