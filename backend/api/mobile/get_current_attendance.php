<?php
require_once 'common.php';

// Handle both GET and POST requests
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $data = apiRequireJson();
    $userId = $data['userId'] ?? '';
    $driverId = $data['driverId'] ?? null;
} else {
    $userId = $_GET['userId'] ?? '';
    $driverId = $_GET['driverId'] ?? null;
}

if (empty($userId)) {
    apiRespond(400, ['status' => 'error', 'error' => 'Missing userId']);
}

try {
    // Get user details
    $userStmt = $conn->prepare("SELECT id, username, full_name, role, driver_id FROM users WHERE id = ? LIMIT 1");
    $userStmt->bind_param("s", $userId);
    $userStmt->execute();
    $userResult = $userStmt->get_result();
    
    if ($userResult->num_rows === 0) {
        apiRespond(404, ['status' => 'error', 'error' => 'User not found']);
    }
    
    $userData = $userResult->fetch_assoc();
    $userStmt->close();
    
    // Use provided driverId or get from user data
    $finalDriverId = $driverId ?? $userData['driver_id'];
    
    $currentAttendance = null;
    $isCheckedIn = false;
    
    // Check for current attendance using driver_id
    if ($finalDriverId && !empty($finalDriverId)) {
        $stmt = $conn->prepare("
            SELECT id, driver_id, plant_id, vehicle_id, assignment_id, 
                   in_time, out_time, notes, approval_status, source
            FROM attendance 
            WHERE driver_id = ? AND out_time IS NULL 
            ORDER BY in_time DESC 
            LIMIT 1
        ");
        $stmt->bind_param("i", $finalDriverId);
        $stmt->execute();
        $result = $stmt->get_result();
        
        if ($result->num_rows > 0) {
            $row = $result->fetch_assoc();
            $currentAttendance = [
                'id' => $row['id'],
                'driver_id' => $row['driver_id'],
                'plant_id' => $row['plant_id'],
                'vehicle_id' => $row['vehicle_id'],
                'assignment_id' => $row['assignment_id'],
                'in_time' => $row['in_time'],
                'out_time' => $row['out_time'],
                'notes' => $row['notes'],
                'approval_status' => $row['approval_status'],
                'source' => $row['source'],
            ];
            $isCheckedIn = true;
        }
        $stmt->close();
    }
    
    // Check for current attendance using NULL driver_id and user_id in notes (supervisors)
    if (!$isCheckedIn) {
        $supervisorPattern = "SUPERVISOR_USER_ID:$userId%";
        $stmt = $conn->prepare("
            SELECT id, driver_id, plant_id, vehicle_id, assignment_id, 
                   in_time, out_time, notes, approval_status, source
            FROM attendance 
            WHERE driver_id IS NULL AND notes LIKE ? AND out_time IS NULL 
            ORDER BY in_time DESC 
            LIMIT 1
        ");
        $stmt->bind_param("s", $supervisorPattern);
        $stmt->execute();
        $result = $stmt->get_result();
        
        if ($result->num_rows > 0) {
            $row = $result->fetch_assoc();
            $currentAttendance = [
                'id' => $row['id'],
                'driver_id' => $row['driver_id'],
                'plant_id' => $row['plant_id'],
                'vehicle_id' => $row['vehicle_id'],
                'assignment_id' => $row['assignment_id'],
                'in_time' => $row['in_time'],
                'out_time' => $row['out_time'],
                'notes' => $row['notes'],
                'approval_status' => $row['approval_status'],
                'source' => $row['source'],
            ];
            $isCheckedIn = true;
        }
        $stmt->close();
    }
    
    apiRespond(200, [
        'status' => 'ok',
        'user_id' => $userId,
        'driver_id' => $finalDriverId,
        'username' => $userData['username'],
        'full_name' => $userData['full_name'],
        'role' => $userData['role'],
        'is_checked_in' => $isCheckedIn,
        'current_attendance' => $currentAttendance,
        'message' => $isCheckedIn 
            ? 'User is currently checked in'
            : 'User is currently checked out'
    ]);
    
} catch (Exception $e) {
    apiRespond(500, [
        'status' => 'error', 
        'error' => $e->getMessage()
    ]);
}
?>
