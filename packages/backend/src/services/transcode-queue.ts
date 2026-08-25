import { EventEmitter } from 'events';
import path from 'path';
import fs from 'fs';
import { spawn, type ChildProcess } from 'child_process';
import logger from '../logger';
import { db, schema } from '../db';
import { eq, and } from 'drizzle-orm';
import { config } from '../config';
import {
  getTranscodeConcurrency,
  getTranscodeProfile,
} from './settings-service';

const DEFAULT_CONCURRENCY = 1;
const MAX_RETRIES = 3;
const RETRY_BASE_DELAY_MS = 1000;
const DEFAULT_PROFILE = 'standard';

/**
 * 转码画质预设：分辨率 + 视频码率 + 音频码率。
 * 目标编码固定为 H.264 (libx264, yuv420p) + AAC，封装 MP4 并加 faststart，
 * 以兼容 TV WebView / 手机 / 浏览器等所有设备。
 */
export const TRANSCODE_PROFILES: Record<
  string,
  { resolution: string; videoBitrate: string; audioBitrate: string; label: string }
> = {
  compatible: {
    resolution: '854x480',
    videoBitrate: '1200k',
    audioBitrate: '128k',
    label: '兼容优先（480p）',
  },
  standard: {
    resolution: '1280x720',
    videoBitrate: '2500k',
    audioBitrate: '192k',
    label: '标准（720p）',
  },
  high: {
    resolution: '1920x1080',
    videoBitrate: '5000k',
    audioBitrate: '256k',
    label: '高清（1080p）',
  },
};

// 统一基于项目根目录解析（本地=仓库根 data/transcoded，Docker=/app/data/transcoded）
const DEFAULT_OUTPUT_DIR = config.transcodeOutputDir;

if (!fs.existsSync(DEFAULT_OUTPUT_DIR)) {
  fs.mkdirSync(DEFAULT_OUTPUT_DIR, { recursive: true });
}

function resolveStoredPath(p: string): string {
  return path.isAbsolute(p) ? p : path.resolve(config.projectRoot, p);
}

export interface QueueItem {
  taskId: number;
  songId: number;
  profile: string;
  retryCount: number;
  child?: ChildProcess;
  pollStartedAt?: number;
  // 重新转码场景：任务开始前歌曲已有旧转码产物，新任务成功后才替换，失败则回滚旧版
  hadPreviousOutput?: boolean;
  previousTranscodedPath?: string | null;
}

export type TranscodeEventType = 'started' | 'progress' | 'completed' | 'failed';

export interface TranscodeEvent {
  type: TranscodeEventType;
  taskId: number;
  songId: number;
  songTitle: string;
  progress?: number;
  stage?: string;
  transcodedPath?: string;
  error?: string;
  retryCount?: number;
  maxRetries?: number;
}

/** 探测 ffmpeg 是否可用；成功时缓存解析到的可执行路径，失败不缓存（下次重试） */
let ffmpegExecutable: string | null = null;

async function resolveFfmpegPath(): Promise<string | null> {
  const isWin = process.platform === 'win32';
  // 显式指定的 FFMPEG_PATH 优先（.env 约定：完整路径或包含 ffmpeg 的目录）
  const envPath = process.env.FFMPEG_PATH?.trim();
  if (envPath && fs.existsSync(envPath)) {
    const stat = fs.statSync(envPath);
    if (stat.isFile()) {
      return envPath;
    }
    if (stat.isDirectory()) {
      const candidate = path.join(envPath, isWin ? 'ffmpeg.exe' : 'ffmpeg');
      if (fs.existsSync(candidate)) return candidate;
    }
  }
  // Windows 下用 where（System32 自带，必定可用）解析完整路径，
  // 支持 .exe/.cmd/.bat 等 PATHEXT 形式；Unix 下用 which。
  const finder = isWin ? 'where' : 'which';
  return new Promise<string | null>((resolve) => {
    let settled = false;
    const finish = (v: string | null) => {
      if (settled) return;
      settled = true;
      resolve(v);
    };
    try {
      const cp = spawn(finder, ['ffmpeg'], { windowsHide: true });
      let out = '';
      cp.stdout?.on('data', (chunk: Buffer) => { out += chunk.toString(); });
      cp.on('error', () => finish(null));
      cp.on('close', (code) => {
        const first = out.split('\n').map(s => s.trim()).filter(Boolean)[0];
        finish(code === 0 && first ? first : null);
      });
      setTimeout(() => finish(null), 5000);
    } catch {
      finish(null);
    }
  });
}

