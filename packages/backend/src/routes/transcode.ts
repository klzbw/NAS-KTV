import { Router, Request, Response } from 'express';
import logger from '../logger';
import fs from 'fs';
import path from 'path';
import { authenticateToken } from '../middleware/jwt';
import { db, schema } from '../db';
import { eq, desc, sql } from 'drizzle-orm';
import { transcodeQueue, isFfmpegAvailable, TRANSCODE_PROFILES } from '../services/transcode-queue';
import { config } from '../config';

const router = Router();

/**
 * POST /api/songs/:id/transcode - 触发歌曲 MV 转码
 */
router.post(
  '/songs/:id/transcode',
  authenticateToken,
  async (req: Request, res: Response) => {
    try {
      const songId = parseInt(req.params.id);
      const profile =
        (req.body?.profile as string) || undefined; // 不传则用 settings 默认预设

      if (profile && !TRANSCODE_PROFILES[profile]) {
        return res.status(400).json({
          success: false,
          error: 'Invalid transcode profile',
        });
      }

      const song = db
        .select()
        .from(schema.songs)
        .where(eq(schema.songs.id, songId))
        .get();

      if (!song) {
        return res.status(404).json({ success: false, error: 'Song not found' });
      }
      if (!song.filePath) {
        return res.status(400).json({ success: false, error: 'Song has no file_path' });
      }
      if (song.fileType !== 'video') {
        return res
          .status(400)
          .json({ success: false, error: 'Only video songs can be transcoded' });
      }

      if (
        song.transcodeStatus === 'processing' ||
        song.transcodeStatus === 'pending'
      ) {
        return res.status(409).json({
          success: false,
          error: `Transcode already in progress (status: ${song.transcodeStatus})`,
        });
      }

      const taskId = await transcodeQueue.enqueue(songId, profile);

      res.json({
        success: true,
        data: { taskId, songId, profile, message: 'Transcode task enqueued' },
      });
    } catch (error) {
      logger.error('Error triggering transcode:', error);
      res.status(500).json({
        success: false,
        error:
          error instanceof Error ? error.message : 'Failed to trigger transcode',
      });
    }
  },
);

/**
 * GET /api/transcode/tasks - 转码任务列表（支持分页和状态筛选）
 */
router.get(
  '/transcode/tasks',
  authenticateToken,
  async (req: Request, res: Response) => {
    try {
      const page = parseInt(req.query.page as string) || 1;
      const pageSize = parseInt(req.query.pageSize as string) || 20;
      const status = req.query.status as string | undefined;
      const offset = (page - 1) * pageSize;

      let items: any[];
      if (status) {
        items = db
          .select()
          .from(schema.transcodeTasks)
          .where(eq(schema.transcodeTasks.status, status))
          .orderBy(desc(schema.transcodeTasks.createdAt))
          .limit(pageSize)
          .offset(offset)
          .all();
      } else {
        items = db
          .select()
          .from(schema.transcodeTasks)
          .orderBy(desc(schema.transcodeTasks.createdAt))
          .limit(pageSize)
          .offset(offset)
          .all();
      }

      const itemsWithSong = items.map((task) => {
        const song = task.songId
          ? db
              .select({
                id: schema.songs.id,
                title: schema.songs.title,
                filePath: schema.songs.filePath,
                fileType: schema.songs.fileType,
                transcodeStatus: schema.songs.transcodeStatus,
                transcodedPath: schema.songs.transcodedPath,
              })
              .from(schema.songs)
              .where(eq(schema.songs.id, task.songId))
              .get()
          : null;
        return { ...task, song };
      });

      const totalResult = status
        ? db
            .select({ count: sql<number>`count(*)` })
            .from(schema.transcodeTasks)
            .where(eq(schema.transcodeTasks.status, status))
            .get()
        : db.select({ count: sql<number>`count(*)` }).from(schema.transcodeTasks).get();

      const total = totalResult?.count ?? 0;

      res.json({
        success: true,
        data: { items: itemsWithSong, total, page, pageSize },
      });
    } catch (error) {
      logger.error('Error getting transcode tasks:', error);
      res
        .status(500)
        .json({ success: false, error: 'Failed to get transcode tasks' });
    }
  },
);

/**
 * GET /api/transcode/tasks/:id - 任务详情
 */
