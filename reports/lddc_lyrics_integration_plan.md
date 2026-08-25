# LDDC 逐句（逐字）歌词接入 NASKTV — 可行性分析与落地规划

> 调研对象：https://github.com/chenmozhijin/LDDC
> 目标：将 LDDC 的逐句/逐字歌词能力接入 NASKTV 现有歌词体系
> 日期：2026-08-24
> 模式：Plan（先规划，后执行）

## 一、LDDC 能力盘点

LDDC（沉默の金）是 Python 歌词匹配工具，核心能力：

| 维度 | 内容 |
|---|---|
| 支持平台 | QQ音乐、酷狗音乐、网易云音乐、Lrclib（英文/无版权歌） |
| 输出格式 | **逐字 LRC**（每行内嵌 `<mm:ss.xx>` 逐字标签）、逐行 LRC、增强 LRC、SRT、ASS |
| 接入形态 | 有 Python API（`LyricsAPI.search` / `get_lyrics`），可嵌入服务端，不仅 GUI |
| 中文支持 | 良好（QQ/酷狗/网易云均为中文曲库主力） |
| 定位 | 歌词"查找/匹配/下载"工具，**不负责持久化**（输出 LRC 文本/文件，需自行落库） |

关键结论：LDDC 输出的是**带逐字时间戳的 LRC 文本**，而我们现有 `.lrc` 同目录同名方案天然可以承接。

## 二、NASKTV 现有歌词体系（现状基线）

| 环节 | 现状 | 与逐字歌词的关系 |
|---|---|---|
| 存储 | `songs.lyricsPath` 指向 `data/` 下 `.lrc` 文件（与音频同目录同名） | ✅ 同目录同名布局，LDDC 输出可直接落盘 |
| 解析 | `packages/backend/src/services/lyrics-parser.ts` 的 `parseLRC()` 返回 `{time, text}[]`；已识别 `WORD_TIMING_REGEX`（`<mm:ss.xx>`）并置 `wordTiming=true` | ⚠️ 只展开行级时间戳，逐字时间戳未解析进数据结构 |
| 接口 | `GET /api/songs/:id/lyrics` → `{lines, wordTiming}`（`packages/backend/src/routes/separation.ts:654`） | ⚠️ `lines` 为行级，逐字被丢弃 |
| 前端类型 | `LyricLine {time, text}`；`wordTiming` 已被 `packages/tv-app/src/api/songs.ts` 识别 | ⚠️ 类型缺少 `words` 子结构 |
| 前端渲染 | `packages/tv-app/src/components/Lyrics.tsx` 已实现整行动态渐变（rAF 直写 `background-position`） | ⚠️ 按整行着色，非逐字 |

## 三、对接方案（两种深度）

### 方案 A：复用现有 LRC 链路（推荐先做）
1. 新增微服务端点（扩展 `downloader` 或独立 LDDC 服务，复用 Python venv 约定）：按 `title/artist` 调用 LDDC 搜索并下载**逐字 LRC**，落盘为与音频同目录同名的 `.lrc`，回写 `songs.lyricsPath`（已有字段，无需改 schema）。
2. 升级 `parseLRC`：检测到 `wordTiming` 时，把一行内交错的 `<mm:ss.xx>`/`</mm:ss.xx>` 标签解析为 `words: LyricWord[]`（含 `text`/`startTime`/`endTime`），附加到每行。**不破坏**现有 `LyricLine {time, text}`（向后兼容）。
3. `GET /api/songs/:id/lyrics` 返回 `lines`，每行可选带 `words`。
4. TV/Mobile 渲染：在 `Lyrics.tsx` 现有逐行渐变机制上，下沉到逐字着色（把 `background-position` 计算粒度从"行"改到"字"）。

### 方案 B：结构化 JSON 存储（按需）
- 把逐字歌词存为 `data/lyrics/<id>.json`（含每行 `words`），而非压在 LRC 文本里。
- 优点：便于查询、翻译、AI 审核；缺点：需新增 schema 字段 + 追加 Drizzle 迁移。
- 建议仅在方案 A 验证成熟后再考虑。

## 四、难度与风险

- **整体难度：中低**。约 70% 工作量在你们已熟悉的 TV 逐行渐变逻辑改造；LDDC 集成是薄封装。
- **主要风险**：
  1. LDDC 依赖目标平台接口稳定性（反爬/限流） → 需超时与失败兜底（复用其 `timeout_retry` 范式）。
  2. 逐字 LRC 解析需处理标签与文本交错、占位对齐（行内 `<00:12.00>text<00:12.50>text`）是核心难点。
  3. 中文歌匹配准确率依赖元数据质量 → 建议走"扫描后自动匹配 + Admin 人工审核"（已有 AI 审核框架）。
  4. TV 端 `Lyrics.tsx` 渐变走 DOM 直写（rAF），逐字需逐字套用同一机制；务必保持 chrome70 兼容（禁用 `inset`/`min`/`max`/`clamp`，沿用 vmin）。

## 五、建议落地步骤（待确认后执行）

1. 确认方案 A / B。
2. Python 侧封装 LDDC 调用（独立脚本或新微服务，复用 venv）。
3. 扩展 `parseLRC` + 新增 `LyricWord` 类型 + 后端接口返回 `words`。
4. TV/Mobile 逐字渲染改造（沿用现有渐变）。
5. 扫描流程新增"歌词自动匹配"开关（参考 `separator_auto_enable` 模式，存 settings 表）。

## 六、待用户确认

- 采用方案 A（LRC 内嵌）还是方案 B（JSON 结构化）？
- LDDC 集成走"独立微服务"还是扩展现有 downloader 微服务？
- 是否要同时覆盖 TV / Mobile-H5 两端，还是先 TV？