export async function isFfmpegAvailable(): Promise<boolean> {
  if (ffmpegExecutable !== null) return true;
  const resolved = await resolveFfmpegPath();
  if (resolved) {
    ffmpegExecutable = resolved;
    logger.info({ executable: resolved }, 'ffmpeg 探测成功');
    return true;
  }
  // 不缓存失败结果：用户可能刚装好 ffmpeg，页面刷新后应重新探测
  return false;
}

/** 获取已解析的 ffmpeg 可执行路径（未探测到时回落到裸命令名） */
function getFfmpegExecutable(): string {
  return ffmpegExecutable ?? 'ffmpeg';
}

/**
 * 构建 ffmpeg 命令行参数。
 * 保持原始宽高比（letterbox/pillarbox 补齐到目标分辨率），确保 yuv420p 与
 * faststart，最大化设备兼容性。
 */
function buildFfmpegArgs(
  input: string,
  output: string,
  profile: string,
): string[] {
  const p = TRANSCODE_PROFILES[profile] || TRANSCODE_PROFILES[DEFAULT_PROFILE];
  const [w, h] = p.resolution.split('x').map((n) => parseInt(n, 10));
  // scale 等比缩放后居中补齐到目标分辨率，避免拉伸变形
  const vf = `scale=${w}:${h}:force_original_aspect_ratio=decrease,pad=${w}:${h}:(ow-iw)/2:(oh-ih)/2,setsar=1`;
  return [
    '-y',
    '-i',
    input,
    '-vf',
    vf,
    '-c:v',
    'libx264',
    '-profile:v',
    'main',
    '-level',
    '4.0',
    '-preset',
    'veryfast',
    '-pix_fmt',
    'yuv420p',
    '-b:v',
    p.videoBitrate,
    '-maxrate',
    p.videoBitrate,
    '-bufsize',
    `${parseInt(p.videoBitrate, 10) * 2}k`,
    '-c:a',
    'aac',
    '-b:a',
    p.audioBitrate,
    '-ac',
    '2',
    '-movflags',
    '+faststart',
    '-f',
    'mp4',
    // 机器可读进度输出到 stdout，便于解析百分比
    '-nostats',
    '-progress',
    'pipe:1',
    output,
  ];
}

class TranscodeQueue extends EventEmitter {
  private queue: QueueItem[] = [];
  private processing: Map<number, QueueItem> = new Map();
  private concurrency: number;

  constructor(concurrency: number = DEFAULT_CONCURRENCY) {
    super();
    const env = parseInt(process.env.TRANSCODE_CONCURRENCY ?? '', 10);
    this.concurrency = Number.isFinite(env) && env > 0 ? env : concurrency;
    this.updateConcurrency().catch(() => {});
  }

  async updateConcurrency(): Promise<void> {
    this.concurrency = await getTranscodeConcurrency();
    logger.info(`Transcode concurrency set to ${this.concurrency}`);
    this.processNext();
  }

