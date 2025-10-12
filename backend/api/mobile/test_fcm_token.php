<?php
require_once 'common.php';

// Test script to manually add FCM token for testing
$testUserId = 'test_user_123';
$testFCMToken = 'test_fcm_token_' . time();

try {
    // Create table if it doesn't exist
    $createTableSQL = "
        CREATE TABLE IF NOT EXISTS user_fcm_tokens (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id VARCHAR(255) NOT NULL,
            fcm_token TEXT NOT NULL,
            platform VARCHAR(50) DEFAULT 'mobile',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY unique_user_platform (user_id, platform),
            INDEX idx_user_id (user_id),
            INDEX idx_fcm_token (fcm_token(100))
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ";
    
    if (!$conn->query($createTableSQL)) {
        throw new Exception('Failed to create FCM tokens table: ' . $conn->error);
    }

    // Insert test FCM token
    $stmt = $conn->prepare("
        INSERT INTO user_fcm_tokens (user_id, fcm_token, platform, created_at, updated_at) 
        VALUES (?, ?, ?, NOW(), NOW()) 
        ON DUPLICATE KEY UPDATE 
        fcm_token = VALUES(fcm_token), 
        updated_at = NOW()
    ");
    
    $platform = 'mobile';
    $stmt->bind_param("sss", $testUserId, $testFCMToken, $platform);
    
    if (!$stmt->execute()) {
        throw new Exception('Failed to execute statement: ' . $stmt->error);
    }
    
    $stmt->close();
    
    echo json_encode([
        'status' => 'ok',
        'message' => 'Test FCM token added successfully',
        'userId' => $testUserId,
        'fcmToken' => $testFCMToken,
        'platform' => $platform
    ], JSON_PRETTY_PRINT);
    
} catch (Exception $e) {
    echo json_encode([
        'status' => 'error',
        'error' => 'Failed to add test FCM token: ' . $e->getMessage()
    ], JSON_PRETTY_PRINT);
}
?>
