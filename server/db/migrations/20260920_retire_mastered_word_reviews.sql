-- 配合“已学会立即移出任务”规则部署；可重复执行。
-- 只处理最后一次明确选择“认识了”的学习中条目。
-- 后来又选“还不熟”、已暂停、无明确结果的旧记录保持不变。
UPDATE user_word_book w
INNER JOIN (
    SELECT user_id, entry_id, MAX(log_id) AS latest_log_id
    FROM user_word_review_logs
    GROUP BY user_id, entry_id
) latest ON latest.user_id = w.user_id AND latest.entry_id = w.entry_id
INNER JOIN user_word_review_logs l ON l.log_id = latest.latest_log_id
SET w.mastery_status = 'mastered',
    w.next_review_at = NULL,
    w.updated_at = NOW()
WHERE w.mastery_status = 'learning'
  AND l.result = 'mastered';