  /**
   * 任务入队：创建数据库记录，加入内存队列，触发处理
   */
  async enqueue(songId: number, profile?: string): Promise<number> {
    const song = db
      .select()
      .from(schema.songs)
      .where(eq(schema.songs.id, songId))
      .get();

    if (!song) {
      throw new Error(`Song ${songId} not found`);
    }
    if (!song.filePath) {
      throw new Error(`Song ${songId} has no file_path`);
    }
    if (song.fileType !== 'video') {
      throw new Error(`Song ${songId} is not a video (fileType=${song.fileType})`);
    }

    const resolvedProfile = profile || (await getTranscodeProfile());

    const hadPreviousOutput = song.transcodeStatus === 'completed' && Boolean(song.transcodedPath);
    const previousTranscodedPath = hadPreviousOutput ? song.transcodedPath : null;

    const result = db
      .insert(schema.transcodeTasks)
      .values({
        songId,
        status: 'pending',
        profile: resolvedProfile,
        progress: 0,
        createdAt: new Date(),
      })
      .returning()
      .get();

    const taskId = result.id;

    db.update(schema.songs)
      .set({
        transcodeStatus: 'pending',
        transcodeProfile: resolvedProfile,
        transcodeStartedAt: null,
        transcodeCompletedAt: null,
        transcodeError: null,
      })
      .where(eq(schema.songs.id, songId))
      .run();

    this.queue.push({
      taskId,
      songId,
      profile: resolvedProfile,
      retryCount: 0,
      hadPreviousOutput,
      previousTranscodedPath,
    });

    logger.info(
      `Transcode task ${taskId} enqueued for song ${songId} (${song.title}) profile=${resolvedProfile}`,
    );

    this.processNext();
    return taskId;
  }

  retry(taskId: number): void {
    const task = db
      .select()
      .from(schema.transcodeTasks)
      .where(eq(schema.transcodeTasks.id, taskId))
      .get();

    if (!task) {
      throw new Error(`Task ${taskId} not found`);
    }
    if (task.status !== 'failed' && task.status !== 'completed') {
      throw new Error(
        `Task ${taskId} is not in failed or completed state (current: ${task.status})`,
      );
    }
    if (!task.songId) {
      throw new Error(`Task ${taskId} has no song_id`);
    }

    const song = db
      .select()
      .from(schema.songs)
      .where(eq(schema.songs.id, task.songId))
      .get();
    if (
      song &&
      (song.transcodeStatus === 'processing' || song.transcodeStatus === 'pending')
    ) {
      throw new Error(`Song ${task.songId} already has an in-progress transcode task`);
    }

    const hadPreviousOutput =
      song?.transcodeStatus === 'completed' && Boolean(song.transcodedPath);
    const previousTranscodedPath = hadPreviousOutput ? song?.transcodedPath : null;

    db.update(schema.transcodeTasks)
      .set({
        status: 'pending',
        progress: 0,
        stage: null,
        error: null,
        retryCount: 0,
        startedAt: null,
        completedAt: null,
      })
      .where(eq(schema.transcodeTasks.id, taskId))
      .run();

    db.update(schema.songs)
      .set({
        transcodeStatus: 'pending',
        transcodeCompletedAt: null,
        transcodeError: null,
      })
      .where(eq(schema.songs.id, task.songId))
      .run();

    this.queue.push({
      taskId,
      songId: task.songId,
      profile: task.profile || DEFAULT_PROFILE,
      retryCount: 0,
      hadPreviousOutput,
      previousTranscodedPath,
    });

    logger.info(`Transcode task ${taskId} retried for song ${task.songId}`);
    this.processNext();
  }

  async forceStop(taskId: number): Promise<boolean> {
    const task = db
      .select()
      .from(schema.transcodeTasks)
      .where(eq(schema.transcodeTasks.id, taskId))
      .get();

    if (!task) throw new Error(`Task ${taskId} not found`);
    if (task.status !== 'processing')
      throw new Error(`Task ${taskId} is not processing (status: ${task.status})`);

    const item = this.processing.get(taskId);
    if (item) {
      this.clearChild(item);
      this.processing.delete(taskId);
    }

    db.update(schema.transcodeTasks)
      .set({ status: 'failed', error: '用户强制停止', completedAt: new Date() })
      .where(eq(schema.transcodeTasks.id, taskId))
      .run();

    if (task.songId) {
      const tmpDir = path.join(DEFAULT_OUTPUT_DIR, `.tmp_${taskId}`);
      try {
        fs.rmSync(tmpDir, { recursive: true, force: true });
      } catch (err) {
        logger.warn({ err, taskId, tmpDir }, 'Failed to remove temp output dir');
      }

      db.update(schema.songs)
        .set(
          item?.hadPreviousOutput
            ? {
                transcodeStatus: 'completed',
                transcodeCompletedAt: item?.previousTranscodedPath ? new Date() : null,
                transcodeError: '用户强制停止',
              }
            : { transcodeStatus: 'failed', transcodeError: '用户强制停止' },
        )
        .where(eq(schema.songs.id, task.songId))
        .run();
    }

    this.emit('failed', {
      type: 'failed',
      taskId,
      songId: task.songId,
      songTitle: 'Unknown',
      error: '用户强制停止',
    } as TranscodeEvent);

    logger.info({ taskId }, 'Transcode task force-stopped');
    setTimeout(() => this.processNext(), 100);
    return true;
  }

