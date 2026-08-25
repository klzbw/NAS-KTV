/**
 * LRC 歌词解析器
 *
 * 将标准 LRC 文本解析为 `{ time, text }` 数组，time 单位为秒。
 * 支持两种时间戳格式：
 *   - [mm:ss.xx]（如 [00:12.50]一行歌词 → { time: 12.5, text: "一行歌词" }）
 *   - [mm:ss]    （如 [01:30]一行歌词   → { time: 90, text: "一行歌词" }）
 * 支持多时间戳行（如 [00:01.00][01:30.00]同一行歌词 展开为两条记录）。
 * 不含时间戳的行（含 ID 标签如 [ti:xxx]、空行等）跳过。
 */

import fs from 'fs';

export interface LyricLine {
  /** 时间戳，单位秒 */
  time: number;
  /** 歌词文本 */
  text: string;
  /** 逐字歌词（仅源 LRC 含 <mm:ss.xx> 逐字标签时存在） */
  words?: LyricWord[];
}

/** 逐字歌词片段 */
export interface LyricWord {
  /** 逐字文本 */
  text: string;
  /** 逐字起播时间，单位秒（绝对歌曲时间） */
  start: number;
  /** 逐字结束时间，单位秒（绝对歌曲时间） */
  end: number;
}

export interface ParseResult {
  lines: LyricLine[];
  /** 是否为逐字歌词（源 LRC 含 <mm:ss.xx> 逐字时间标签；展示文本已剥离标签） */
  wordTiming: boolean;
}

// 匹配单条时间戳：[mm:ss] 或 [mm:ss.xx]，秒与毫秒均允许 1-2 位
const TIMESTAMP_REGEX = /\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]/g;

// 逐字歌词标签：<mm:ss.xx> 或 <mm:ss>
const WORD_TIMING_REGEX = /<\d{1,2}:\d{1,2}(?:\.\d{1,3})?>/;
// 与上同，但带 g 标志用于剥离（检测用 WORD_TIMING_REGEX 不带 g，避免 lastIndex 副作用）
const WORD_TIMING_STRIP_REGEX = /<\d{1,2}:\d{1,2}(?:\.\d{1,3})?>/g;

// 时间戳标签（行级或字级）<mm:ss.xx> 解析为秒
function tagToSeconds(mm: string, ss: string, frac?: string): number {
  const m = parseInt(mm, 10);
  const s = parseInt(ss, 10);
  // 将小数部分作为 0.{frac} 解析，自动适配 1-3 位精度
  const fracSeconds = frac ? parseFloat('0.' + frac) : 0;
  return m * 60 + s + fracSeconds;
}

/**
 * 从「仍保留逐字 <mm:ss.xx> 标签」的行文本中解析字级时间轴。
 *
 * 增强型 LRC 字标签格式：<起播>字<结束><起播2>字2<结束2>…
 * 相邻「结束 / 起播」标签间无文本（标记词边界），故每段文本夹在
 * 第 i 个标签之后、第 i+1 个标签之前即为第 i 个逐字片段。
 * 返回逐字数组（start/end 为绝对秒），无字标签时返回 null。
 */
function parseWordTiming(textWithTags: string): LyricWord[] | null {
  const TAG = /<(\d{1,2}):(\d{1,2})(?:\.\d{1,3})?>/g;
  const tags: { time: number; start: number; end: number }[] = [];
  let m: RegExpExecArray | null;
  while ((m = TAG.exec(textWithTags)) !== null) {
    tags.push({
      time: tagToSeconds(m[1], m[2], m[3]),
      start: m.index,
      end: m.index + m[0].length,
    });
  }
  if (tags.length < 2) return null;
  const words: LyricWord[] = [];
  for (let i = 0; i < tags.length - 1; i++) {
    const text = textWithTags.slice(tags[i].end, tags[i + 1].start).trim();
    if (!text) continue; // 空段 = 词边界（结束标签紧接下一词起播标签）
    words.push({ text, start: tags[i].time, end: tags[i + 1].time });
  }
  return words.length > 0 ? words : null;
}

/**
 * 读取歌词文件并智能解码。
 *
 * 优先按 UTF-8 解码；若出现替换字符 U+FFFD（说明原文件为 GBK/GB2312
 * 等中文编码），则回退用 GBK 解码，避免导入的 .lrc 显示乱码。
 * 解码后统一剥离 BOM。
 */
export function readLyricsFile(filePath: string): string {
  const buf = fs.readFileSync(filePath);
  const utf8 = new TextDecoder('utf-8').decode(buf);
  if (!utf8.includes('\uFFFD')) {
    return utf8.replace(/^\uFEFF/, '');
  }
  try {
    return new TextDecoder('gbk').decode(buf).replace(/^\uFEFF/, '');
  } catch {
    return utf8;
  }
}

/**
 * 解析 LRC 文本为歌词行数组。
 *
 * @param content LRC 原始文本
 * @returns 按时间升序排列的歌词行 + 是否逐字歌词
 */
export function parseLRC(content: string): ParseResult {
  const lines: LyricLine[] = [];
  let wordTiming = false;

  for (const rawLine of content.split(/\r?\n/)) {
    const stamps = [...rawLine.matchAll(TIMESTAMP_REGEX)];
    if (stamps.length === 0) continue;

    // 去掉所有时间戳得到纯歌词文本（仍含逐字 <mm:ss.xx> 标签）
    const text = rawLine.replace(TIMESTAMP_REGEX, '').trim();

    // 解析逐字时间轴（标签此刻仍保留在 text 中）
    const words = parseWordTiming(text);
    if (words) {
      wordTiming = true;
    }

    // 剥离内联逐字标签，得到展示用的纯文本（字级数据已存入 words）
    const cleanText = text.replace(WORD_TIMING_STRIP_REGEX, '').trim();

    for (const stamp of stamps) {
      const mm = parseInt(stamp[1], 10);
      const ss = parseInt(stamp[2], 10);
      // 将小数部分作为 0.{frac} 解析，自动适配 1-3 位精度
      const fracSeconds = stamp[3] ? parseFloat('0.' + stamp[3]) : 0;
      lines.push({
        time: mm * 60 + ss + fracSeconds,
        text: cleanText,
        words: words ?? undefined,
      });
    }
  }

  // 按时间升序排列
  lines.sort((a, b) => a.time - b.time);
  return { lines, wordTiming };
}
