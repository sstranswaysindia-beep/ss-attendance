CREATE TABLE IF NOT EXISTS khata_entry_controls (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  previous_month_entry_cutoff_day TINYINT UNSIGNED NOT NULL DEFAULT 31,
  previous_month_entry_cutoff_mmdd CHAR(5) DEFAULT NULL,
  is_active ENUM('Y', 'N') NOT NULL DEFAULT 'Y',
  effective_from DATE DEFAULT NULL,
  effective_to DATE DEFAULT NULL,
  remarks VARCHAR(255) DEFAULT NULL,
  updated_by INT DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_khata_controls_active_dates (is_active, effective_from, effective_to)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Default rule: block previous-month entries after day 31 (month-end behavior).
-- You can also set recurring annual cutoff using MM-DD in previous_month_entry_cutoff_mmdd (example: 04-01).
INSERT INTO khata_entry_controls (
  previous_month_entry_cutoff_day,
  previous_month_entry_cutoff_mmdd,
  is_active,
  effective_from,
  effective_to,
  remarks
)
SELECT 31, NULL, 'Y', NULL, NULL, 'Default cutoff (month-end)'
WHERE NOT EXISTS (SELECT 1 FROM khata_entry_controls);
