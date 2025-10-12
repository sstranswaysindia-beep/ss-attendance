<?php
require_once 'common.php';

header('Content-Type: application/json; charset=utf-8');

// Get user ID from POST data (same as the mobile app sends)
$input = json_decode(file_get_contents('php://input'), true);
$userId = $input['userId'] ?? $_GET['userId'] ?? '1';

echo json_encode([
    'debug' => true,
    'userId_received' => $userId,
    'timestamp' => date('Y-m-d H:i:s')
], JSON_PRETTY_PRINT);

try {
    // Test the exact same query as get_user_profile.php
    $stmt = $conn->prepare("
        SELECT 
            id,
            username,
            full_name,
            email,
            phone,
            role,
            profile_photo,
            created_at,
            updated_at,
            last_login_at,
            must_change_password
        FROM users 
        WHERE id = ? 
        LIMIT 1
    ");
    
    $stmt->bind_param("s", $userId);
    $stmt->execute();
    $result = $stmt->get_result();
    $userProfile = $result->fetch_assoc();
    $stmt->close();

    if (!$userProfile) {
        echo "\n\n" . json_encode([
            'status' => 'error',
            'error' => 'User not found',
            'userId' => $userId
        ], JSON_PRETTY_PRINT);
    } else {
        echo "\n\n" . json_encode([
            'status' => 'ok',
            'profile' => $userProfile,
            'profile_photo_exists' => !empty($userProfile['profile_photo']),
            'profile_photo_url' => $userProfile['profile_photo']
        ], JSON_PRETTY_PRINT);
    }
    
} catch (Exception $e) {
    echo "\n\n" . json_encode([
        'status' => 'error',
        'error' => 'Database error: ' . $e->getMessage()
    ], JSON_PRETTY_PRINT);
}
?>
