CREATE TABLE IF NOT EXISTS user_devices (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id INT NOT NULL,
  device_id VARCHAR(120) NOT NULL,
  app_identifier VARCHAR(200) NOT NULL,
  platform VARCHAR(32) NOT NULL,
  device_model VARCHAR(200) DEFAULT NULL,
  os_version VARCHAR(120) DEFAULT NULL,
  app_version VARCHAR(32) DEFAULT NULL,
  app_build VARCHAR(32) DEFAULT NULL,
  last_seen_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  first_seen_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  meta_json JSON DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_user_device (user_id, app_identifier, device_id),
  KEY idx_user_devices_user (user_id),
  KEY idx_user_devices_platform (platform)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