router.get(
  '/transcode/tasks/:id',
  authenticateToken,
  async (req: Request, res: Response) => {
    try {
      const taskId = parseInt(req.params.id);
      const task = db
        .select()
        .from(schema.transcodeTasks)
        .where(eq(schema.transcodeTasks.id, taskId))
        .get();
      if (!task) {
        return res.status(404).json({ success: false, error: 'Task not found' });
      }
      const song = task.songId
        ? db.select().from(schema.songs).where(eq(schema.songs.id, task.songId)).get()
        : null;
      res.json({ success: true, data: { ...task, song } });
    } catch (error) {
      logger.error('Error getting transcode task:', error);
      res
        .status(500)
        .json({ success: false, error: 'Failed to get transcode task' });
    }
  },
);

router.post(
  '/transcode/tasks/:id/retry',
  authenticateToken,
  async (req: Request, res: Response) => {
    try {
      const taskId = parseInt(req.params.id);
      transcodeQueue.retry(taskId);
      res.json({ success: true, data: { taskId, message: 'Task re-queued' } });
    } catch (error) {
      logger.error('Error retrying transcode task:', error);
      const status =
        error instanceof Error && error.message.includes('not found')
          ? 404
          : error instanceof Error && error.message.includes('not in failed or completed state')
            ? 400
            : 500;
      res.status(status).json({
        success: false,
        error: error instanceof Error ? error.message : 'Failed to retry task',
      });
    }
  },
);

router.post(
  '/transcode/tasks/:id/stop',
  authenticateToken,
  async (req: Request, res: Response) => {
    try {
      const taskId = parseInt(req.params.id);
      await transcodeQueue.forceStop(taskId);
      res.json({ success: true, data: { taskId, message: 'Task force-stopped' } });
    } catch (error) {
      logger.error('Error stopping transcode task:', error);
      const status =
        error instanceof Error && error.message.includes('not found')
          ? 404
          : error instanceof Error && error.message.includes('not processing')
            ? 400
            : 500;
      res.status(status).json({
        success: false,
        error: error instanceof Error ? error.message : 'Failed to stop task',
      });
    }
  },
);

router.post(
  '/transcode/tasks/batch-retry',
  authenticateToken,
  async (req: Request, res: Response) => {
    try {
      const { taskIds } = req.body;
      if (!Array.isArray(taskIds) || taskIds.length === 0) {
        return res.status(400).json({ success: false, error: 'taskIds array is required' });
      }
      let succeeded = 0;
      let skipped = 0;
      for (const id of taskIds) {
        try {
          transcodeQueue.retry(id);
          succeeded++;
        } catch {
          skipped++;
        }
      }
      res.json({ success: true, data: { succeeded, skipped } });
    } catch (error) {
      logger.error('Error batch retrying transcode:', error);
      res.status(500).json({ success: false, error: 'Failed to batch retry' });
    }
  },
);

router.post(
  '/transcode/tasks/batch-delete',
  authenticateToken,
  async (req: Request, res: Response) => {
    try {
      const { taskIds } = req.body;
      if (!Array.isArray(taskIds) || taskIds.length === 0) {
        return res.status(400).json({ success: false, error: 'taskIds array is required' });
      }
      let succeeded = 0;
      let skipped = 0;
      for (const id of taskIds) {
        const task = db
          .select()
          .from(schema.transcodeTasks)
          .where(eq(schema.transcodeTasks.id, id))
          .get();
        if (!task || task.status === 'processing') {
          skipped++;
          continue;
        }
        db.delete(schema.transcodeTasks).where(eq(schema.transcodeTasks.id, id)).run();
        succeeded++;
      }
      res.json({ success: true, data: { succeeded, skipped } });
    } catch (error) {
      logger.error('Error batch deleting transcode:', error);
      res.status(500).json({ success: false, error: 'Failed to batch delete' });
    }
  },
);

router.post(
  '/transcode/tasks/batch-stop',
  authenticateToken,
  async (req: Request, res: Response) => {
    try {
      const { taskIds } = req.body;
      if (!Array.isArray(taskIds) || taskIds.length === 0) {
        return res.status(400).json({ success: false, error: 'taskIds array is required' });
      }
      let succeeded = 0;
      let skipped = 0;
      for (const id of taskIds) {
        try {
          await transcodeQueue.forceStop(id);
          succeeded++;
        } catch {
          skipped++;
        }
      }
      res.json({ success: true, data: { succeeded, skipped } });
    } catch (error) {
      logger.error('Error batch stopping transcode:', error);
      res.status(500).json({ success: false, error: 'Failed to batch stop' });
    }
  },
);

/**
 * GET /api/transcode/queue/status - 队列状态
 */
router.get(
  '/transcode/queue/status',
  authenticateToken,
  async (req: Request, res: Response) => {
    try {
      const status = transcodeQueue.getQueueStatus();
      res.json({ success: true, data: status });
    } catch (error) {
      res.status(500).json({ success: false, error: 'Failed to get queue status' });
    }
  },
);

