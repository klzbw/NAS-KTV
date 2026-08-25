/* Hallmark · component: ai-parse-result-editor · genre: modern-minimal · theme: Cobalt
 * pattern: inline field grid · controlled inputs
 * states: default · focus-visible · disabled
 *
 * AI 解析结果人工干预编辑器（受控组件）：在 AI 解析结果基础上编辑
 * title / artists / album / genre / language / mood / year / confidence，
 * 供 AiParse 详情页与歌曲管理页审核弹窗复用。
 *
 * 歌手输入采用「本地文本 + 失焦提交」：若用 value(join) ↔ onChange(split) 的
 * 受控往返，输入框中的分隔符（、/，&）会在 split → filter → join 过程中被吞掉，
 * 导致无法输入/插入分隔符。
 */
import { useState } from 'react';
import type { Dispatch, SetStateAction } from 'react';

export interface AiParseResultEditorProps {
  value: Record<string, unknown>;
  onChange: Dispatch<SetStateAction<Record<string, unknown> | null>>;
}

const TEXT_FIELDS: [string, string][] = [
  ['title', '标题'],
  ['album', '专辑'],
  ['genre', '风格'],
  ['language', '语种'],
  ['mood', '心情'],
];

const inputCls =
  'w-full rounded-md border border-border bg-paper-2 text-sm text-ink px-3 py-1.5 ' +
  'focus-visible:border-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent';

export default function AiParseResultEditor({ value, onChange }: AiParseResultEditorProps) {
  // 歌手输入框保留原始文本（含分隔符），失焦时统一解析为数组提交，避免分隔符被吞
  const [artistsInput, setArtistsInput] = useState(() => {
    const artists = value.artists;
    return Array.isArray(artists)
      ? (artists as unknown[]).map(String).join('、')
      : String(artists ?? '');
  });

  const handleArtistsBlur = () => {
    onChange((d) => ({
      ...(d ?? {}),
      artists: artistsInput
        .split(/[、/,，&]/)
        .map((s) => s.trim())
        .filter(Boolean),
    }));
  };

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 gap-sm">
      <div>
        <label className="block text-xs text-ink-3 mb-xs">歌手</label>
        <input
          type="text"
          className={inputCls}
          value={artistsInput}
          onChange={(e) => setArtistsInput(e.target.value)}
          onBlur={handleArtistsBlur}
        />
        <p className="text-[11px] text-ink-3 mt-1 leading-snug">
          多位歌手用顿号、逗号、斜杠或 &amp; 分隔，第一位为主歌手
        </p>
      </div>
      {TEXT_FIELDS.map(([key, label]) => (
        <div key={key}>
          <label className="block text-xs text-ink-3 mb-xs">{label}</label>
          <input
            type="text"
            className={inputCls}
            value={String(value[key] ?? '')}
            onChange={(e) =>
              onChange((d) => ({
                ...(d ?? {}),
                [key]: e.target.value,
              }))
            }
          />
        </div>
      ))}
      {(
        [
          ['year', '年份'],
          ['confidence', '置信度'],
        ] as [string, string][]
      ).map(([key, label]) => (
        <div key={key}>
          <label className="block text-xs text-ink-3 mb-xs">{label}</label>
          <input
            type="number"
            className={inputCls}
            value={String(value[key] ?? '')}
            onChange={(e) =>
              onChange((d) => ({
                ...(d ?? {}),
                [key]: e.target.value === '' ? '' : Number(e.target.value),
              }))
            }
          />
        </div>
      ))}
    </div>
  );
}
