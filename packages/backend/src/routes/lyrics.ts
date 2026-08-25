import { Router, Request, Response } from 'express';
import logger from '../logger';
import { authenticateToken } from '../middleware/jwt';
import { lyricsClient } from '../services/lyrics-client';

const router = Router();

/**
 * GET /api/lyrics/sources - 可用歌词源列表（QQ / 酷狗 / 网易云 / Lrclib）
 */
router.get('/sources', authenticateToken, async (_req: Request, res: Response) => {
  try {
    const sources = await lyricsClient.getSources();
    res.json({ success: true, data: sources });
  } catch (error) {
    logger.error('lyrics sources error:', error);
    res.status(502).json({ success: false, error: '歌词服务不可用' });
  }
});

/**
 * POST /api/lyrics/search - 提交异步歌词候选搜索，立即返回 { search_id, status:'pending' }
 */
router.post('/search', authenticateToken, async (req: Request, res: Response) => {
  try {
    const { keyword, sources } = req.body as { keyword?: string; sources?: string[] };
    if (!keyword || !keyword.trim()) {
      return res.status(400).json({ success: false, error: 'keyword required' });
    }
    const data = await lyricsClient.submitSearch(keyword.trim(), sources);
    res.json({ success: true, data });
  } catch (error) {
    logger.error('lyrics search submit error:', error);
    res.status(502).json({ success: false, error: '歌词服务不可用' });
  }
});

/**
 * GET /api/lyrics/search/:id - 轮询歌词候选结果（pending/done + results）
 */
router.get('/search/:id', authenticateToken, async (req: Request, res: Response) => {
  try {
    const data = await lyricsClient.getSearch(req.params.id);
    res.json({ success: true, data });
  } catch (error) {
    logger.error('lyrics search result error:', error);
    res.status(502).json({ success: false, error: '歌词服务不可用' });
  }
});

/**
 * GET /api/lyrics/preview/:id/:source/:index - 预览某候选的 LRC 文本
 * （落盘前的最后一次确认数据源；真正写盘由前端调用 PUT /api/songs/:id/lyrics 完成）
 */
router.get(
  '/preview/:id/:source/:index',
  authenticateToken,
  async (req: Request, res: Response) => {
    try {
      const id = req.params.id;
      const source = req.params.source;
      const index = parseInt(req.params.index);
      if (!Number.isInteger(index) || index < 0) {
        return res.status(400).json({ success: false, error: 'invalid index' });
      }
      const data = await lyricsClient.getPreview(id, source, index);
      res.json({ success: true, data });
    } catch (error) {
      logger.error('lyrics preview error:', error);
      res.status(502).json({ success: false, error: '歌词服务不可用' });
    }
  },
);

export default router;
