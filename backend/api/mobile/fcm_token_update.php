<?php
require_once 'common.php';

$data = apiRequireJson();
apiEnsurePost();

$userId = $data['userId'] ?? '';
$fcmToken = $data['fcmToken'] ?? '';
$platform = $data['platform'] ?? 'mobile';

if (empty($userId) || empty($fcmToken)) {
    apiRespond(400, ['status' => 'error', 'error' => 'Missing required fields: userId and fcmToken']);
}

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

    // Insert or update FCM token
    $stmt = $conn->prepare("
        INSERT INTO user_fcm_tokens (user_id, fcm_token, platform, created_at, updated_at) 
        VALUES (?, ?, ?, NOW(), NOW()) 
        ON DUPLICATE KEY UPDATE 
        fcm_token = VALUES(fcm_token), 
        updated_at = NOW()
    ");
    
    if (!$stmt) {
        throw new Exception('Failed to prepare statement: ' . $conn->error);
    }
    
    $stmt->bind_param("sss", $userId, $fcmToken, $platform);
    
    if (!$stmt->execute()) {
        throw new Exception('Failed to execute statement: ' . $stmt->error);
    }
    
    $stmt->close();
    
    apiRespond(200, [
        'status' => 'ok', 
        'message' => 'FCM token updated successfully',
        'userId' => $userId,
        'platform' => $platform
    ]);
    
} catch (Exception $e) {
    error_log("FCM token update error: " . $e->getMessage());
    apiRespond(500, [
        'status' => 'error', 
        'error' => 'Failed to update FCM token: ' . $e->getMessage()
    ]);
}
?>