  private processNext(): void {
    while (this.processing.size < this.concurrency) {
      const item = this.queue.shift();
      if (!item) break;

      this.processing.set(item.taskId, item);
      this.processTask(item).catch((err) => {
        logger.error(`Unexpected error processing transcode task ${item.taskId}:`, err);
        this.processing.delete(item.taskId);
        this.processNext();
      });
    }
  }

  private clearChild(item: QueueItem): void {
    if (item.child) {
      try {
        item.child.kill('SIGKILL');
      } catch {
        // ignore
      }
      item.child = undefined;
    }
  }

  private async processTask(item: QueueItem): Promise<void> {
    const { taskId, songId, profile } = item;

    const song = db
      .select()
      .from(schema.songs)
      .where(eq(schema.songs.id, songId))
      .get();
    const songTitle = song?.title ?? 'Unknown';

    try {
      if (!(await isFfmpegAvailable())) {
        throw new Error('ffmpeg 不可用：请确认系统已安装 ffmpeg 并在 PATH 中');
      }

      db.update(schema.transcodeTasks)
        .set({ status: 'processing', startedAt: new Date(), error: null })
        .where(eq(schema.transcodeTasks.id, taskId))
        .run();

      db.update(schema.songs)
        .set({
          transcodeStatus: 'processing',
          transcodeStartedAt: new Date(),
          transcodeError: null,
        })
        .where(eq(schema.songs.id, songId))
        .run();

      this.emit('started', {
        type: 'started',
        taskId,
        songId,
        songTitle,
      } as TranscodeEvent);

      const inputPath = resolveStoredPath(song!.filePath!);
      const tmpDir = path.join(DEFAULT_OUTPUT_DIR, `.tmp_${taskId}`);
      try {
        fs.rmSync(tmpDir, { recursive: true, force: true });
      } catch {
        // ignore
      }
      fs.mkdirSync(tmpDir, { recursive: true });
      const outputPath = path.join(tmpDir, 'transcoded.mp4');

      await this.runFfmpeg(item, inputPath, outputPath, songTitle);
    } catch (error) {
      await this.handleTaskError(item, error, songTitle);
    }
  }

