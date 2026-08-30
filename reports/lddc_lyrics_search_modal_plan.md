# LDDC 歌词搜索弹框方案 — 可行性分析与难度评估

> 关联文档：`reports/lddc_lyrics_integration_plan.md`（整体接入规划）
> 本报告聚焦：**在 Admin Web 歌词维护界面新增"在线搜索歌词"按钮 → 弹框搜索/筛选/预览/选择 → 下载并覆盖歌词** 的具体方案
> 日期：2026-08-24 · 模式：Plan（先规划，后执行）

## 一、方案概述

```
Admin Web Songs 页
  └─ 行操作「歌词」→ 歌词维护 Modal（LRC 编辑）
        └─ 【新增】"在线搜索歌词"按钮
              └─ LyricSearchModal（新弹框）
                    ├─ 搜索框（默认带出 title + artist）
                    ├─ 来源筛选（QQ / 酷狗 / 网易云 / Lrclib 多选）
                    ├─ 结果列表（来源徽标、歌名、歌手、时长、逐字标记）
                    ├─ 预览（解析后的歌词行，只读）
                    └─ 确认应用 → 下载 LRC → 覆盖同目录同名 .lrc → 回写 lyricsPath
```

## 二、可行性：高（全链路均有现成模板）

| 环节 | 现成参照 | 复用程度 |
|---|---|---|
| Python 歌词服务 | `packages/downloader`（FastAPI :8002，异步搜索 + 结果缓存 + 轮询） | 直接扩展，新增歌词端点 |
| 后端桥接路由 | `backend/src/routes/download.ts`（authenticateToken + 502 兜底） | 照抄模式，新建 `routes/lyrics.ts` |
| Node 客户端 | `backend/src/services/downloader-client.ts`（fetch + 30s 超时） | 照抄模式，新建 `lyrics-client.ts` |
| admin-web API 封装 | `admin-web/src/api/download.ts` | 照抄模式 |
| 搜索→结果→勾选→提交 UI | `admin-web/src/pages/Download.tsx` | 交互模型一致 |
| 歌词落盘覆盖 | `PUT /api/songs/:id/lyrics`（写同目录同名 .lrc + 回写 lyricsPath，separation.ts:728） | **直接复用**，无需改 schema |
| 歌词读取 | `GET /api/songs/:id/lyrics` | 无需改动 |

**存储零改动**：LDDC 输出逐字 LRC 文本 → 走现有 PUT 落盘 → TV/Mobile 播放端无需任何改动即可读新歌词。

## 三、关键架构决策

### 1. LDDC 集成位置：扩展现有 downloader 微服务（推荐）
- 理由：复用 venv / Dockerfile / docker-compose / 健康检查 / 日志轮询；歌词本质也是"下载"；musicdl 与 LDDC 同属 CharlesPikachu 系，模式一致。
- 备选：新建 lddc 微服务（:8003），职责更纯但新增部署单元成本高，**不推荐**。

### 2. LDDC headless 调用（最大不确定点）
- LDDC 硬依赖 `PySide6-Essentials`（GUI），但 `core/api/lyrics/`（qm/kg/ne/lrclib）在架构重构中已与 GUI 分离，核心逻辑仅依赖 httpx。
- 两种做法：
  - **A. 直接 pip 安装 LDDC 并 import**：需验证 `import LDDC.core.api.lyrics` 是否会连带导入 PySide6（无头 Linux 可 import 但不可建 QApplication，需实测）。安装体积 ~100MB+。
  - **B. Vendor 歌词核心模块**（推荐）：仅拷贝 `LDDC/core/api/lyrics/` + 解密/模型依赖进 downloader，依赖面收窄到 httpx + 纯 Python 库，**彻底规避 PySide6 与 GUI 启动风险**。
- 结论：无论 A/B 都可行，B 更干净，工作量略增。

### 3. 后端 API 设计（新增 `routes/lyrics.ts`）
| 端点 | 说明 |
|---|---|
| `POST /api/lyrics/search` | body: `{ songId, keyword?, sources? }`，按 title+artist 搜，返回 `search_id`（异步，后台线程跑 LDDC） |
| `GET /api/lyrics/search/:id` | 轮询结果 `{ status, results: [{ key, source, title, artist, duration, wordTiming }] }`（key 复用 downloader 的 `search_id|source|idx` 缓存模式） |
| `POST /api/lyrics/apply` | body: `{ songId, key }` → 后端拉取 LRC → 复用 PUT 落盘逻辑写同目录同名 .lrc → 回写 lyricsPath → 返回 `{ lineCount, wordTiming }` |

