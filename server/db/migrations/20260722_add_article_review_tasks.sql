CREATE TABLE IF NOT EXISTS article_review_tasks (
    task_id BIGINT NOT NULL AUTO_INCREMENT,
    user_id INT NOT NULL,
    article_id INT NOT NULL,
    task_type VARCHAR(32) NOT NULL DEFAULT 'review',
    scheduled_for DATE NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'pending',
    started_at DATETIME DEFAULT NULL,
    completed_at DATETIME DEFAULT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL,
    PRIMARY KEY (task_id),
    UNIQUE KEY idx_user_article_day_type (user_id, article_id, scheduled_for, task_type),
    KEY idx_user_status_schedule (user_id, status, scheduled_for),
    KEY idx_user_completed_at (user_id, completed_at),
    CONSTRAINT fk_article_review_tasks_article FOREIGN KEY (article_id) REFERENCES articles(article_id) ON DELETE CASCADE,
    CONSTRAINT fk_article_review_tasks_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
