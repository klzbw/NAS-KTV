/* Hallmark · component: transcode-page · genre: modern-minimal · theme: Cobalt
 * states: default · hover · focus · active · disabled · loading · error · success
 * contrast: pass (46–50)
 */
import { useState, useEffect, useCallback, useRef } from 'react';
import {
  Film,
  RefreshCw,
  Loader2,
  AlertCircle,
  Search,
  Trash2,
  StopCircle,
  ChevronLeft,
  ChevronRight,
  X,
  Plus,
  Square,
  CheckSquare,
  Play,
} from 'lucide-react';
import { transcodeApi } from '../api/transcode';
import { songsApi } from '../api/songs';
import type { TranscodeTask, Song } from '../types';
import Button from '../components/Button';
import EmptyState from '../components/EmptyState';
import Badge from '../components/Badge';
import Modal from '../components/Modal';
import Loading from '../components/Loading';
import { useToast } from '../components/Toast';
import Pagination from '../components/Pagination';
import { TRANSCODE_PROFILES, transcodeProfileLabel } from '../constants';

type TaskStatus = 'pending' | 'processing' | 'completed' | 'failed';

const statusVariantMap: Record<TaskStatus, 'neutral' | 'warning' | 'success' | 'danger'> = {
  pending: 'neutral',
  processing: 'warning',
  completed: 'success',
  failed: 'danger',
};

const statusLabel: Record<TaskStatus, string> = {
  pending: '待处理',
  processing: '处理中',
  completed: '已完成',
  failed: '失败',
};

/** transcode 阶段英文 → 中文进度名 */
const STAGE_LABELS: Record<string, string> = {
  transcoding: '转码中',
  done: '完成',
};

function stageLabel(stage: string | null | undefined): string {
  if (!stage) return '';
  return STAGE_LABELS[stage] ?? stage;
}

function isKnownStatus(s: string): s is TaskStatus {
  return Object.prototype.hasOwnProperty.call(statusLabel, s);
}

const filterTabs: { value: string; label: string }[] = [
  { value: 'all', label: '全部' },
  { value: 'pending', label: '待处理' },
  { value: 'processing', label: '处理中' },
  { value: 'completed', label: '已完成' },
  { value: 'failed', label: '失败' },
];