  /**
   * 运行 ffmpeg 并通过 -progress pipe:1 解析进度；结束时按退出码判断成败。
   */
  private runFfmpeg(
    item: QueueItem,
    inputPath: string,
    outputPath: string,
    songTitle: string,
  ): Promise<void> {
    const { taskId, songId, profile } = item;

    return new Promise<void>((resolve, reject) => {
      const args = buildFfmpegArgs(inputPath, outputPath, profile);
      let cp: ChildProcess;
      try {
        cp = spawn(getFfmpegExecutable(), args, { stdio: ['ignore', 'pipe', 'pipe'] });
      } catch (err) {
        reject(err);
        return;
      }
      item.child = cp;

      let durationMs = 0;
      let outTimeMs = 0;
      let lastReported = 0;

      const reportProgress = (stage: string) => {
        const pct =
          durationMs > 0 ? Math.min(100, (outTimeMs / durationMs) * 100) : 0;
        // 限制上报频率（每 2% 或阶段变化），降低 WS 广播压力
        if (pct - lastReported >= 2 || stage === 'done') {
          lastReported = pct;
          db.update(schema.transcodeTasks)
            .set({ progress: pct, stage: 'transcoding' })
            .where(eq(schema.transcodeTasks.id, taskId))
            .run();
          this.emit('progress', {
            type: 'progress',
            taskId,
            songId,
            progress: pct,
            stage: 'transcoding',
          } as TranscodeEvent);
        }
      };

      cp.stdout?.on('data', (chunk: Buffer) => {
        const text = chunk.toString();
        for (const line of text.split('\n')) {
          const sep = line.indexOf('=');
          if (sep < 0) continue;
          const key = line.slice(0, sep).trim();
          const val = line.slice(sep + 1).trim();
          if (key === 'duration_ms') durationMs = parseInt(val, 10) || durationMs;
          else if (key === 'out_time_ms') {
            outTimeMs = parseInt(val, 10) || outTimeMs;
            reportProgress('transcoding');
          } else if (key === 'progress' && val === 'end') {
            reportProgress('done');
          }
        }
      });

      let stderrTail = '';
      cp.stderr?.on('data', (chunk: Buffer) => {
        stderrTail = chunk.toString().slice(-2000);
      });

      cp.on('error', (err) => {
        this.clearChild(item);
        this.processing.delete(taskId);
        reject(err);
      });

      cp.on('close', (code) => {
        this.clearChild(item);
        this.processing.delete(taskId);
        if (code === 0) {
          this.handleTaskCompleted(item, outputPath, songTitle)
            .then(() => {
              this.processNext();
              resolve();
            })
            .catch((err) => reject(err));
        } else {
          const msg = `ffmpeg 退出码 ${code}`;
          const err = new Error(stderrTail ? `${msg}\n${stderrTail}` : msg);
          reject(err);
        }
      });
    });
  }

  private async handleTaskCompleted(
    item: QueueItem,
    tmpOutputPath: string,
    songTitle: string,
  ): Promise<void> {
    const { taskId, songId } = item;
    const finalDir = path.join(DEFAULT_OUTPUT_DIR, `song_${songId}`);
    const finalPath = path.join(finalDir, 'transcoded.mp4');

    const song = db
      .select()
      .from(schema.songs)
      .where(eq(schema.songs.id, songId))
      .get();

    // 1. 移除旧产物（重新转码成功时直接删除旧版）
    if (song && song.transcodedPath) {
      const oldResolved = resolveStoredPath(song.transcodedPath);
      try {
        if (fs.existsSync(oldResolved)) fs.rmSync(oldResolved, { force: true });
      } catch (err) {
        logger.warn({ err, oldResolved }, 'Failed to remove old transcoded file');
      }
    }

    // 2. 新产物移动到正式位置（相对路径入库，保持与音频流路由一致）
    fs.mkdirSync(finalDir, { recursive: true });
    const resolvedTmp = resolveStoredPath(tmpOutputPath);
    if (!fs.existsSync(resolvedTmp)) {
      throw new Error('转码产物不存在');
    }
    fs.renameSync(resolvedTmp, finalPath);

    // 3. 清理临时目录
    const tmpDir = path.join(DEFAULT_OUTPUT_DIR, `.tmp_${taskId}`);
    try {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    } catch (err) {
      logger.warn({ err, taskId, tmpDir }, 'Failed to remove temp output dir');
    }

    const relativePath = path.relative(config.projectRoot, finalPath).replace(/\\/g, '/');

    db.update(schema.transcodeTasks)
      .set({
        status: 'completed',
        progress: 100,
        stage: 'done',
        error: null,
        completedAt: new Date(),
      })
      .where(eq(schema.transcodeTasks.id, taskId))
      .run();

    db.update(schema.songs)
      .set({
        transcodeStatus: 'completed',
        transcodedPath: relativePath,
        transcodeCompletedAt: new Date(),
        transcodeError: null,
      })
      .where(eq(schema.songs.id, songId))
      .run();

    this.emit('completed', {
      type: 'completed',
      taskId,
      songId,
      songTitle,
      transcodedPath: relativePath,
    } as TranscodeEvent);

    logger.info(`Transcode task ${taskId} completed for song ${songId}`);
  }

