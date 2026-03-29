-- ============================================================
-- SS Transways India – Referral Program Database Migration
-- Run this SQL on the production database before deploying.
-- ============================================================

-- 1. Add referral_code column to existing users table
ALTER TABLE `users`
    ADD COLUMN `referral_code` VARCHAR(20) DEFAULT NULL AFTER `role`,
    ADD COLUMN `referred_by` INT DEFAULT NULL AFTER `referral_code`,
    ADD UNIQUE INDEX `idx_users_referral_code` (`referral_code`);

-- 2. Create the user_referrals table
CREATE TABLE IF NOT EXISTS `user_referrals` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `referrer_user_id` INT NOT NULL COMMENT 'User who shared the referral code',
    `referral_code` VARCHAR(20) NOT NULL COMMENT 'The referral code used',
    `referred_user_id` INT DEFAULT NULL COMMENT 'New user who registered',
    `referred_username` VARCHAR(100) DEFAULT NULL,
    `referred_name` VARCHAR(200) DEFAULT NULL COMMENT 'Full name of the referred person',
    `referred_mobile` VARCHAR(15) DEFAULT NULL,
    `referred_type` ENUM('driver', 'helper') DEFAULT 'driver' COMMENT 'driver=₹50, helper=₹30',
    `aadhar_no` VARCHAR(20) DEFAULT NULL,
    `dl_no` VARCHAR(30) DEFAULT NULL,
    `aadhar_photo_url` VARCHAR(500) DEFAULT NULL,
    `dl_photo_url` VARCHAR(500) DEFAULT NULL,
    `status` ENUM('pending', 'verified', 'rejected') DEFAULT 'pending',
    `amount` DECIMAL(10, 2) DEFAULT 0.00 COMMENT 'Referral earning amount',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `profile_submitted_at` DATETIME DEFAULT NULL,
    `verified_at` DATETIME DEFAULT NULL,
    `verified_by` INT DEFAULT NULL COMMENT 'Admin who verified',
    `rejection_reason` VARCHAR(500) DEFAULT NULL,
    INDEX `idx_referrer` (`referrer_user_id`),
    INDEX `idx_referred_user` (`referred_user_id`),
    INDEX `idx_status` (`status`),
    INDEX `idx_referral_code` (`referral_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. Add UPI / Google Pay ID column to users table
ALTER TABLE `users`
    ADD COLUMN `upi_id` VARCHAR(100) DEFAULT NULL AFTER `referral_code`;

-- 4. Create withdrawal requests table
CREATE TABLE IF NOT EXISTS `referral_withdrawals` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `user_id` INT NOT NULL,
    `amount` DECIMAL(10, 2) NOT NULL,
    `upi_id` VARCHAR(100) NOT NULL,
    `status` ENUM('pending', 'approved', 'rejected') DEFAULT 'pending',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `processed_at` DATETIME DEFAULT NULL,
    `processed_by` INT DEFAULT NULL,
    `remarks` VARCHAR(500) DEFAULT NULL,
    INDEX `idx_withdrawal_user` (`user_id`),
    INDEX `idx_withdrawal_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
