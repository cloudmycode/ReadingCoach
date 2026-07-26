CREATE TABLE IF NOT EXISTS user_word_book (
  entry_id BIGINT NOT NULL AUTO_INCREMENT,
  user_id INT NOT NULL,
  article_id BIGINT NOT NULL,
  sentence_id BIGINT NOT NULL,
  normalized_word VARCHAR(128) NOT NULL,
  word VARCHAR(128) NOT NULL DEFAULT '',
  sentence_original TEXT NOT NULL,
  sentence_translation TEXT NOT NULL,
  part_of_speech VARCHAR(32) NOT NULL DEFAULT '',
  meaning TEXT NOT NULL,
  tip TEXT NOT NULL,
  looked_up_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (entry_id),
  UNIQUE KEY idx_user_sentence_word (user_id, article_id, sentence_id, normalized_word),
  KEY idx_user_looked_up (user_id, looked_up_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
