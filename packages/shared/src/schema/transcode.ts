import { sqliteTable, text, integer, real } from 'drizzle-orm/sqlite-core';
import { songs } from './songs';

/**
 * 转码任务表
 *
 * 与 separation_tasks 同构：后端 transcode-queue 调用本地 ffmpeg 把 MV / 不兼容视频
 * 统一转码为 H.264 + AAC 的 MP4；任务进度（started/progress/completed/failed）由
 * EventEmitter 发出并经 WebSocket 广播给管理后台。
 */
export const transcodeTasks = sqliteTable('transcode_tasks', {
  id: integer('id').primaryKey(),
  songId: integer('song_id').references(() => songs.id),
  // pending | processing | completed | failed
  status: text('status'),
  // 画质预设 key：compatible | standard | high（见 backend transcode-queue 的 PROFILES）
  profile: text('profile'),
  priority: integer('priority').default(0),
  progress: real('progress').default(0),
  // transcoding | done | null
  stage: text('stage'),
  error: text('error'),
  retryCount: integer('retry_count').default(0),
  createdAt: integer('created_at', { mode: 'timestamp' }),
  startedAt: integer('started_at', { mode: 'timestamp' }),
  completedAt: integer('completed_at', { mode: 'timestamp' }),
});

export type TranscodeTask = typeof transcodeTasks.$inferSelect;
export type NewTranscodeTask = typeof transcodeTasks.$inferInsert;
