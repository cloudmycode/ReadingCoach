-- 记录每次生词复习结果，支持已完成任务按日期回溯「熟练 / 不熟悉」。
CREATE TABLE IF NOT EXISTS user_word_review_logs (
  log_id BIGINT NOT NULL AUTO_INCREMENT,
  user_id INT NOT NULL,
  entry_id BIGINT NOT NULL,
  result VARCHAR(16) NOT NULL,
  reviewed_at DATETIME NOT NULL,
  PRIMARY KEY (log_id),
  KEY idx_user_reviewed_at (user_id, reviewed_at),
  KEY idx_user_entry_reviewed (user_id, entry_id, reviewed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 兼容迁移前已有「最近一次复习」数据：无结果标记，前端可不展示熟练度徽章。
INSERT INTO user_word_review_logs (user_id, entry_id, result, reviewed_at)
SELECT w.user_id, w.entry_id, '', w.last_reviewed_at
FROM user_word_book w
WHERE w.last_reviewed_at IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM user_word_review_logs l
    WHERE l.user_id = w.user_id
      AND l.entry_id = w.entry_id
      AND l.reviewed_at = w.last_reviewed_at
  );
