ALTER TABLE `users`
    ADD COLUMN `proxy_enabled` ENUM('Y','N') NOT NULL DEFAULT 'N' AFTER `view_document`;

-- Optional: mark selected supervisors/drivers here, for example:
-- UPDATE `users` SET `proxy_enabled` = 'Y' WHERE `username` IN ('supervisor1', 'driver123');
