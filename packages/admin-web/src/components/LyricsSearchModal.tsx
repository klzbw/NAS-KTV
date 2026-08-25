/* Hallmark · component: lyrics-search-modal · genre: modern-minimal · theme: Cobalt
 * pattern: source-chip-bar · async search + poll · candidate list · LRC preview
 * states: default · hover · focus-visible · active · disabled · loading · error · success
 */

import { useEffect, useRef, useState, useCallback } from 'react';
import { Search, Loader2, FileText, ArrowLeft } from 'lucide-react';
import Modal from './Modal';
import Button from './Button';
import Badge from './Badge';
import EmptyState from './EmptyState';
import { lyricsApi, type LyricSource, type LyricCandidate, type LyricPreview } from '../api/lyrics';
import type { Song } from '../types';

const SOURCE_BADGE: Record<string, 'info' | 'danger' | 'neutral'> = {
  qm: 'info',
  kugou: 'info',
  netease: 'danger',
  lrclib: 'neutral',
};

interface LyricsSearchModalProps {
  isOpen: boolean;
  onClose: () => void;
  song: Song | null;
  /** 选中某候选歌词后回调，把 LRC 文本回填到上级歌词编辑器（由上级统一保存） */
  onApply: (lrc: string) => void;
}

function LyricsSearchModal({ isOpen, onClose, song, onApply }: LyricsSearchModalProps) {
  const [sources, setSources] = useState<LyricSource[]>([]);
  const [selectedSources, setSelectedSources] = useState<Set<string>>(new Set());
  const [keyword, setKeyword] = useState('');
  const [searching, setSearching] = useState(false);
  const [results, setResults] = useState<LyricCandidate[]>([]);
  const [perSource, setPerSource] = useState<Record<string, number>>({});
  const [errors, setErrors] = useState<Record<string, string> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [searched, setSearched] = useState(false);

  const [preview, setPreview] = useState<LyricPreview | null>(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [previewError, setPreviewError] = useState<string | null>(null);

  const searchPollRef = useRef<number | null>(null);
  const searchingRef = useRef(false);
  const lastSearchKeyRef = useRef<string | null>(null);

  const clearPoll = useCallback(() => {
    if (searchPollRef.current) {
      window.clearInterval(searchPollRef.current);
      searchPollRef.current = null;
    }
  }, []);

  // 打开时加载可用源并预填关键词（歌手 - 标题）
  useEffect(() => {
    if (!isOpen) return;
    setResults([]);
    setPerSource({});
    setErrors(null);
    setError(null);
    setSearched(false);
    setPreview(null);
    setPreviewError(null);
    searchingRef.current = false;
    lastSearchKeyRef.current = null;
    clearPoll();

    const defaultKeyword = song
      ? [song.artistName, song.title].filter(Boolean).join(' - ')
      : '';
    setKeyword(defaultKeyword);

    lyricsApi
      .sources()
      .then((list) => {
        setSources(list);
        setSelectedSources(new Set(list.filter((s) => s.enabled).map((s) => s.key)));
      })
      .catch(() => {
        setError('无法连接歌词服务（下载微服务未启动？）');
      });
    // 仅在开关切换时重置，避免重复拉取
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen]);

  useEffect(() => () => clearPoll(), [clearPoll]);

  const toggleSource = (key: string) => {
    setSelectedSources((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  };

  const pollSearch = useCallback(
    (searchId: string) => {
      clearPoll();
      let attempts = 0;
      const MAX_ATTEMPTS = 80; // 80 × 1.5s ≈ 120s 兜底
      searchPollRef.current = window.setInterval(async () => {
        attempts += 1;
        try {
          const r = await lyricsApi.searchResult(searchId);
          if (r.status === 'done') {
            setResults(r.results);
            setPerSource(r.per_source || {});
            setErrors(r.errors || null);
            setSearching(false);
            searchingRef.current = false;
            clearPoll();
          } else if (r.status === 'failed') {
            setError('搜索失败，请稍后重试');
            setSearching(false);
            searchingRef.current = false;
            lastSearchKeyRef.current = null;
            clearPoll();
          } else if (attempts >= MAX_ATTEMPTS) {
            setError('搜索超时，请稍后重试');
            setSearching(false);
            searchingRef.current = false;
            lastSearchKeyRef.current = null;
            clearPoll();
          }
        } catch {
          /* 忽略轮询抖动，下一轮继续 */
        }
      }, 1500);
    },
    [clearPoll],
  );

  const doSearch = async () => {
    const kw = keyword.trim();
    if (!kw) return;
    if (searchingRef.current) return;
    const srcs = sources.filter((s) => selectedSources.has(s.key)).map((s) => s.key);
    const key = `${kw}|${[...selectedSources].sort().join(',')}`;
    if (lastSearchKeyRef.current === key && searched) return;
    searchingRef.current = true;
    setSearching(true);
    setError(null);
    setResults([]);
    setPerSource({});
    setErrors(null);
    setPreview(null);
    setSearched(true);
    lastSearchKeyRef.current = key;
    try {
      const data = await lyricsApi.search(kw, srcs.length ? srcs : undefined);
      pollSearch(data.search_id);
    } catch {
      setError('搜索提交失败，请检查歌词服务');
      setSearching(false);
      searchingRef.current = false;
      lastSearchKeyRef.current = null;
    }
  };

  const selectCandidate = async (c: LyricCandidate) => {
    setPreviewLoading(true);
    setPreviewError(null);
    setPreview(null);
    try {
      const [searchId, source, idxStr] = c.key.split('|');
      const data = await lyricsApi.preview(searchId, source, parseInt(idxStr, 10));
      setPreview(data);
    } catch {
      setPreviewError('该候选暂无可用歌词，换一首试试');
    } finally {
      setPreviewLoading(false);
    }
  };

  const applyLyrics = () => {
    if (!preview) return;
    onApply(preview.lrc);
    onClose();
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="搜索歌词（LDDC 云端歌词）" size="lg">
      <div className="space-y-4">
        <p className="text-xs text-ink-2">
          从 QQ 音乐 / 酷狗 / 网易云 / Lrclib 搜索歌词，选中后预览确认，再回填到歌词编辑器保存。
        </p>

        {error && (
          <div className="rounded-md border border-danger bg-paper px-4 py-3 text-sm text-danger">
            {error}
          </div>
        )}

        {/* 搜索区 */}
        <div className="rounded-lg border border-border bg-paper-2 p-3 space-y-3">
          <div className="flex flex-wrap gap-2">
            {sources.map((s) => {
              const active = selectedSources.has(s.key);
              return (
                <button
                  key={s.key}
                  type="button"
                  disabled={!s.enabled}
                  onClick={() => toggleSource(s.key)}
                  aria-pressed={active}
                  className={[
                    'inline-flex items-center h-8 px-3 rounded-md text-sm border transition-colors',
                    'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2 focus-visible:ring-offset-paper',
                    !s.enabled
                      ? 'opacity-40 cursor-not-allowed border-border text-ink-2'
                      : active
                        ? 'border-accent bg-[color-mix(in_oklch,var(--color-accent)_14%,transparent)] text-accent'
                        : 'border-border text-ink-2 hover:bg-paper-3',
                  ].join(' ')}
                >
                  {s.label}
                </button>
              );
            })}
          </div>

          <div className="flex gap-2">
            <input
              value={keyword}
              onChange={(e) => setKeyword(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && doSearch()}
              placeholder="输入歌名 / 歌手 / 关键词"
              className="flex-1 h-10 px-3 rounded-md border border-border bg-paper text-ink placeholder:text-ink-2
                focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2 focus-visible:ring-offset-paper"
            />
            <Button onClick={doSearch} loading={searching} leftIcon={<Search className="w-4 h-4" />}>
              搜索
            </Button>
          </div>
        </div>

        {/* 搜索中提示 */}
        {searching && results.length === 0 && (
          <div className="rounded-lg border border-border bg-paper p-4 flex items-center gap-3 text-sm text-ink-2">
            <Loader2 className="w-4 h-4 animate-spin text-accent" />
            正在搜索各音源，请稍候（慢源可能需数十秒）…
          </div>
        )}

        {/* 预览态 */}
        {preview && (
          <div className="rounded-lg border border-border bg-paper p-3 space-y-3">
            <div className="flex items-center justify-between gap-2">
              <div className="flex items-center gap-2 min-w-0">
                <Badge variant={SOURCE_BADGE[preview.source] || 'neutral'}>
                  {sources.find((s) => s.key === preview.source)?.label || preview.source}
                </Badge>
                <span className="text-sm font-medium text-ink truncate">{preview.title}</span>
              </div>
              <Button size="sm" variant="ghost" onClick={() => setPreview(null)} leftIcon={<ArrowLeft className="w-4 h-4" />}>
                返回列表
              </Button>
            </div>
            <textarea
              readOnly
              value={preview.lrc}
              className="w-full h-64 p-3 rounded-md border border-border bg-paper-2 text-ink font-mono text-xs leading-relaxed
                focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2 focus-visible:ring-offset-paper"
            />
            <div className="flex items-center justify-between">
              <span className="text-xs text-ink-2">{preview.lrc.split('\n').filter(Boolean).length} 行</span>
              <Button onClick={applyLyrics} leftIcon={<FileText className="w-4 h-4" />}>
                使用此歌词
              </Button>
            </div>
          </div>
        )}

        {/* 预览加载 / 错误 */}
        {!preview && previewLoading && (
          <div className="rounded-lg border border-border bg-paper p-4 flex items-center gap-3 text-sm text-ink-2">
            <Loader2 className="w-4 h-4 animate-spin text-accent" />
            正在获取歌词预览…
          </div>
        )}
        {!preview && previewError && (
          <div className="rounded-md border border-danger bg-paper px-4 py-3 text-sm text-danger">
            {previewError}
          </div>
        )}

        {/* 候选列表 */}
        {!preview && !previewLoading && results.length > 0 && (
          <div className="rounded-lg border border-border bg-paper divide-y divide-border max-h-80 overflow-y-auto">
            {results.map((c) => (
              <button
                key={c.key}
                type="button"
                onClick={() => selectCandidate(c)}
                className="w-full text-left flex items-center gap-3 px-3 py-2.5 hover:bg-paper-2
                  focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-inset"
              >
                <Badge variant={SOURCE_BADGE[c.source] || 'neutral'} className="shrink-0">
                  {c.source_label}
                </Badge>
                <div className="min-w-0 flex-1">
                  <div className="text-sm font-medium text-ink truncate">{c.title}</div>
                  <div className="text-xs text-ink-2 truncate">
                    {[c.artist, c.album].filter(Boolean).join(' · ') || '未知'}
                  </div>
                </div>
                {c.duration && <span className="text-xs text-ink-3 shrink-0">{c.duration}</span>}
              </button>
            ))}
          </div>
        )}

        {/* 空结果 */}
        {!preview && !previewLoading && !searching && results.length === 0 && searched && (
          <div className="rounded-lg border border-border bg-paper">
            <EmptyState
              icon={<Search className="w-8 h-8" />}
              title="未找到相关歌词"
              description="换个关键词，或在上方多勾选几个音源后重试"
            />
          </div>
        )}

        {/* 各源命中情况（搜索完成后展示） */}
        {!preview && !searching && results.length > 0 && Object.keys(perSource).length > 0 && (
          <div className="flex flex-wrap gap-2 text-xs text-ink-2">
            {sources.map((s) => {
              const count = perSource[s.key];
              const failed = errors?.[s.key];
              if (count === undefined && !failed) return null;
              return (
                <span key={s.key} className="inline-flex items-center gap-1">
                  {s.label}：
                  {failed ? (
                    <span className="text-danger">不可用</span>
                  ) : (
                    <span className="text-ink">{count} 条</span>
                  )}
                </span>
              );
            })}
          </div>
        )}
      </div>
    </Modal>
  );
}

export default LyricsSearchModal;
