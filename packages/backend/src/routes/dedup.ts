import { Router, Request, Response } from 'express';
import { authenticateToken } from '../middleware/jwt';
import {
  runLocalDedup,
  getDedupStatus,
  getDedupTasks,
  getDedupTaskById,
  restoreSong,
} from '../services/dedup-service';

const router = Router();

/**
 * POST /api/dedup/run - 触发本地去重脚本（后台执行，进度通过 /status 轮询）
 */
router.post('/run', authenticateToken, (req: Request, res: Response) => {
  void runLocalDedup().catch((error) => {
    // 异步执行失败已在服务内记录任务状态
  });
  res.json({ success: true, data: getDedupStatus() });
});

/**
 * GET /api/dedup/status - 去重进度与上次结果
 */
router.get('/status', authenticateToken, (req: Request, res: Response) => {
  res.json({ success: true, data: getDedupStatus() });
});

/**
 * GET /api/dedup/tasks - 去重任务记录（分页）
 */
router.get('/tasks', authenticateToken, (req: Request, res: Response) => {
  const page = Math.max(1, Number(req.query.page) || 1);
  const pageSize = Math.min(100, Math.max(1, Number(req.query.pageSize) || 10));
  const offset = (page - 1) * pageSize;
  const data = getDedupTasks({ offset, limit: pageSize });
  res.json({
    success: true,
    data: {
      items: data.items,
      total: data.total,
      page,
      limit: pageSize,
      offset,
    },
  });
});

/**
 * GET /api/dedup/tasks/:id - 单个去重任务（详情弹窗 / 扫描页 URL 跳转，任务可能不在当前分页）
 */
router.get('/tasks/:id', authenticateToken, (req: Request, res: Response) => {
  const id = Number(req.params.id);
  if (!Number.isFinite(id)) {
    return res.status(400).json({ success: false, message: '参数无效' });
  }
  const task = getDedupTaskById(id);
  if (!task) {
    return res.status(404).json({ success: false, message: '任务不存在' });
  }
  res.json({ success: true, data: task });
});

/**
 * POST /api/dedup/restore - 还原被去重删除的歌曲（写入例外防止再次被识别）
 */
router.post('/restore', authenticateToken, async (req: Request, res: Response) => {
  try {
    const taskId = Number(req.body.taskId);
    const removedId = Number(req.body.removedId);
    if (!Number.isFinite(taskId) || !Number.isFinite(removedId)) {
      return res.status(400).json({ success: false, message: '参数无效' });
    }
    const data = await restoreSong(taskId, removedId);
    res.json({ success: true, data });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: error instanceof Error ? error.message : '还原失败',
    });
  }
});

export default router;
