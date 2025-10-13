-- Add receipt_path field to advance_transactions table
ALTER TABLE `advance_transactions` 
ADD COLUMN `receipt_path` VARCHAR(500) DEFAULT NULL AFTER `description`;

-- Add index for receipt_path for better query performance
ALTER TABLE `advance_transactions` 
ADD INDEX `idx_receipt_path` (`receipt_path`);
