# MiniRetro · 小霸王复古模拟器

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform](https://img.shields.io/badge/iOS%20%7C%20iPadOS-17.0%2B-blue)
![Version](https://img.shields.io/badge/version-2.0.0-brightgreen)

一个用 SwiftUI + Metal 写的 iOS/iPadOS 复古游戏模拟器，内核基于 libretro。
支持 FC/NES、GB/GBC、GBA 和街机（CPS1/CPS2/Neo Geo/PGM），侧载安装，**不含任何 ROM**。

![游戏库](docs/screenshots/12-library-v17-fixed.png)

---

## 支持的平台

| 平台 | 文件 | 说明 |
|---|---|---|
| FC / NES / FDS | `.nes` `.fds` `.unf` | 含早期汉化卡带的 UNIF 封装 |
| GB / GBC | `.gb` `.gbc` | |
| GBA | `.gba` | |
| 街机 | `.zip` `.7z` | 整套 romset，需自备 BIOS |

四个内核（fceumm / SameBoy / mGBA / FBNeo）**已随 App 打包**，装上就能用。

---

## 安装

下载 [Releases](https://github.com/xvzxv/MiniRetro/releases) 里的 `*-unsigned.ipa`，
用 **Sideloadly / AltStore / 自签证书** 签名后安装。需要 iOS / iPadOS 17.0+。

免费 Apple ID 的签名 7 天过期，到期重新签一次即可。

---

## 使用

### 导入游戏

点右上角 `+`，三种方式：

- **选择文件**：可一次选多个（游戏、BIOS、金手指、存档混着选也行，App 自动归类）
- **导入整个文件夹**：递归扫描，适合一次拷一堆 ROM 进来
- **从直链 / WebDAV 导入**：粘贴下载链接，或连群晖 / 坚果云 / Nextcloud 浏览下载

会自动识别的东西：

| 文件 | 处理 |
|---|---|
| `.nes/.fds/.gb/.gbc/.gba` | 识别平台后入库 |
| `.zip` | 含主机 ROM → 解压分类；街机 romset / 整合包 → 拆包 |
| `.7z` | 街机 romset 整包 |
| `neogeo.zip` / `pgm.zip` | 识别为 BIOS，装进 `System/` |
| `.cht` | 存进金手指库，游戏内可一键套用 |
| `.srm` / `.sav` | 按同名 ROM 归档为电池存档 |

重复导入同一款游戏会跳过，不会生成副本。

### 批量删除

右上角 `⋯` → **批量选择** → 点卡片勾选（支持「全选」）→ 底部「删除」。
删除会同时清掉 ROM 文件、即时存档、金手指记录，并有二次确认。

### 游戏内

左上角菜单：

- **存档**：1 个自动槽（进游戏自动读、退出自动写）+ 3 个手动槽，每槽带画面封面
- **金手指**：手动录入 / 社区库搜索 / 套用导入的 `.cht`
- **快进**：2×～16×，画面顶部也有快捷开关
- **显示**：滤镜、FPS、音量、虚拟按键布局编辑、手柄键位
- **软复位 / 退出**：都会二次确认

### 街机

1. 导入整套 romset（`.zip`/`.7z`，**不要解压**）
2. 把 `pgm.zip`（PGM）或 `neogeo.zip`（Neo Geo）用同一个 `+` 导入 —— 它通常就在你的 romset 包里
3. 缺 BIOS 时画面会显示内核的缺失清单，照着补即可

> BIOS 属于厂商版权数据，App 不内置。

### 手柄

系统蓝牙配对后自动识别。设置里可选方向输入（十字键 / 左摇杆 / 两者）；
连上手柄后虚拟按键自动隐藏，点画面右上角的手掌图标可临时调回。

---

## 版本号规则

`主版本.次版本.修订号`：

- **修订号**（`2.0.x`）：修 bug、小调整
- **次版本**（`2.x.0`）：加新功能、较大改动
- **主版本**（`x.0.0`）：重构或重大更新

---

## 构建

需要 macOS + Xcode 16 以上：

```bash
brew install xcodegen cmake rgbds
./Tools/build.sh                 # 产出 build/MiniRetro-<版本>-<build>-unsigned.ipa
./Tools/build.sh --skip-cores    # 只编译 App（内核已构建过）
./Tools/run_romlib_test.sh       # 逻辑回归测试，不需要设备
```

开发细节见 [`docs/maintenance.md`](docs/maintenance.md) 与 [`docs/adr-log.md`](docs/adr-log.md)。

---

## 许可

自有代码 **MIT**（见 [LICENSE](LICENSE)）。
第三方内核：fceumm（GPL-2.0）、SameBoy（Expat/MIT）、mGBA（MPL-2.0）、FBNeo（禁止商业使用），
详见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。

**本仓库不包含任何 ROM / BIOS。** 请使用你自己合法拥有的游戏备份或 homebrew 作品。
