CREATE TABLE IF NOT EXISTS word_explanations_cache (
  cache_id INT NOT NULL AUTO_INCREMENT,
  sentence_id BIGINT NOT NULL DEFAULT 0,
  normalized_word VARCHAR(128) NOT NULL,
  word VARCHAR(128) NOT NULL DEFAULT '',
  part_of_speech VARCHAR(32) NOT NULL DEFAULT '',
  meaning TEXT NOT NULL,
  tip TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (cache_id),
  UNIQUE KEY idx_sentence_word (sentence_id, normalized_word)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
