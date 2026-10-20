# 测试用例表（模拟器侧 / 自动化）

> 执行环境：iOS 模拟器（iPad 6 同尺寸 + 当前 iPhone）+ 单元测试。
> 标 ⚠️ 的用例需要 ROM 素材（仓库不含 ROM，请使用 homebrew / 自有备份）。

## 0. 自动化测试

| ID | 用例 | 方式 | 状态 |
|---|---|---|---|
| A-01 | ROM 魔数识别（iNES / FDS / GBA / GB / GBC） | `Tests/CoreRegistryTests.c`（可独立运行） | ✅ 13/13 通过 |
| A-02 | 扩展名兜底与大小写 | 同上 | ✅ |
| A-03 | 未知数据/空文件无匹配 | 同上 | ✅ |
| A-04 | 三套默认布局按钮完整性（FC/GB 无 LR，GBA 有） | `LayoutStoreTests` | ✅ 逻辑验证 |
| A-05 | 布局 JSON 往返（位置/透明度保持） | `LayoutStoreTests` | ✅ |
| A-06 | 即时存档 serialize/unserialize 往返 | `SaveStateTests` | ⏳ 需 ROM（自动 skip） |
| A-07 | 电池存档 flush | `SaveStateTests` | ⏳ 需 ROM |
| A-08 | CoreBridge 编译零警告 | `clang -Wall` | ✅ |
| A-09 | Swift 逻辑层类型检查 | `swiftc -typecheck` | ✅ 零错误 |
| A-10 | **端到端**：framework 探测 + dlopen | `Tools/run_e2e.sh` | ✅ 三 core 通过 |
| A-11 | **端到端**：retro_load_game（need_fullpath 两种路径） | 同上 | ✅ fceumm=true / sameboy+mGBA=false 均通过 |
| A-12 | **端到端**：60fps 帧率 | 同上 | ✅ 60.3 / 59.5 / 59.5 fps |
| A-13 | **端到端**：像素输出（三种 pixel format） | 同上 | ✅ XRGB8888×2 + RGB565 转换均有效 |
| A-14 | **端到端**：音频回调产出 | 同上 | ✅ 48kHz / 32.768kHz 写入环形缓冲 |
| A-15 | **端到端**：存档 serialize/unserialize 往返 | 同上 | ✅ 13758 / 252666 / 528448 字节 |
| A-16 | Metal shader 语法校验 | `xcrun -sdk iphoneos metal -c App/Resources/VideoShaders.metal` | ✅ 编译通过（8KB air） |
| A-17 | iOS 完整构建 | `./Tools/build.sh` | ✅ BUILD SUCCEEDED，产出 ipa 1.6MB |
| A-18 | system_id → SystemType 映射（防回归） | `SystemTypeMappingTests` + 真实 ROMImporter 可执行验证 | ✅ 11 + 6 项通过 |
| A-19 | `.nes` 中文名扩展名兜底 | 同上（含 `水浒神兽[外星科技][CN][RPG](8Mb).nes`） | ✅ 识别为 fc/fceumm |
| A-20 | UNIF 容器识别 | C 测试 + 可执行验证 | ✅ `UNIF` → fceumm/unf |

运行自动化测试：

```bash
# ROM 识别（无需 Xcode，直接跑）
cd Tests && clang -Wall -o /tmp/cr_test CoreRegistryTests.c ../CoreBridge/CoreRegistry.c && /tmp/cr_test

# XCTest（需 Xcode + 模拟器）
xcodegen generate
xcodebuild test -scheme MiniRetro -destination 'platform=iOS Simulator,name=iPad (10th generation)'
```

## 1. 导入与游戏库（M1/M5）

