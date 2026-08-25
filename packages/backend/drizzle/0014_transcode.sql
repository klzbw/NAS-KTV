-- 转码功能：songs 增量列 + transcode_tasks 表。
-- 仅追加，不动已有列/表/约束；老库升级安全。
-- 转码把 MV / 不兼容视频统一转为 H.264 + AAC 的 MP4，产物路径存 transcoded_path。
-- 每个语句单独成段，由 migrator 在每条语句后插入的分隔标记处自动切分后逐条 prepare 执行。

ALTER TABLE songs ADD COLUMN transcoded_path TEXT;--> statement-breakpoint
ALTER TABLE songs ADD COLUMN transcode_status TEXT;--> statement-breakpoint
ALTER TABLE songs ADD COLUMN transcode_profile TEXT;--> statement-breakpoint
ALTER TABLE songs ADD COLUMN transcode_started_at INTEGER;--> statement-breakpoint
ALTER TABLE songs ADD COLUMN transcode_completed_at INTEGER;--> statement-breakpoint
ALTER TABLE songs ADD COLUMN transcode_error TEXT;--> statement-breakpoint

CREATE TABLE transcode_tasks (
  id INTEGER PRIMARY KEY,
  song_id INTEGER REFERENCES songs(id),
  status TEXT,
  profile TEXT,
  priority INTEGER DEFAULT 0,
  progress REAL DEFAULT 0,
  stage TEXT,
  error TEXT,
  retry_count INTEGER DEFAULT 0,
  created_at INTEGER,
  started_at INTEGER,
  completed_at INTEGER
);
