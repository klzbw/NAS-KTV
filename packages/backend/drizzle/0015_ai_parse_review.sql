-- AI 解析人工干预/审核留痕。
-- ai_parse_tasks：AI 原始结果快照（ai_result，modify 覆盖 result 后仍可对比）、
-- 是否人工修改（manual_edited）、审核动作/人/时间/备注（review_*）。
-- songs：当前 AI 结果是否经人工修改（ai_manual_edited，列表徽标用）。
-- 仅追加新增可空列，不动已有列/表/约束；老库升级安全。

ALTER TABLE ai_parse_tasks ADD COLUMN ai_result TEXT;--> statement-breakpoint
ALTER TABLE ai_parse_tasks ADD COLUMN manual_edited INTEGER DEFAULT 0;--> statement-breakpoint
ALTER TABLE ai_parse_tasks ADD COLUMN review_action TEXT;--> statement-breakpoint
ALTER TABLE ai_parse_tasks ADD COLUMN reviewed_by TEXT;--> statement-breakpoint
ALTER TABLE ai_parse_tasks ADD COLUMN reviewed_at INTEGER;--> statement-breakpoint
ALTER TABLE ai_parse_tasks ADD COLUMN review_note TEXT;--> statement-breakpoint
ALTER TABLE songs ADD COLUMN ai_manual_edited INTEGER DEFAULT 0;--> statement-breakpoint
