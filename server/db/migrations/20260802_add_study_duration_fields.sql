-- 按篇累计阅读有效时长；按日累计阅读/复习有效时长。
ALTER TABLE articles
  ADD COLUMN read_seconds INT NOT NULL DEFAULT 0 COMMENT '累计有效阅读秒数' AFTER read_count;

ALTER TABLE user_study_logs
  ADD COLUMN read_seconds INT NOT NULL DEFAULT 0 COMMENT '当日有效阅读秒数' AFTER review_article_count,
  ADD COLUMN review_seconds INT NOT NULL DEFAULT 0 COMMENT '当日有效复习秒数' AFTER read_seconds;
