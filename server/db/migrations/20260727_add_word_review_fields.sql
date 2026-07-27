-- 在生词本上增加轻量复习状态，任务直接从 user_word_book 调度。
ALTER TABLE user_word_book
  ADD COLUMN review_step TINYINT NOT NULL DEFAULT 0 AFTER tip,
  ADD COLUMN next_review_at DATE DEFAULT NULL AFTER review_step,
  ADD COLUMN mastery_status VARCHAR(16) NOT NULL DEFAULT 'learning' AFTER next_review_at,
  ADD COLUMN last_reviewed_at DATETIME DEFAULT NULL AFTER mastery_status,
  ADD KEY idx_user_review_due (user_id, mastery_status, next_review_at);

-- 已有生词：立即进入待复习池，方便迁移后立刻可用。
UPDATE user_word_book
SET next_review_at = CURDATE(),
    mastery_status = 'learning',
    review_step = 0
WHERE next_review_at IS NULL;
