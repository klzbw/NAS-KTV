import { sqliteTable, text, integer, real } from 'drizzle-orm/sqlite-core';
import { songs } from './songs';

export const aiParseTasks = sqliteTable('ai_parse_tasks', {
  id: integer('id').primaryKey(),
  songId: integer('song_id').references(() => songs.id),
  status: text('status'),
  model: text('model'),
  promptTemplate: text('prompt_template'),
  requestMessages: text('request_messages'),
  responseRaw: text('response_raw'),
  result: text('result'),
  error: text('error'),
  confidence: real('confidence'),
  needReview: integer('need_review').default(0),
  originalTitle: text('original_title'),
  originalArtistId: integer('original_artist_id'),
  originalArtistName: text('original_artist_name'),
  createdAt: integer('created_at', { mode: 'timestamp' }),
  startedAt: integer('started_at', { mode: 'timestamp' }),
  completedAt: integer('completed_at', { mode: 'timestamp' }),

  // ===== 人工干预/审核留痕 =====
  // AI 原始解析结果 JSON 快照（解析完成时固定；result 被人工修改覆盖后仍可对比）
  aiResult: text('ai_result'),
  // 是否人工修改过解析结果（0/1，modify 审核时置 1）
  manualEdited: integer('manual_edited').default(0),
  // 审核动作：approve / modify / reject（NULL=尚未人工审核）
  reviewAction: text('review_action'),
  // 审核人（JWT username）
  reviewedBy: text('reviewed_by'),
  // 审核时间
  reviewedAt: integer('reviewed_at', { mode: 'timestamp' }),
  // 审核备注（可选）
  reviewNote: text('review_note'),
});

export type AiParseTask = typeof aiParseTasks.$inferSelect;
export type NewAiParseTask = typeof aiParseTasks.$inferInsert;
