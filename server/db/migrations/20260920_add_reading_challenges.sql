-- Reading quizzes and family rewards. No dependency on an external queue or payment service.
CREATE TABLE IF NOT EXISTS reading_accounts (
 user_id INT NOT NULL PRIMARY KEY,
 starts_on CHAR(10) NOT NULL,
 timezone VARCHAR(64) NOT NULL DEFAULT 'Asia/Shanghai'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS reading_article_roots (
 article_id BIGINT NOT NULL PRIMARY KEY,
 user_id INT NOT NULL,
 content_hash CHAR(64) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS reading_papers (
 id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
 user_id INT NOT NULL,
 article_id BIGINT NOT NULL,
 content_hash CHAR(64) NOT NULL,
 title VARCHAR(255) NOT NULL,
 source_json MEDIUMTEXT NOT NULL,
 questions_json MEDIUMTEXT NULL,
 generation_json MEDIUMTEXT NULL,
 quality_json MEDIUMTEXT NULL,
 model VARCHAR(100) NOT NULL,
 prompt_version VARCHAR(32) NOT NULL,
 created_at BIGINT NOT NULL,
 UNIQUE KEY article_version (user_id, article_id, content_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS reading_listening (
 user_id INT NOT NULL,
 paper_id BIGINT NOT NULL,
 sentence_id BIGINT NOT NULL,
 completed_at BIGINT NOT NULL,
 PRIMARY KEY (user_id, paper_id, sentence_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS reading_cycles (
 id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
 user_id INT NOT NULL,
 starts_on CHAR(10) NOT NULL,
 ends_on CHAR(10) NOT NULL,
 timezone VARCHAR(64) NOT NULL,
 rules_json TEXT NOT NULL,
 settled_at BIGINT NULL,
 UNIQUE KEY user_cycle (user_id, starts_on),
 KEY unsettled (settled_at, ends_on)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS reading_attempts (
 id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
 user_id INT NOT NULL,
 paper_id BIGINT NOT NULL,
 cycle_id BIGINT NOT NULL,
 request_key VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 answers_json MEDIUMTEXT NOT NULL,
 results_json MEDIUMTEXT NULL,
 raw_result_json MEDIUMTEXT NULL,
 graded_model VARCHAR(100) NOT NULL DEFAULT '',
 grading_prompt_version VARCHAR(32) NOT NULL DEFAULT '',
 status VARCHAR(24) NOT NULL DEFAULT 'pending',
 score INT NULL,
 passed BOOLEAN NOT NULL DEFAULT FALSE,
 submitted_at BIGINT NOT NULL,
 submitted_on CHAR(10) NOT NULL,
 graded_at BIGINT NULL,
 UNIQUE KEY user_request (user_id, request_key),
 KEY cycle_pending (cycle_id, status),
 KEY user_paper (user_id, paper_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS reading_passes (
 user_id INT NOT NULL,
 content_hash CHAR(64) NOT NULL,
 attempt_id BIGINT NOT NULL,
 PRIMARY KEY (user_id, content_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS reading_days (
 user_id INT NOT NULL,
 completed_on CHAR(10) NOT NULL,
 cycle_id BIGINT NOT NULL,
 attempt_id BIGINT NOT NULL,
 PRIMARY KEY (user_id, completed_on),
 KEY cycle_days (cycle_id, completed_on)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS reading_vouchers (
 id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
 user_id INT NOT NULL,
 cycle_id BIGINT NOT NULL,
 stars INT NOT NULL,
 completed_days INT NOT NULL,
 amount_fen INT NOT NULL,
 issued_at BIGINT NOT NULL,
 redeemed_at BIGINT NULL,
 UNIQUE KEY cycle_voucher (cycle_id),
 KEY user_vouchers (user_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS reading_jobs (
 id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
 kind VARCHAR(16) NOT NULL,
 ref_id BIGINT NOT NULL,
 state VARCHAR(16) NOT NULL DEFAULT 'queued',
 tries INT NOT NULL DEFAULT 0,
 available_at BIGINT NOT NULL,
 lease_until BIGINT NOT NULL DEFAULT 0,
 token CHAR(32) NOT NULL DEFAULT '',
 last_error VARCHAR(100) NOT NULL DEFAULT '',
 UNIQUE KEY job_business_key (kind, ref_id),
 KEY queued_jobs (state, available_at, id),
 KEY leased_jobs (state, lease_until, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
