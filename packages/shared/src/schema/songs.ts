import { sqliteTable, text, integer, real } from 'drizzle-orm/sqlite-core';
import { artists } from './artists';

export const songs = sqliteTable('songs', {
  id: integer('id').primaryKey(),
  title: text('title').notNull(),
  artistId: integer('artist_id').references(() => artists.id),
  albumId: integer('album_id'),
  filePath: text('file_path').unique().notNull(),
  fileType: text('file_type', { enum: ['audio', 'video'] }),
  duration: integer('duration'),
  lyricsPath: text('lyrics_path'),
  pitchDefault: integer('pitch_default').default(0),
  playCount: integer('play_count').default(0),
  createdAt: integer('created_at', { mode: 'timestamp' }).defaultNow(),

  vocalsPath: text('vocals_path'),
  instrumentalPath: text('instrumental_path'),
  separationStatus: text('separation_status', {
    enum: ['pending', 'processing', 'completed', 'failed'],
  }),
  separationModel: text('separation_model'),
  separationStartedAt: integer('separation_started_at', { mode: 'timestamp' }),
  separationCompletedAt: integer('separation_completed_at', { mode: 'timestamp' }),
  separationError: text('separation_error'),

  // ===== 转码（MV → 通用视频）相关字段 =====
  transcodedPath: text('transcoded_path'),
  transcodeStatus: text('transcode_status', {
    enum: ['pending', 'processing', 'completed', 'failed'],
  }),
  transcodeProfile: text('transcode_profile'),
  transcodeStartedAt: integer('transcode_started_at', { mode: 'timestamp' }),
  transcodeCompletedAt: integer('transcode_completed_at', { mode: 'timestamp' }),
  transcodeError: text('transcode_error'),

  aiParsed: integer('ai_parsed').default(0),
  aiParsedAt: integer('ai_parsed_at', { mode: 'timestamp' }),
  aiConfidence: real('ai_confidence'),
  aiNeedReview: integer('ai_need_review').default(0),
  // 当前 AI 解析结果是否经过人工修改（0/1，modify 审核时置 1，列表徽标用）
  aiManualEdited: integer('ai_manual_edited').default(0),
  rawTags: text('raw_tags'),
  fileHash: text('file_hash'),
});

export type Song = typeof songs.$inferSelect;
export type NewSong = typeof songs.$inferInsert;