/**
 * GET /api/transcode/ffmpeg - ffmpeg 可用性探测
 */
router.get(
  '/transcode/ffmpeg',
  authenticateToken,
  async (req: Request, res: Response) => {
    try {
      const available = await isFfmpegAvailable();
      res.json({ success: true, data: { available } });
    } catch (error) {
      res.status(500).json({ success: false, error: 'Failed to check ffmpeg' });
    }
  },
);

/**
 * 跨源视频流响应头（与音频流一致，放行跨源以兼容 TV WebView）。
 */
const STREAM_CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Cross-Origin-Resource-Policy': 'cross-origin',
};

/**
 * 视频流辅助函数 - 支持 Range 请求。
 * 优先返回转码后的 MP4，无转码产物时回退原始文件（保证接口始终可用）。
 * 返回 true 表示已处理响应，false 表示无可播放文件。
 */
function streamVideoFile(req: Request, res: Response, song: any): boolean {
  // 优先转码版，其次原片
  const candidates: string[] = [];
  if (song.transcodedPath) candidates.push(song.transcodedPath);
  if (song.filePath && song.fileType === 'video') candidates.push(song.filePath);

  let resolvedPath: string | null = null;
  for (const p of candidates) {
    const r = path.isAbsolute(p) ? p : path.resolve(config.projectRoot, p);
    if (fs.existsSync(r)) {
      resolvedPath = r;
      break;
    }
  }
  if (!resolvedPath) return false;

  let stat: fs.Stats;
  try {
    stat = fs.statSync(resolvedPath);
  } catch {
    return false;
  }
  if (!stat.isFile()) return false;

  const fileSize = stat.size;
  const range = req.headers.range;

  const ext = path.extname(resolvedPath).toLowerCase();
  const mimeMap: Record<string, string> = {
    '.mp4': 'video/mp4',
    '.mkv': 'video/x-matroska',
    '.avi': 'video/x-msvideo',
    '.mov': 'video/quicktime',
    '.webm': 'video/webm',
    '.flv': 'video/x-flv',
    '.wmv': 'video/x-ms-wmv',
  };
  const contentType = mimeMap[ext] || 'video/mp4';

  if (range) {
    const match = /bytes=(\d*)-(\d*)/.exec(range);
    if (!match) {
      res.status(416).json({ success: false, error: 'Invalid range' });
      return true;
    }
    const start = match[1] ? parseInt(match[1], 10) : 0;
    const end = match[2] ? parseInt(match[2], 10) : fileSize - 1;
    if (start >= fileSize || end >= fileSize || start > end) {
      res.status(416).set('Content-Range', `bytes */${fileSize}`).json({ success: false, error: 'Requested range not satisfiable' });
      return true;
    }
    const chunkSize = end - start + 1;
    const stream = fs.createReadStream(resolvedPath, { start, end });
    res.status(206).set({
      'Content-Range': `bytes ${start}-${end}/${fileSize}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': chunkSize.toString(),
      'Content-Type': contentType,
      ...STREAM_CORS_HEADERS,
    });
    stream.pipe(res);
    stream.on('error', (err) => {
      logger.error('Video stream error:', err);
      if (!res.headersSent) res.status(500).json({ success: false, error: 'Stream error' });
    });
    return true;
  }

  res.status(200).set({
    'Content-Length': fileSize.toString(),
    'Content-Type': contentType,
    'Accept-Ranges': 'bytes',
    ...STREAM_CORS_HEADERS,
  });
  const stream = fs.createReadStream(resolvedPath);
  stream.pipe(res);
  stream.on('error', (err) => {
    logger.error('Video stream error:', err);
    if (!res.headersSent) res.status(500).json({ success: false, error: 'Stream error' });
  });
  return true;
}

/**
 * GET /api/songs/:id/video - 统一视频流（转码版优先，原片回退，支持 Range）。
 * 公开接口（与音频流一致），供 TV / 手机端播放 MV 使用。
 */
router.get('/songs/:id/video', async (req: Request, res: Response) => {
  try {
    const songId = parseInt(req.params.id);
    const song = db
      .select()
      .from(schema.songs)
      .where(eq(schema.songs.id, songId))
      .get();
    if (!song) {
      return res.status(404).json({ success: false, error: 'Song not found' });
    }
    const served = streamVideoFile(req, res, song);
    if (!served) {
      return res.status(404).json({ success: false, error: 'No playable video for this song' });
    }
  } catch (error) {
    logger.error('Error streaming video:', error);
    res.status(500).json({ success: false, error: 'Failed to stream video' });
  }
});

export default router;
