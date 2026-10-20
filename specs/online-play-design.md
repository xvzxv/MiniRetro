# 联机对战设计（本期只设计，不实现）

- 版本：1.0　日期：2026-10-20　状态：**设计文档 / 无实现代码**
- 关联：项目计划书 2.1「联机功能（本期只设计不开发）」、M9 里程碑

---

## 1. 背景与非目标

### 1.1 为什么现在只写文档

联机（netplay）不是「加一个 socket」那么简单，它牵动模拟器的时间模型：

- 帧同步要求 core **完全确定性**（同一 ROM + 同一输入序列 → 完全相同的画面/内存）
- 需要重写 run 循环为「按帧锁定」，与当前「自由跑 + sleep 限速」模型冲突
- 需要 NAT 穿透、房间发现、延迟补偿、断线重连、存档同步等一整套基础设施
- iPad 6（A10）上的回滚（rollback）开销需要单独评估

因此本期只沉淀设计，把接口位置在代码里留好，避免未来实现时返工架构。

### 1.2 非目标（本期明确不做）

- ❌ 任何 socket / 网络代码
- ❌ UI 入口（只留协议与注释占位）
- ❌ 房间服务器 / 中继服务器
- ❌ 回滚实现

---

## 2. 现状调研：libretro 生态的 netplay 是什么

**关键结论：netplay 由前端实现，core 不提供。**

libretro API 没有任何 netplay 相关回调。RetroArch 的 netplay 完全在其前端层：

| 组件 | 职责 |
|---|---|
| `netplay_frontend.c` | 房间/会话生命周期、UI |
| `netplay_handshake.c` | 握手、能力协商（core 名、版本、ROM CRC） |
| `netplay_sync.c` | 帧同步：收集本地输入 → 广播 → 等待各方输入 → 解锁一帧 |
| `netplay_io.c` | UDP 传输、NAT 打洞、中继（relay）兜底 |
| 存档同步 | 开局把 host 的 `retro_serialize` 快照发给 join 方 |

对 core 的唯一要求：**确定性**（相同输入序列产生相同状态）。core 侧不需要改代码。

### 2.1 三个 core 的确定性评估

| core | 确定性 | 依据 / 风险点 |
|---|---|---|
| mGBA 0.10.5 | 高 | 官方提供确定性测试套件（`mgba-test`），上游明确支持 TAS 与 netplay；风险：开启 nondeterministic 优化（如某些 JIT 优化）需关闭 |
| SameBoy 1.0.4 | 高 | 设计目标是精度优先，无多线程仿真；TAS 社区广泛使用；风险：低（需固定 `sameboy_*` core options） |
| fceumm | 中高 | 单线程、无随机源；风险：部分 mapper 的 IRQ 时序依赖未定义行为、NTSC 滤镜可能引入浮点差异（联机时应强制关闭滤镜） |

**共性要求**：
1. 双方 core options 必须一致（金手指、调色板、滤镜、超频等）→ 握手时交换并校验
2. ROM 必须完全一致 → 用 ROM 文件 CRC32/SHA1 校验
3. 存档起点必须一致 → 开局同步 host 快照
4. 音频不参与同步（各自本地播放，允许轻微差异）

---

## 3. 方案对比

| 方案 | 优点 | 缺点 | 结论 |
|---|---|---|---|
| **A. 移植 RetroArch netplay** | 成熟、有中继服务 | GPL 传染性需评估；代码与 RetroArch 前端深度耦合（依赖其 config/thread/UI 层），移植成本高于重写；iOS 上中继服务不可控 | ❌ 不采用 |
| **B. 自研帧锁步（lockstep）+ 快照纠正** | 可控、代码量适中、与现有 CoreBridge 契合 | 延迟敏感（RTT 越高越卡）；需要 NAT 方案 | ✅ **推荐** |
| **C. 回滚（rollback）** | 体感延迟低，适合格斗/动作 | 每帧需保存快照，内存与 CPU 开销大（iPad 6 上 GBA 快照约 200–400KB，保留 7 帧 ≈ 2–3MB，可行但 A10 上重放成本需实测）；实现复杂度高 | ⏳ 二期（v2） |
| **D. 云游戏（串流）** | 客户端零要求 | 服务器成本、延迟不可控、与"本地模拟器"定位冲突 | ❌ 不采用 |

---

## 4. 推荐方案（B：帧锁步 + 快照纠正）

### 4.1 时间模型改造

当前 run 循环（`RetroCore.mm` → `runLoopBody`）：

```
while running:
    retro_run()                  # 自由跑
    sleep(到下一帧时间)
```

联机模式需要的循环：

```
while running:
    本地输入 = 采集(本帧)
    发送(本地输入)
    等待(所有玩家的本帧输入, 超时 = 3 帧)
    if 超时:
        预测(缺失玩家输入 = 上一帧输入)   # 或直接停顿
    retro_run_with(所有输入)
    每 N 帧校验状态哈希(与 host 对比)
    if 哈希不一致:
        请求 host 快照 → unserialize → 追帧重放
```

**关键点**：`retro_run()` 本身不变；变化的是「何时允许调用」与「输入从哪来」。这意味着 CoreBridge 只需暴露：

