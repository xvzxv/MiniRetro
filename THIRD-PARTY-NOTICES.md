# 第三方组件与许可（Third-Party Notices）

MiniRetro 自有代码以 **MIT** 许可发布（见 [LICENSE](LICENSE)）。
下列第三方组件保持其原始许可证，**不受 MIT 许可影响**，再分发时须一并遵守。

## 随仓库分发的模拟器内核

| 组件 | 版本 / 锁定 | 许可证 | 用途 |
|---|---|---|---|
| [fceumm](https://github.com/libretro/libretro-fceumm) | `ac0d00a7` | **GPL-2.0** | FC/NES、FDS 内核 |
| [SameBoy](https://github.com/LIJI32/SameBoy) | v1.0.4 | **Expat (MIT)** | GB/GBC 内核 |
| [mGBA](https://github.com/mgba-emu/mgba) | 0.10.5 | **MPL-2.0** | GBA 内核 |
| [libretro.h](https://github.com/libretro/libretro-common) | `a3194c18` | RetroArch 团队许可（类 MIT） | libretro API 头文件 |

- `Cores/{fceumm,sameboy,mgba}/` 为上述项目的**源码快照**，各自的 `LICENSE` / `Copying` 文件原样保留。
- `Cores/artifacts/{fceumm,sameboy,mgba}-core.xcframework` 为对应源码的编译产物。
- 如需重新分发本项目的二进制包，请同时满足 GPL-2.0（fceumm）与 MPL-2.0（mGBA）的条款。

## 可选内核（不随仓库分发）

| 组件 | 版本 / 锁定 | 许可证 | 用途 |
|---|---|---|---|
| [FBNeo](https://github.com/libretro/fbneo) | `2b0c1c06` | [FBNeo License](https://github.com/finalburnneo/FBNeo/blob/master/src/license.txt)（**禁止商业使用**） | 街机 CPS1/CPS2/Neo Geo/PGM |

FBNeo 体积较大（单切片约 49 MB），**未纳入本仓库**。
执行 `./Tools/build_cores.sh fbneo` 会从上游浅克隆并编译，编译产物由你自行承担上述许可义务。

## 构建期工具（不随仓库分发）

| 工具 | 许可证 |
|---|---|
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | MIT |
| [CMake](https://cmake.org) | BSD-3-Clause |
| [rgbds](https://github.com/gbdev/rgbds) | MIT |

## 游戏 ROM 与 BIOS

本仓库**不包含任何游戏 ROM、BIOS 或游戏画面素材**。
导入的 ROM/BIOS 由使用者自行提供，请使用你合法拥有的游戏备份或自由/homebrew 作品。
截图中出现的游戏画面来自自建的测试 ROM。