  private async handleTaskError(
    item: QueueItem,
    error: unknown,
    songTitle: string,
  ): Promise<void> {
    const { taskId, songId } = item;
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';

    this.processing.delete(taskId);
    item.retryCount++;

    if (item.retryCount < MAX_RETRIES) {
      const delay = RETRY_BASE_DELAY_MS * Math.pow(2, item.retryCount - 1);
      logger.warn(
        `Transcode task ${taskId} failed (attempt ${item.retryCount}/${MAX_RETRIES}): ${errorMessage}, retrying in ${delay}ms`,
      );

      db.update(schema.transcodeTasks)
        .set({ status: 'pending', error: errorMessage, retryCount: item.retryCount })
        .where(eq(schema.transcodeTasks.id, taskId))
        .run();

      db.update(schema.songs)
        .set({ transcodeStatus: 'pending', transcodeError: errorMessage })
        .where(eq(schema.songs.id, songId))
        .run();

      setTimeout(() => {
        this.queue.push(item);
        this.processNext();
      }, delay);
    } else {
      db.update(schema.transcodeTasks)
        .set({ status: 'failed', error: errorMessage, completedAt: new Date() })
        .where(eq(schema.transcodeTasks.id, taskId))
        .run();

      const tmpDir = path.join(DEFAULT_OUTPUT_DIR, `.tmp_${taskId}`);
      try {
        fs.rmSync(tmpDir, { recursive: true, force: true });
      } catch (err) {
        logger.warn({ err, taskId, tmpDir }, 'Failed to remove temp output dir');
      }

      db.update(schema.songs)
        .set(
          item.hadPreviousOutput
            ? {
                transcodeStatus: 'completed',
                transcodeCompletedAt: item.previousTranscodedPath ? new Date() : null,
                transcodeError: errorMessage,
              }
            : { transcodeStatus: 'failed', transcodeError: errorMessage },
        )
        .where(eq(schema.songs.id, songId))
        .run();

      this.emit('failed', {
        type: 'failed',
        taskId,
        songId,
        songTitle,
        error: errorMessage,
        retryCount: item.retryCount,
        maxRetries: MAX_RETRIES,
      } as TranscodeEvent);

      logger.error(`Transcode task ${taskId} failed permanently: ${errorMessage}`);
    }

    this.processNext();
  }

  getQueueStatus(): {
    pending: number;
    processing: number;
    completed: number;
    failed: number;
  } {
    const count = (status: string) =>
      db
        .select()
        .from(schema.transcodeTasks)
        .where(eq(schema.transcodeTasks.status, status))
        .all().length;

    return {
      pending: this.queue.length,
      processing: this.processing.size,
      completed: count('completed'),
      failed: count('failed'),
    };
  }

  /**
   * 应用重启时恢复未完成任务（处理中任务无法继续轮询，重置为 pending 重新执行）。
   */
  recoverPendingTasks(): void {
    const processing = db
      .select()
      .from(schema.transcodeTasks)
      .where(eq(schema.transcodeTasks.status, 'processing'))
      .all();

    const pending = db
      .select()
      .from(schema.transcodeTasks)
      .where(eq(schema.transcodeTasks.status, 'pending'))
      .all();

    if (processing.length > 0) {
      db.update(schema.transcodeTasks)
        .set({ status: 'pending' })
        .where(eq(schema.transcodeTasks.status, 'processing'))
        .run();

      db.update(schema.songs)
        .set({ transcodeStatus: 'pending' })
        .where(eq(schema.songs.transcodeStatus, 'processing'))
        .run();
    }

    const toRecover = [...processing, ...pending];
    for (const task of toRecover) {
      if (!task.songId) continue;
      const song = db
        .select()
        .from(schema.songs)
        .where(eq(schema.songs.id, task.songId))
        .get();
      const hadPreviousOutput = Boolean(song?.transcodedPath);
      this.queue.push({
        taskId: task.id,
        songId: task.songId,
        profile: task.profile || DEFAULT_PROFILE,
        retryCount: task.retryCount ?? 0,
        hadPreviousOutput,
        previousTranscodedPath: song?.transcodedPath ?? null,
      });
    }

    if (toRecover.length > 0) {
      logger.info(`Recovered ${toRecover.length} transcode tasks`);
      this.processNext();
    }
  }
}

export const transcodeQueue = new TranscodeQueue();
