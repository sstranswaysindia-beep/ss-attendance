-- Adds a notification bucket for trip deletions.
-- Run this once on the primary database.

CREATE TABLE IF NOT EXISTS `notification_trip` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `trip_id` BIGINT UNSIGNED NOT NULL,
  `trip_number` VARCHAR(50) DEFAULT NULL,
  `vehicle_id` BIGINT UNSIGNED DEFAULT NULL,
  `vehicle_number` VARCHAR(40) DEFAULT NULL,
  `deleted_by_user_id` BIGINT UNSIGNED DEFAULT NULL,
  `deleted_by_name` VARCHAR(120) DEFAULT NULL,
  `message` VARCHAR(255) NOT NULL,
  `payload` JSON DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_notification_trip_trip_id` (`trip_id`),
  KEY `idx_notification_trip_vehicle_id` (`vehicle_id`),
  KEY `idx_notification_trip_user_id` (`deleted_by_user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