> 简化点：`apply` 由后端一次完成（拉取 + 落盘 + 回写），前端避免"先拉 content 再走 saveLyrics"的两次往返；也可前端拉 content 后走现有 saveLyrics，二选一。

### 4. admin-web UI（歌词 Modal + 新弹框）
- 歌词维护 Modal 顶部新增「在线搜索歌词」按钮（loading 态、来源服务不可用降级提示）。
- 新组件 `LyricSearchModal`：搜索（默认填 title + artist）、来源多选（≤4）、结果列表（来源徽标 + 逐字标记）、行内预览（解析歌词只读展示，可滚动）、确认应用（应用前确认提示"将覆盖现有歌词"）。
- 遵循 Hallmark（admin-web → modern-minimal，OKLCH 令牌，8 状态，禁 hex/rgb）。
- 应用成功后：关闭弹框 → 重新 `getLyricsRaw` 刷新 Modal 文本 → toast。

## 四、难度评估

| 部分 | 难度 | 说明 |
|---|---|---|
| downloader 扩展（LDDC 封装） | **中** | LDDC API 适配 + 异步搜索 + 三端点；vendor 方案需先验证 import 边界 |
| 后端桥接 | **低** | 照抄 download.ts 模式 |
| admin-web 弹框 UI | **中** | 新组件 + 多交互状态，参考 Download.tsx；纯前端工作 |
| 端到端验证 | **中** | 需真实网络调 QQ/酷狗/网易云（反爬风险），失败兜底 + 降级提示 |
| **合计** | **中低** | 约 1 个工作日核心量，无 schema 变更、无 TV 端改动 |

## 五、风险与对策

1. **LDDC 携带 PySide6** → vendor 歌词核心模块规避（决策 2-B）。
2. **平台反爬/接口变更/歌词源失效** → 沿用 LDDC 内置 `timeout_retry` + 多源；后端统一 502 + 前端降级提示"歌词服务不可用"。
3. **误覆盖现有歌词** → 应用前确认弹窗（已有 clearLyricsConfirmOpen 同类模式）；可考虑"先备份旧 .lrc 为 .lrc.bak"（可选增强）。
4. **逐字 LRC 解析兼容** → 落盘内容保持 LDDC 原始输出；前端歌词 Modal 显示原始文本（现有 textarea 天然支持）；`GET /lyrics` 的 parseLRC 已识别 `<mm:ss.xx>` 标签，TV 端逐字渲染属后续增强（见整体规划），不影响本次"覆盖歌词"目标。
5. **许可合规（需注意）**：LDDC 为 **GPL-3.0-only**。HTTP 服务隔离（独立进程调用）通常视为隔离；但若 vendor 代码进 downloader 进程则构成衍生，需按 GPL 处置。建议：保持"独立进程/模块边界"，并在 README/归档注明来源与许可。对比：现有 musicdl 为 MIT，无此问题。

## 六、落地步骤（待确认后执行）

1. 确认 LDDC 集成方式（pip 依赖 vs vendor 核心模块）+ 是否扩展现有 downloader。
2. downloader 新增歌词端点（search / result / fetch-apply），后端新增 `lyrics-client.ts` + `routes/lyrics.ts`（注册进 `routes/index.ts`）。
3. admin-web：`api/lyrics.ts` + `LyricSearchModal` 组件 + 歌词 Modal 按钮接线。
4. 后端 `POST /api/lyrics/apply` 复用现有落盘逻辑。
5. 端到端验证（真机网络搜索 → 预览 → 应用 → TV/Mobile 读取新歌词）。

## 七、待用户确认

- 集成方式：A（pip 装 LDDC）还是 B（vendor 核心模块，推荐）？
- 扩展现有 downloader 微服务（推荐）还是新建独立服务？
- 是否需要在应用前备份旧歌词（.bak）？
- 弹框内预览是否需要"逐字时间轴"预览（更炫但工作量+），还是行级文本预览即可？
