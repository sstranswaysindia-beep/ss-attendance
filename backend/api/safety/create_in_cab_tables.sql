-- In-Cab Assessment master/details

CREATE TABLE IF NOT EXISTS `in_cab_assessments` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `driver_id` INT(11) NOT NULL,
  `vehicle_id` INT(11) NOT NULL,
  `plant_id` INT(11) DEFAULT NULL,
  `assessor_user_id` INT(11) DEFAULT NULL,
  `transporter_name` VARCHAR(255) DEFAULT NULL,
  `weather` VARCHAR(50) DEFAULT NULL,
  `location_text` VARCHAR(255) DEFAULT NULL,
  `start_time` DATETIME DEFAULT NULL,
  `end_time` DATETIME DEFAULT NULL,
  `assessment_date` DATE NOT NULL,
  `overall_notes` VARCHAR(500) DEFAULT NULL,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_incab_driver` (`driver_id`, `assessment_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `in_cab_assessment_items` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `assessment_id` BIGINT UNSIGNED NOT NULL,
  `section_key` VARCHAR(40) NOT NULL,
  `item_code` VARCHAR(40) NOT NULL,
  `question_text` VARCHAR(500) NOT NULL,
  `result` ENUM('positive','needs_improvement','not_observed','yes','no') NOT NULL,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_assessment_item` (`assessment_id`, `item_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