| ID | 步骤 | 预期 |
|---|---|---|
| L-01 | 首次启动，空库 | 显示引导文案，不含任何预置游戏 |
| L-02 | 导入单个 `.nes` | 卡片出现，角标 `FC/NES` |
| L-03 | 导入含 3 个 ROM 的 `.zip` | 一次导入 3 个，各自正确分类 |
| L-04 | 导入 `.gba` / `.gb` / `.gbc` | 角标分别为 GBA / GB / GBC |
| L-05 | 重复导入同一 ROM | 提示「跳过重复 1 款」，库中不重复 |
| L-06 | 导入非法文件（如 .txt 改名 .gba） | 魔数失败 → 扩展名兜底入库，标记损坏 |
| L-07 | 搜索 "mario" | 仅显示匹配项 |
| L-08 | 收藏 / 取消收藏 | 星标切换，重启保留 |
| L-09 | 最近游玩排序 | 玩过的排前 |
| L-10 | 网格/列表切换 | 布局切换，内容一致 |
| L-11 | 删除库中条目 | 条目消失，存档目录一并清理 |

## 2. 运行与输入（M1/M6）

| ID | 步骤 | 预期 |
|---|---|---|
| G-01 | 点卡片进入游戏 | 横屏全屏，画面正常，声音正常 |
| G-02 | 方向键 + A/B 同时按 | 多指同时生效（斜向移动 + 跳） |
| G-03 | GBA 游戏按 L/R | 肩键生效（菜单里 L/R 位于屏幕上角） |
| G-04 | 拖动虚拟按键（布局编辑模式） | 位置移动，松手保存，重启保留 |
| G-05 | 调节按键透明度/大小 | 立即生效 |
| G-06 | 切换皮肤（经典/极简） | 按键配色与透明度切换 |
| G-07 | 连接蓝牙手柄 | HUD 出现手柄图标，全键可用 |
| G-08 | 手柄键位重映射（A→B） | 按物理 A 触发模拟器 B |
| G-09 | 进后台（回到桌面） | 自动暂停（可配），回前台恢复 |
| G-10 | 进后台后杀 App 重开 | 自动存档可读回（若开启自动存档） |

## 3. 存档（M2/M3/M4）

| ID | 步骤 | 预期 |
|---|---|---|
| S-01 | 存档到槽位 1 | 槽位出现缩略图 + 时间 |
| S-02 | 继续玩 30 秒后读槽位 1 | 画面回到存档点 |
| S-03 | 槽位 2/3/4 独立存档 | 互不覆盖 |
| S-04 | 删除槽位 | 槽位与缩略图消失 |
| S-05 | 正常存档（电池）后杀 App | 重进游戏进度保留（`.sav` 落盘） |
| S-06 | 自动存档（进后台） | `自动存档` 槽位更新 |

## 4. 金手指（M2/M3/M4）

| ID | 步骤 | 预期 |
|---|---|---|
| C-01 | GBA 添加 GameShark 码并启用 | 效果生效（内存值变化） |
| C-02 | 关闭开关 | 效果消失 |
| C-03 | 重启 App 后 | 金手指列表与开关状态保留 |
| C-04 | FC 添加 Game Genie 码 | 生效 |
| C-05 | GB 添加 GameShark 码 | 生效（依赖 SameBoy 原生 cheat 补丁） |
| C-06 | 添加空代码 | 按钮禁用，不允许提交 |

## 5. 滤镜与设置（M7）

| ID | 步骤 | 预期 |
|---|---|---|
| V-01 | 整数倍滤镜 | 像素锐利，无模糊 |
| V-02 | 平滑滤镜 | 边缘柔化 |
| V-03 | CRT 滤镜 | 扫描线 + 暗角 |
| V-04 | LCD 点阵（GB 游戏） | 点阵网格可见 |
| V-05 | 低性能模式 + CRT | 自动降级为整数倍 |
| V-06 | 快进 2×/4× | 速度提升，无爆音 |
| V-07 | 音量滑杆 | 音量实时变化 |
| V-08 | 显示 FPS | HUD 显示帧率（目标 ≥60） |

## 6. 稳定性（M8）

| ID | 步骤 | 预期 |
|---|---|---|
| P-01 | 连续游玩 2 小时 | 无崩溃、无卡顿累积 |
| P-02 | Leaks 检测（Instruments） | 无内存泄漏，稳定 <300MB |
| P-03 | 20 次进出游戏 | 无崩溃、内存不持续增长 |
| P-04 | 低电量模式游玩 | 帧率可接受（≥55fps） |
| P-05 | 来电/通知打断 | 自动暂停，恢复后继续 |
| P-06 | iPad 分屏/台前调度 | 画面与按键适配（P2 可选） |
