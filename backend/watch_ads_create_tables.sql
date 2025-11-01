-- Watch Ads reward infrastructure
-- Execute each block individually in production and wrap with appropriate backups if required.

/* ------------------------------------------------------------------
   Table: watch_ads_sessions
   Purpose: Tracks each rewarded ad viewing session for audit/fraud checks.
-------------------------------------------------------------------*/
CREATE TABLE IF NOT EXISTS watch_ads_sessions (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id           INT NOT NULL,
  role              ENUM('driver','supervisor') NOT NULL,
  ad_network        VARCHAR(60) NOT NULL,
  session_token     VARCHAR(120) NOT NULL,
  reward_amount     DECIMAL(12,2) NOT NULL DEFAULT 0,
  status            ENUM('initiated','rewarded','failed','duplicate','expired') NOT NULL DEFAULT 'initiated',
  rewarded_at       DATETIME DEFAULT NULL,
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_session_token (session_token),
  KEY idx_user_status (user_id, status),
  KEY idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* ------------------------------------------------------------------
   Table: user_reward_balances
   Purpose: Keeps the latest balance so the app can display it quickly.
-------------------------------------------------------------------*/
CREATE TABLE IF NOT EXISTS user_reward_balances (
  user_id     INT NOT NULL,
  role        ENUM('driver','supervisor') NOT NULL,
  balance     DECIMAL(14,2) NOT NULL DEFAULT 0,
  updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, role)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* ------------------------------------------------------------------
   Table: reward_ledger
   Purpose: Immutable ledger of every credit/debit event (ads, redemptions, manual adjustments).
-------------------------------------------------------------------*/
CREATE TABLE IF NOT EXISTS reward_ledger (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id       INT NOT NULL,
  role          ENUM('driver','supervisor') NOT NULL,
  amount        DECIMAL(14,2) NOT NULL,
  direction     ENUM('credit','debit') NOT NULL DEFAULT 'credit',
  source        ENUM('ad_reward','redeem','adjustment','rollback') NOT NULL,
  reference_id  BIGINT UNSIGNED DEFAULT NULL,
  note          VARCHAR(255) DEFAULT NULL,
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_user_time (user_id, created_at),
  KEY idx_reference (reference_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* ------------------------------------------------------------------
   Table: watch_ads_limits
   Purpose: Optional global configuration (daily caps, cooldowns, reward rates).
-------------------------------------------------------------------*/
CREATE TABLE IF NOT EXISTS watch_ads_limits (
  id                    TINYINT UNSIGNED NOT NULL DEFAULT 1,
  reward_amount         DECIMAL(12,2) NOT NULL DEFAULT 1.00,
  daily_view_limit      INT NOT NULL DEFAULT 10,
  cooldown_minutes      INT NOT NULL DEFAULT 30,
  last_updated_by       INT DEFAULT NULL,
  updated_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO watch_ads_limits (id, reward_amount, daily_view_limit, cooldown_minutes, last_updated_by)
VALUES (1, 1.00, 10, 30, NULL)
ON DUPLICATE KEY UPDATE
  reward_amount = VALUES(reward_amount),
  daily_view_limit = VALUES(daily_view_limit),
  cooldown_minutes = VALUES(cooldown_minutes);

