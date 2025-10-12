<?php
require_once 'common.php';

$data = apiRequireJson();
apiEnsurePost();

$userId = $data['userId'] ?? '';

if (empty($userId)) {
    apiRespond(400, ['status' => 'error', 'error' => 'Missing userId']);
}

try {
    // Get user profile data from users table
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
    
    if ($result->num_rows === 0) {
        apiRespond(404, ['status' => 'error', 'error' => 'User not found']);
    }
    
    $userData = $result->fetch_assoc();
    $stmt->close();
    
    // Get supervised plants if user is a supervisor
    $supervisedPlants = [];
    if ($userData['role'] === 'supervisor') {
        $plantStmt = $conn->prepare("
            SELECT DISTINCT p.id, p.plant_name
            FROM plants p
            LEFT JOIN supervisor_plants sp ON sp.plant_id = p.id
            WHERE p.supervisor_user_id = ? OR sp.user_id = ?
            ORDER BY p.plant_name
        ");
        
        $plantStmt->bind_param("ss", $userId, $userId);
        $plantStmt->execute();
        $plantResult = $plantStmt->get_result();
        
        while ($plant = $plantResult->fetch_assoc()) {
            $supervisedPlants[] = [
                'id' => $plant['id'],
                'plant_name' => $plant['plant_name']
            ];
        }
        $plantStmt->close();
    }
    
    // Format the response
    $response = [
        'status' => 'ok',
        'profile' => [
            'id' => $userData['id'],
            'username' => $userData['username'],
            'full_name' => $userData['full_name'],
            'email' => $userData['email'],
            'phone' => $userData['phone'],
            'role' => $userData['role'],
            'profile_photo' => $userData['profile_photo'],
            'created_at' => $userData['created_at'],
            'updated_at' => $userData['updated_at'],
            'last_login_at' => $userData['last_login_at'],
            'must_change_password' => (bool)$userData['must_change_password'],
            'supervised_plants' => $supervisedPlants,
            'total_supervised_plants' => count($supervisedPlants),
        ]
    ];
    
    apiRespond(200, $response);
    
} catch (Exception $e) {
    error_log("Error fetching user profile: " . $e->getMessage());
    apiRespond(500, ['status' => 'error', 'error' => 'Failed to fetch profile']);
}
?>
