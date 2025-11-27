CREATE TABLE IF NOT EXISTS supervisor_absence_marks (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  absence_date DATE NOT NULL,
  driver_id INT NOT NULL,
  plant_id INT NOT NULL,
  supervisor_user_id INT NOT NULL,
  marked_absent TINYINT(1) NOT NULL DEFAULT 1,
  note VARCHAR(255) DEFAULT NULL,
  marked_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
    ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_absence_driver_date (driver_id, absence_date),
  KEY idx_absence_supervisor_date (supervisor_user_id, absence_date),
  KEY idx_absence_plant_date (plant_id, absence_date),
  CONSTRAINT fk_absence_driver
    FOREIGN KEY (driver_id) REFERENCES drivers(id) ON DELETE CASCADE,
  CONSTRAINT fk_absence_supervisor
    FOREIGN KEY (supervisor_user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_absence_plant
    FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS supervisor_absence_audit (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  absence_mark_id BIGINT UNSIGNED NOT NULL,
  action ENUM('marked_absent','cleared') NOT NULL,
  supervisor_user_id INT NOT NULL,
  action_note VARCHAR(255) DEFAULT NULL,
  action_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_absence_audit_mark (absence_mark_id),
  CONSTRAINT fk_absence_audit_mark
    FOREIGN KEY (absence_mark_id)
    REFERENCES supervisor_absence_marks(id) ON DELETE CASCADE,
  CONSTRAINT fk_absence_audit_supervisor
    FOREIGN KEY (supervisor_user_id)
    REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
