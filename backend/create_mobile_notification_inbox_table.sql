CREATE TABLE IF NOT EXISTS `mobile_notification_inbox` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `recipient_user_id` VARCHAR(64) NOT NULL,
  `title` VARCHAR(255) NOT NULL DEFAULT '',
  `body` TEXT NOT NULL,
  `data_json` LONGTEXT NULL,
  `source` VARCHAR(64) NOT NULL DEFAULT 'push_api',
  `scope` VARCHAR(32) NOT NULL DEFAULT 'direct',
  `status` VARCHAR(32) NOT NULL DEFAULT 'queued',
  `sender_username` VARCHAR(100) NULL,
  `fcm_message_name` VARCHAR(255) NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `dismissed_at` DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_mobile_notification_recipient` (`recipient_user_id`, `dismissed_at`, `created_at`),
  KEY `idx_mobile_notification_status` (`status`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