1. 输入注入的原子性（当前状态表已满足）
2. 帧边界回调（`retro_run` 返回后立即通知）
3. 类型化快照（已有 `serializeState` / `unserializeState`）
4. 状态哈希（需新增：对 `serializeState` 结果取 SHA-256 即可，无需 core 配合）

### 4.2 传输层

- **协议**：UDP + 自定义轻量包头（seq、ack、payload type）
- **NAT**：优先 STUN 打洞（P2P）；失败则走自建中继（TURN 风格，只转发不解析）
- **房间**：最小可用方案为「房主 IP + 端口 + 房间码」，不做账号体系
- **可靠性**：输入包用「冗余发送最近 3 帧」抵抗丢包（输入数据极小，2 字节/帧/人）

### 4.3 一致性与纠错

| 机制 | 说明 |
|---|---|
| 握手校验 | core 名 + 版本 + ROM SHA1 + core options 全量指纹 |
| 开局同步 | host 发送 `serializeState` 快照，join 方 `unserializeState` 后开始 |
| 周期哈希 | 每 60 帧对比一次状态哈希（SHA-256 取前 8 字节），成本可忽略 |
| 纠正 | 哈希不一致 → 请求快照 → 读档 → 重放最近 N 帧输入 |
| 断线 | 3 秒无包判定断线，弹提示；可选「单人继续」降级 |

### 4.4 音频

联机时不共享音频。各端本地播放自己的 core 输出，允许 ±1 帧差异；不对音频做同步，避免音频缓冲成为延迟瓶颈。

---

## 5. 接口预留点（代码现状）

当前代码中已留好以下位置，未来实现**不需要改动现有公共接口**：

| 位置 | 预留内容 | 状态 |
|---|---|---|
| `CoreBridge/RetroCore.h` | `@protocol RetroSessionPlaceholder` —— 未来 `RetroSession` 协议的占位声明 | ✅ 已声明（空协议，仅注释） |
| `CoreBridge/RetroCore.h` | 类注释中标注「未来 netplay 通过该协议接入，不改变 RetroCore 现有接口」 | ✅ |
| `RetroCore.mm` | `runLoopBody` 的帧循环是唯一插入点：联机模式在此插入「等待输入 → 解锁」 | ✅ 结构已具备（单点循环） |
| `App/Game/EmulatorViewModel.swift` | `onRequestMenu` 回调 —— UI 入口占位（未来挂「联机对战」按钮） | ✅ |
| `App/Game/EmulatorViewModel.swift` | `serializeState` / `unserializeState` —— 快照同步直接复用 | ✅ |
| `App/Game/InGameMenuView.swift` | 菜单分组结构 —— 未来新增「联机」Section | ✅ |
| `App/Models/` | 无网络相关模型（刻意不引入，避免半成品状态泄漏到数据层） | ✅ |

### 5.1 未来需要新增的（估算）

```
CoreBridge/Netplay/
  RetroSession.h/.mm        会话生命周期、锁步循环、哈希校验
  InputPacket.h             输入包编解码（2 字节/帧/人）
  NetplayTransport.h        UDP + 打洞 + 中继抽象
  StateHash.c               SHA-256（可用 CommonCrypto）
App/Netplay/
  NetplayLobbyView.swift    房间码、连接状态、延迟显示
  NetplaySettingsView.swift 输入延迟、预测模式
```

---

## 6. 工作量估算（单人，含测试）

| 阶段 | 内容 | 估算 |
|---|---|---|
| 1. 时间模型改造 | CoreBridge 锁步循环 + 输入队列 + 帧边界 | 4–5 天 |
| 2. 传输层 | UDP、握手、打洞、冗余发送 | 5–7 天 |
| 3. 一致性 | 哈希校验、快照同步、纠正重放 | 4–6 天 |
| 4. UI | 大厅、房间码、延迟/状态显示 | 3–4 天 |
| 5. 测试与调优 | 双机联调、弱网、A10 性能 | 5–7 天 |
| **合计（v1 锁步）** | | **约 3–4 周** |
| 回滚（v2） | 快照环形缓冲、重放、预测 | 另加 2–3 周 |

**风险**：iPad 6 上 A10 的回滚重放成本需实测；跨 NAT 成功率取决于是否有中继服务器（需额外运维成本）。

---

## 7. TODO（本期不实现）

- [ ] 实现 `RetroSession` 协议与锁步循环（替换 `runLoopBody` 的联机分支）
- [ ] 输入包编码与冗余发送
- [ ] UDP 传输 + STUN 打洞 + 中继兜底
- [ ] 握手校验（core 版本 / ROM SHA1 / core options 指纹）
- [ ] 周期状态哈希与快照纠正
- [ ] 联机大厅 UI 与延迟显示
- [ ] 双机联调与弱网测试
- [ ] （v2）回滚 netplay 与 A10 性能评估
- [ ] （v2）观战模式、三人以上

---

## 8. 结论

技术上可行，路径清晰：**复用现有 CoreBridge 的快照与输入抽象，把 run 循环改成锁步即可**。本期不实现的原因不是技术障碍，而是范围控制——先确保单机体验（三格式、存档、金手指、滤镜、手柄）在 iPad 6 上稳定，再谈联机。

设计要点已固化在代码注释与本文档中，未来启动时按第 6 节顺序推进即可。
