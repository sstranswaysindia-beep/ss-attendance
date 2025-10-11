-- Create advance_approval_logs table for tracking approval actions
CREATE TABLE IF NOT EXISTS advance_approval_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    request_id INT NOT NULL,
    driver_id INT NOT NULL,
    action ENUM('approve', 'reject') NOT NULL,
    admin_id VARCHAR(100) NOT NULL,
    comments TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_request_id (request_id),
    INDEX idx_driver_id (driver_id),
    INDEX idx_created_at (created_at),
    
    FOREIGN KEY (request_id) REFERENCES advance_requests(id) ON DELETE CASCADE,
    FOREIGN KEY (driver_id) REFERENCES drivers(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