function formatTime(iso: string): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '—';
  const pad = (n: number) => n.toString().padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export default function Transcode() {
  const [tasks, setTasks] = useState<TranscodeTask[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [actionLoadingId, setActionLoadingId] = useState<number | null>(null);
  const [batchRetrying, setBatchRetrying] = useState(false);
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(20);
  const [total, setTotal] = useState(0);

  const [selectedIds, setSelectedIds] = useState<Set<number>>(new Set());
  const [ffmpegOk, setFfmpegOk] = useState<boolean | null>(null);

  const [triggerProfile, setTriggerProfile] = useState<string>('standard');

  const [showSongModal, setShowSongModal] = useState(false);
  const [songSearch, setSongSearch] = useState('');
  const [songResults, setSongResults] = useState<Song[]>([]);
  const [songLoading, setSongLoading] = useState(false);
  const [songPage, setSongPage] = useState(1);
  const [songTotal, setSongTotal] = useState(0);

  const [preview, setPreview] = useState<{ songId: number; songTitle?: string } | null>(null);

  const [confirmDialog, setConfirmDialog] = useState<{
    title: string;
    message: string;
    onConfirm: () => void;
  } | null>(null);

  const { showToast, ToastContainer } = useToast();

  const hasProcessing = tasks.some(t => t.status === 'processing');
  const totalPages = Math.max(1, Math.ceil(total / pageSize));
  const songTotalPages = Math.max(1, Math.ceil(songTotal / 10));

  const loadTasks = useCallback(async () => {
    setLoading(true);
    try {
      const params: { page: number; pageSize: number; status?: string } = {
        page,
        pageSize,
      };
      if (statusFilter !== 'all') params.status = statusFilter;
      const res = await transcodeApi.getTasks(params);
      setTasks(res.items ?? []);
      setTotal(res.total ?? 0);
    } catch (err) {
      const msg = err instanceof Error ? err.message : '加载任务列表失败';
      showToast('error', msg);
    } finally {
      setLoading(false);
    }
  }, [page, pageSize, statusFilter, showToast]);

  const checkFfmpeg = useCallback(async () => {
    try {
      const ok = await transcodeApi.ffmpegAvailable();
      setFfmpegOk(ok);
    } catch {
      setFfmpegOk(null);
    }
  }, []);

  useEffect(() => {
    loadTasks();
    checkFfmpeg();
  }, [loadTasks, checkFfmpeg]);

  useEffect(() => {
    setPage(1);
    setSelectedIds(new Set());
  }, [statusFilter]);

  useEffect(() => {
    setSelectedIds(new Set());
  }, [page]);

  useEffect(() => {
    if (!hasProcessing) return;
    let hidden = false;
    const interval = setInterval(() => {
      if (!hidden) loadTasks();
    }, 5000);
    const onVis = () => { hidden = document.hidden; };
    document.addEventListener('visibilitychange', onVis);
    return () => {
      clearInterval(interval);
      document.removeEventListener('visibilitychange', onVis);
    };
  }, [hasProcessing, loadTasks]);

  useEffect(() => {
    const wsBaseUrl = `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}/ws?token=${encodeURIComponent(localStorage.getItem('token') ?? '')}`;
    let ws: WebSocket | null = null;
    try {
      ws = new WebSocket(wsBaseUrl);
    } catch {
      return;
    }
    ws.onmessage = (event) => {
      try {
        const message = JSON.parse(event.data);
        const type: string = message.type;
        const payload = message.payload ?? message.data ?? {};
        const taskId: number | undefined = payload.taskId ?? payload.id;
        if (!taskId) return;

        setTasks((prev) =>
          prev.map((t) => {
            if (t.id !== taskId) return t;
            if (type === 'TRANSCODE_STARTED') {
              return { ...t, status: 'processing', progress: 0, stage: payload.stage ?? null };
            }
            if (type === 'TRANSCODE_PROGRESS') {
              const progress =
                typeof payload.progress === 'number' ? payload.progress : t.progress;
              return { ...t, status: 'processing', progress, stage: payload.stage ?? t.stage };
            }
            if (type === 'TRANSCODE_COMPLETED') {
              return {
                ...t,
                status: 'completed',
                progress: 100,
                completedAt: new Date().toISOString(),
                error: null,
              };
            }
            if (type === 'TRANSCODE_FAILED') {
              return { ...t, status: 'failed', error: payload.error || '转码失败' };
            }
            return t;
          })
        );
      } catch {
        // ignore malformed message
      }
    };
    return () => { ws?.close(); };
  }, []);

  const stats = { pending: 0, processing: 0, completed: 0, failed: 0 };
  for (const t of tasks) {
    if (isKnownStatus(t.status)) stats[t.status] += 1;
  }

  const refreshTaskRow = useCallback((updated: TranscodeTask) => {
    setTasks(prev => prev.map(t => (t.id === updated.id ? { ...t, ...updated } : t)));
  }, []);

  const handleRetry = async (task: TranscodeTask) => {
    setActionLoadingId(task.id);
    try {
      const updated = await transcodeApi.retryTask(task.id);
      refreshTaskRow(updated);
      showToast('success', '重试已触发');
    } catch (err) {
      showToast('error', err instanceof Error ? err.message : '重试失败');
    } finally {
      setActionLoadingId(null);
    }
  };

  const handleReTranscode = (task: TranscodeTask) => {
    const song = (task as TranscodeTask & { song?: { title?: string } }).song;
    setConfirmDialog({
      title: '重新转码',
      message: `确定要重新转码「${song?.title || `歌曲 #${task.songId}`}」吗？重新转码将覆盖现有产物。`,
      onConfirm: async () => {
        setActionLoadingId(task.id);
        try {
          await transcodeApi.retryTask(task.id);
          showToast('success', '重新转码已触发');
          await loadTasks();
        } catch (err) {
          showToast('error', err instanceof Error ? err.message : '重新转码失败');
        } finally {
          setActionLoadingId(null);
        }
      },
    });
  };

  const handleStop = (task: TranscodeTask) => {
    const song = (task as TranscodeTask & { song?: { title?: string } }).song;
    setConfirmDialog({
      title: '确认停止',
      message: `确定要停止「${song?.title || `歌曲 #${task.songId}`}」的转码任务吗？停止后任务将标记为失败。`,
      onConfirm: async () => {
        setActionLoadingId(task.id);
        try {
          await transcodeApi.stopTask(task.id);
          setTasks(prev =>
            prev.map(t => (t.id === task.id ? { ...t, status: 'failed', error: '用户手动停止' } : t))
          );
          showToast('success', '任务已停止');
        } catch (err) {
          showToast('error', err instanceof Error ? err.message : '停止失败');
        } finally {
          setActionLoadingId(null);
        }
      },
    });
  };

  const doBatchRetry = async (ids: number[]) => {
    setBatchRetrying(true);
    try {
      const res = await transcodeApi.batchRetry(ids);
      showToast('success', `批量重试完成：成功 ${res.succeeded}，跳过 ${res.skipped}`);
      setSelectedIds(new Set());
      await loadTasks();
    } catch (err) {
      showToast('error', err instanceof Error ? err.message : '批量重试失败');
    } finally {
      setBatchRetrying(false);
    }
  };

  const handleBatchRetry = () => {
    const ids = [...selectedIds].filter(id => {
      const t = tasks.find(x => x.id === id);
      return t && (t.status === 'failed' || t.status === 'pending' || t.status === 'completed');
    });
    if (ids.length === 0) {
      showToast('warning', '没有可重试的选中任务');
      return;
    }
    const completedCount = ids.filter(id => {
      const t = tasks.find(x => x.id === id);
      return t?.status === 'completed';
    }).length;
    if (completedCount > 0) {
      setConfirmDialog({
        title: '批量重新转码',
        message: `选中的任务中有 ${completedCount} 个已完成任务，重新转码将覆盖现有产物。是否继续？`,
        onConfirm: () => doBatchRetry(ids),
      });
      return;
    }
    doBatchRetry(ids);
  };

  const handleBatchDelete = () => {
    const ids = [...selectedIds];
    if (ids.length === 0) return;
    setConfirmDialog({
      title: '确认删除',
      message: `确定要删除选中的 ${ids.length} 个任务吗？此操作不可撤销。`,
      onConfirm: async () => {
        try {
          const res = await transcodeApi.batchDelete(ids);
          showToast('success', `批量删除完成：成功 ${res.succeeded}，跳过 ${res.skipped}`);
          setSelectedIds(new Set());
          await loadTasks();
        } catch (err) {
          showToast('error', err instanceof Error ? err.message : '批量删除失败');
        }
      },
    });
  };

  const handleBatchStop = () => {
    const ids = [...selectedIds].filter(id => {
      const t = tasks.find(x => x.id === id);
      return t && t.status === 'processing';
    });
    if (ids.length === 0) {
      showToast('warning', '没有正在处理的选中任务');
      return;
    }
    setConfirmDialog({
      title: '确认停止',
      message: `确定要停止选中的 ${ids.length} 个正在处理的任务吗？停止后任务将标记为失败。`,
      onConfirm: async () => {
        try {
          const res = await transcodeApi.batchStop(ids);
          showToast('success', `批量停止完成：成功 ${res.succeeded}，跳过 ${res.skipped}`);
          setSelectedIds(new Set());
          await loadTasks();
        } catch (err) {
          showToast('error', err instanceof Error ? err.message : '批量停止失败');
        }
      },
    });
  };

  const toggleSelect = (id: number) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const toggleSelectAll = () => {
    if (selectedIds.size === tasks.length && tasks.length > 0) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(tasks.map(t => t.id)));
    }
  };

  const openPreview = (task: TranscodeTask) => {
    const song = (task as TranscodeTask & { song?: { title?: string } }).song;
    setPreview({ songId: task.songId, songTitle: song?.title });
  };

  const loadSongs = useCallback(async (keyword: string, p: number) => {
    setSongLoading(true);
    try {
      const res = await songsApi.list({ page: p, pageSize: 10, keyword: keyword || undefined });
      setSongResults(res.items ?? []);
      setSongTotal(res.total ?? 0);
    } catch {
      showToast('error', '加载歌曲列表失败');
    } finally {
      setSongLoading(false);
    }
  }, [showToast]);

  const songSearchTimerRef = useRef<ReturnType<typeof setTimeout>>();

  useEffect(() => {
    if (!showSongModal) return;
    clearTimeout(songSearchTimerRef.current);
    songSearchTimerRef.current = setTimeout(() => {
      setSongPage(1);
      loadSongs(songSearch, 1);
    }, 300);
    return () => clearTimeout(songSearchTimerRef.current);
  }, [songSearch, showSongModal, loadSongs]);

  useEffect(() => {
    if (!showSongModal) return;
    loadSongs(songSearch, songPage);
  }, [songPage, showSongModal, songSearch, loadSongs]);

  const triggerSongTranscode = async (song: Song) => {
    try {
      await songsApi.transcode(song.id, triggerProfile);
      showToast('success', `歌曲「${song.title}」转码任务已触发（${transcodeProfileLabel(triggerProfile)}）`);
      setShowSongModal(false);
      setSongSearch('');
      await loadTasks();
    } catch (err) {
      showToast('error', err instanceof Error ? err.message : '触发转码失败');
    }
  };

  const handleSongSelect = (song: Song) => {
    if (song.fileType !== 'video') {
      showToast('warning', '仅视频歌曲支持转码');
      return;
    }
    const status = song.transcodeStatus;
    if (status === 'processing' || status === 'pending') {
      showToast('warning', '该歌曲正在转码中');
      return;
    }
    if (status === 'completed') {
      setConfirmDialog({
        title: '重新转码',
        message: `歌曲「${song.title}」已完成转码，重新转码将覆盖现有产物。是否继续？`,
        onConfirm: () => triggerSongTranscode(song),
      });
      return;
    }
    triggerSongTranscode(song);
  };

  const getSongStatusBadge = (status?: string | null) => {
    if (!status || status === 'none') return null;
    if (!isKnownStatus(status)) return null;
    return <Badge variant={statusVariantMap[status]} size="sm">{statusLabel[status]}</Badge>;
  };

  const allSelected = tasks.length > 0 && selectedIds.size === tasks.length;

  const statCards: {
    label: string;
    value: number;
    variant: 'neutral' | 'warning' | 'success' | 'danger';
  }[] = [
    { label: '待处理', value: stats.pending, variant: 'neutral' },
    { label: '处理中', value: stats.processing, variant: 'warning' },
    { label: '已完成', value: stats.completed, variant: 'success' },
    { label: '失败', value: stats.failed, variant: 'danger' },
  ];

  const statDotClass: Record<typeof statCards[number]['variant'], string> = {
    neutral: 'bg-ink-3',
    warning: 'bg-warning',
    success: 'bg-success',
    danger: 'bg-danger',
  };

  return (
    <div className="p-lg">
      <ToastContainer />

      <div className="flex items-start justify-between gap-md mb-lg flex-wrap">
        <div className="min-w-0">
          <h1 className="text-2xl font-display font-bold text-ink mb-xs">
            MV 转码
          </h1>
          <p className="text-sm text-ink-3">
            将歌曲 MV 转码为 H.264 + AAC 的通用 MP4 格式，兼容所有播放设备
          </p>
        </div>
        <div className="flex items-center gap-sm p-sm rounded-lg border border-border bg-paper flex-wrap">
          {ffmpegOk === false && (
            <div
              className="inline-flex items-center gap-1.5 text-xs text-danger px-2 py-1 rounded-md bg-paper-2 border border-danger"
              title="系统未检测到 ffmpeg，转码任务将无法执行"
            >
              <AlertCircle className="w-3.5 h-3.5 shrink-0" />
              <span>ffmpeg 不可用</span>
            </div>
          )}
          <div className="flex items-center gap-xs">
            <label htmlFor="trigger-profile" className="text-xs font-medium text-ink-3 whitespace-nowrap">
              触发画质预设
            </label>
            <select
              id="trigger-profile"
              value={triggerProfile}
              onChange={(e) => setTriggerProfile(e.target.value)}
              className={[
                'rounded-md border border-border bg-paper-2 text-ink text-sm',
                'px-2 py-1.5 focus-visible:outline-none focus-visible:border-accent focus-visible:ring-2',
                'focus-visible:ring-accent',
              ].join(' ')}
            >
              {TRANSCODE_PROFILES.map(m => (
                <option key={m.value} value={m.value}>
                  {m.label}
                </option>
              ))}
            </select>
          </div>
          <Button
            variant="secondary"
            size="sm"
            leftIcon={<Plus className="w-4 h-4" />}
            onClick={() => setShowSongModal(true)}
          >
            选择歌曲
          </Button>
        </div>
      </div>

      {ffmpegOk === false && (
        <div className="mb-md rounded-md border border-danger bg-paper-2 px-md py-sm flex items-start gap-sm text-sm text-danger">
          <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
          <div>
            <p className="font-medium">转码环境未就绪</p>
            <p className="text-ink-3 mt-0.5">
              系统未检测到 ffmpeg，转码任务将无法执行。请在运行环境安装 ffmpeg 并确保其在 PATH 中（Docker 镜像已内置）。
            </p>
          </div>
        </div>
      )}

      <div className="grid grid-cols-2 md:grid-cols-4 gap-sm mb-md">
        {statCards.map(card => (
          <div
            key={card.label}
            className="bg-paper border border-border rounded-lg p-md"
          >
            <div className="flex items-center gap-2 mb-xs">
              <span className={`w-2 h-2 rounded-full ${statDotClass[card.variant]}`} />
              <span className="text-sm text-ink-3">{card.label}</span>
            </div>
            <div className="text-2xl font-display font-bold text-ink font-mono">
              {card.value}
            </div>
          </div>
        ))}
      </div>

      <div className="bg-paper border border-border rounded-lg overflow-hidden">
        <div className="flex items-center justify-between gap-md px-md py-sm border-b border-border flex-wrap">
          <div className="flex items-center gap-xs flex-wrap">
            {filterTabs.map(tab => {
              const active = statusFilter === tab.value;
              return (
                <button
                  key={tab.value}
                  onClick={() => setStatusFilter(tab.value)}
                  className={[
                    'inline-flex items-center px-sm py-1.5 rounded-md text-sm font-medium',
                    'border transition-colors',
                    'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent',
                    active
                      ? 'border-accent bg-accent text-paper'
                      : 'border-border bg-paper text-ink-2 hover:bg-paper-2 hover:text-ink',
                  ].join(' ')}
                >
                  {tab.label}
                </button>
              );
            })}
          </div>
          {hasProcessing && (
            <div className="flex items-center gap-1.5 text-xs text-warning">
              <Loader2 className="w-3.5 h-3.5 animate-spin" />
              自动刷新中
            </div>
          )}
        </div>

        {selectedIds.size > 0 && (
          <div className="flex items-center gap-sm px-md py-sm bg-accent-soft border-b border-border flex-wrap">
            <span className="text-sm text-accent font-medium">
              已选 {selectedIds.size} 项
            </span>
            <div className="flex items-center gap-xs">
            <Button
              size="sm"
              variant="ghost"
              leftIcon={<RefreshCw className="w-3.5 h-3.5" />}
              onClick={handleBatchRetry}
              loading={batchRetrying}
            >
              批量重试
            </Button>
              <Button
                size="sm"
                variant="ghost"
                leftIcon={<StopCircle className="w-3.5 h-3.5" />}
                onClick={handleBatchStop}
              >
                批量停止
              </Button>
              <Button
                size="sm"
                variant="danger"
                leftIcon={<Trash2 className="w-3.5 h-3.5" />}
                onClick={handleBatchDelete}
              >
                批量删除
              </Button>
            </div>
            <Button
              size="sm"
              variant="ghost"
              onClick={() => setSelectedIds(new Set())}
              className="ml-auto"
            >
              取消选择
            </Button>
          </div>
        )}

        {loading ? (
          <Loading />
        ) : tasks.length === 0 ? (
          <EmptyState
            icon={<Film className="w-8 h-8" />}
            title="暂无转码任务"
            description="提交歌曲 MV 转码请求后，任务会显示在这里"
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-paper-2 text-ink-3">
                <tr>
                  <th className="w-10 px-md py-sm">
                    <button
                      onClick={toggleSelectAll}
                      className="inline-flex items-center justify-center w-4 h-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent rounded-sm"
                      aria-label={allSelected ? '取消全选' : '全选'}
                    >
                      {allSelected ? (
                        <CheckSquare className="w-4 h-4 text-accent" />
                      ) : selectedIds.size > 0 ? (
                        <Square className="w-4 h-4 text-accent fill-accent/30" />
                      ) : (
                        <Square className="w-4 h-4 text-ink-3" />
                      )}
                    </button>
                  </th>
                  <th className="text-left font-medium px-md py-sm whitespace-nowrap">歌曲</th>
                  <th className="text-left font-medium px-md py-sm whitespace-nowrap">状态</th>
                  <th className="text-left font-medium px-md py-sm whitespace-nowrap min-w-[180px]">进度</th>
                  <th className="text-left font-medium px-md py-sm whitespace-nowrap">画质</th>
                  <th className="text-left font-medium px-md py-sm whitespace-nowrap">创建时间</th>
                  <th className="text-right font-medium px-md py-sm whitespace-nowrap">操作</th>
                </tr>
              </thead>
              <tbody>
                {tasks.map(task => {
                  const status = isKnownStatus(task.status) ? task.status : 'pending';
                  const isLoading = actionLoadingId === task.id;
                  const song = (task as TranscodeTask & {
                    song?: { title?: string; artistName?: string; transcodeStatus?: string | null };
                  }).song;
                  const progress = Math.max(0, Math.min(100, Math.round(task.progress ?? 0)));
                  const isSelected = selectedIds.has(task.id);

                  return (
                    <tr
                      key={task.id}
                      className={[
                        'border-t border-border transition-colors',
                        isSelected ? 'bg-accent-soft/30' : 'hover:bg-paper-2',
                      ].join(' ')}
                    >
                      <td className="px-md py-sm">
                        <button
                          onClick={() => toggleSelect(task.id)}
                          className="inline-flex items-center justify-center w-4 h-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent rounded-sm"
                          aria-label={isSelected ? '取消选择' : '选择'}
                        >
                          {isSelected ? (
                            <CheckSquare className="w-4 h-4 text-accent" />
                          ) : (
                            <Square className="w-4 h-4 text-ink-3" />
                          )}
                        </button>
                      </td>
                      <td className="px-md py-sm text-ink">
                        <div className="flex items-center gap-sm">
                          <Film className="w-4 h-4 text-ink-3 shrink-0" />
                          <div className="min-w-0">
                            <div className="font-medium truncate">
                              {song?.title || `歌曲 #${task.songId}`}
                            </div>
                            {song?.artistName && (
                              <div className="text-xs text-ink-3 truncate">
                                {song.artistName}
                              </div>
                            )}
                            {task.error && status === 'failed' && (
                              <div className="text-xs truncate flex items-center gap-1 mt-0.5">
                                <AlertCircle className="w-3 h-3 shrink-0 text-danger" />
                                <span className="text-danger truncate">{task.error}</span>
                              </div>
                            )}
                          </div>
                        </div>
                      </td>
                      <td className="px-md py-sm">
                        <Badge variant={statusVariantMap[status]} dot>
                          {statusLabel[status]}
                        </Badge>
                      </td>
                      <td className="px-md py-sm">
                        <div className="flex items-center gap-sm">
                          <div
                            className="flex-1 h-1.5 bg-paper-3 rounded-full overflow-hidden"
                            role="progressbar"
                            aria-valuenow={progress}
                            aria-valuemin={0}
                            aria-valuemax={100}
                          >
                            <div
                              className="h-full bg-accent transition-[width] duration-300 ease-out"
                              style={{ width: `${progress}%` }}
                            />
                          </div>
                          <span className="font-mono text-xs text-ink-2 w-10 text-right">
                            {progress}%
                          </span>
                        </div>
                        {task.stage && (
                          <div className="text-xs text-ink-3 mt-1 truncate">
                            {stageLabel(task.stage)}
                          </div>
                        )}
                      </td>
                      <td className="px-md py-sm text-ink-2 font-mono text-xs">
                        {transcodeProfileLabel(task.profile)}
                      </td>
                      <td className="px-md py-sm text-ink-3 text-xs">
                        {formatTime(task.createdAt)}
                      </td>
                      <td className="px-md py-sm">
                        <div className="flex items-center justify-end gap-xs flex-wrap">
                          {status === 'completed' && (
                            <>
                              <Button
                                size="sm"
                                variant="secondary"
                                leftIcon={<Play className="w-3.5 h-3.5" />}
                                onClick={() => openPreview(task)}
                              >
                                预览
                              </Button>
                              <Button
                                size="sm"
                                variant="ghost"
                                leftIcon={
                                  isLoading ? (
                                    <Loader2 className="w-3.5 h-3.5 animate-spin" />
                                  ) : (
                                    <RefreshCw className="w-3.5 h-3.5" />
                                  )
                                }
                                onClick={() => handleReTranscode(task)}
                                disabled={isLoading}
                              >
                                重新转码
                              </Button>
                            </>
                          )}
                          {status === 'processing' && (
                            <Button
                              size="sm"
                              variant="ghost"
                              leftIcon={
                                isLoading ? (
                                  <Loader2 className="w-3.5 h-3.5 animate-spin" />
                                ) : (
                                  <StopCircle className="w-3.5 h-3.5" />
                                )
                              }
                              onClick={() => handleStop(task)}
                              disabled={isLoading}
                            >
                              停止
                            </Button>
                          )}
                          {(status === 'failed' || status === 'pending') && (
                            <Button
                              size="sm"
                              variant="ghost"
                              leftIcon={
                                isLoading ? (
                                  <Loader2 className="w-3.5 h-3.5 animate-spin" />
                                ) : (
                                  <RefreshCw className="w-3.5 h-3.5" />
                                )
                              }
                              onClick={() => handleRetry(task)}
                              disabled={isLoading}
                            >
                              重试
                            </Button>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}

        {total > 0 && (
          <div className="border-t border-border">
            <div className="px-md pt-sm text-xs text-ink-3">共 {total} 条任务</div>
            <Pagination
              currentPage={page}
              totalPages={totalPages}
              onPageChange={setPage}
              state={loading ? 'loading' : 'default'}
              pageSize={pageSize}
              onPageSizeChange={(s) => {
                setPageSize(s);
                setPage(1);
              }}
            />
          </div>
        )}
      </div>

      <Modal
        isOpen={showSongModal}
        onClose={() => { setShowSongModal(false); setSongSearch(''); }}
        title="选择歌曲"
      >
        <div className="space-y-md" style={{ minHeight: '400px' }}>
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-ink-3" />
            <input
              type="text"
              value={songSearch}
              onChange={e => setSongSearch(e.target.value)}
              placeholder="搜索歌曲名称..."
              className={[
                'w-full rounded-md border border-border bg-paper text-ink text-sm',
                'pl-9 pr-3 py-2 placeholder:text-ink-3',
                'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent',
              ].join(' ')}
              autoFocus
            />
            {songSearch && (
              <button
                onClick={() => setSongSearch('')}
                className="absolute right-2 top-1/2 -translate-y-1/2 text-ink-3 hover:text-ink p-1 rounded-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent transition-colors"
                aria-label="清除搜索"
              >
                <X className="w-3.5 h-3.5" />
              </button>
            )}
          </div>

          <p className="text-xs text-ink-3">
            仅视频歌曲（MV）可转码；音频歌曲在列表中标记为「音频」，点击不触发转码。
          </p>

          {songLoading ? (
            <Loading />
          ) : songResults.length === 0 ? (
            <div className="py-lg text-center text-ink-3 text-sm">
              {songSearch ? '未找到匹配的歌曲' : '暂无歌曲'}
            </div>
          ) : (
            <div className="space-y-xs max-h-80 overflow-y-auto">
              {songResults.map(song => {
                const isVideo = song.fileType === 'video';
                const disabled = !isVideo || song.transcodeStatus === 'processing' || song.transcodeStatus === 'pending';
                return (
                  <div
                    key={song.id}
                    className="flex items-center justify-between gap-sm p-sm rounded-md border border-border hover:bg-paper-2 transition-colors"
                  >
                    <div className="flex items-center gap-sm min-w-0">
                      <Film className="w-4 h-4 text-ink-3 shrink-0" />
                      <div className="min-w-0">
                        <div className="flex items-center gap-sm">
                          <span className="text-sm font-medium text-ink truncate">
                            {song.title}
                          </span>
                          {isVideo ? (
                            <Badge variant="success" size="sm">视频</Badge>
                          ) : (
                            <Badge variant="neutral" size="sm">音频</Badge>
                          )}
                          {getSongStatusBadge(song.transcodeStatus)}
                        </div>
                        <div className="text-xs text-ink-3 truncate">
                          {song.artistName || '未知歌手'}
                        </div>
                      </div>
                    </div>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => handleSongSelect(song)}
                      disabled={disabled}
                    >
                      {!isVideo
                        ? '非视频'
                        : song.transcodeStatus === 'completed'
                          ? '重新转码'
                          : song.transcodeStatus === 'processing' || song.transcodeStatus === 'pending'
                            ? '处理中'
                            : '选择'}
                    </Button>
                  </div>
                );
              })}
            </div>
          )}

          {songTotal > 10 && (
            <div className="flex items-center justify-between pt-sm border-t border-border">
              <span className="text-xs text-ink-3">共 {songTotal} 首歌曲</span>
              <div className="flex items-center gap-xs">
                <Button
                  size="sm"
                  variant="ghost"
                  leftIcon={<ChevronLeft className="w-4 h-4" />}
                  disabled={songPage <= 1}
                  onClick={() => setSongPage(p => p - 1)}
                >
                  上一页
                </Button>
                <span className="text-xs text-ink-2 px-sm">
                  {songPage}/{songTotalPages}
                </span>
                <Button
                  size="sm"
                  variant="ghost"
                  rightIcon={<ChevronRight className="w-4 h-4" />}
                  disabled={songPage >= songTotalPages}
                  onClick={() => setSongPage(p => p + 1)}
                >
                  下一页
                </Button>
              </div>
            </div>
          )}
        </div>
      </Modal>

      {preview && (
        <Modal
          isOpen={!!preview}
          onClose={() => setPreview(null)}
          title={`预览 · ${preview.songTitle || `歌曲 #${preview.songId}`}`}
        >
          <div className="space-y-sm">
            <video
              src={`/api/songs/${preview.songId}/video`}
              controls
              className="w-full rounded-md bg-black"
              style={{ maxHeight: '60vh' }}
            >
              您的浏览器不支持视频预览。
            </video>
            <p className="text-xs text-ink-3">
              优先播放转码后的通用 MP4，未转码时回退到原始 MV 文件。
            </p>
          </div>
        </Modal>
      )}

      <Modal
        isOpen={!!confirmDialog}
        onClose={() => setConfirmDialog(null)}
        title={confirmDialog?.title || '确认操作'}
      >
        {confirmDialog && (
          <div className="space-y-md">
            <p className="text-sm text-ink-2">{confirmDialog.message}</p>
            <div className="flex items-center justify-end gap-sm">
              <Button variant="ghost" onClick={() => setConfirmDialog(null)}>
                取消
              </Button>
              <Button
                variant="danger"
                onClick={() => {
                  confirmDialog.onConfirm();
                  setConfirmDialog(null);
                }}
              >
                确认
              </Button>
            </div>
          </div>
        )}
      </Modal>
    </div>
  );
}
