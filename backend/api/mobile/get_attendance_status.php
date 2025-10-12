<?php
require_once 'common.php';

// Handle both GET and POST requests
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $data = apiRequireJson();
    $userId = $data['userId'] ?? '';
} else {
    $userId = $_GET['userId'] ?? '';
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
    
    $driverId = $userData['driver_id'];
    $hasOpenAttendance = false;
    $openRecords = [];
    $currentStatus = 'checked_out'; // Default status
    
    // Check for open attendance records using driver_id
    if ($driverId && !empty($driverId)) {
        $stmt = $conn->prepare("
            SELECT id, driver_id, plant_id, vehicle_id, assignment_id, 
                   in_time, out_time, notes, approval_status, source
            FROM attendance 
            WHERE driver_id = ? AND out_time IS NULL 
            ORDER BY in_time DESC 
            LIMIT 1
        ");
        $stmt->bind_param("i", $driverId);
        $stmt->execute();
        $result = $stmt->get_result();
        
        if ($result->num_rows > 0) {
            $row = $result->fetch_assoc();
            $openRecords[] = [
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
                'type' => 'driver'
            ];
            $hasOpenAttendance = true;
            $currentStatus = 'checked_in';
        }
        $stmt->close();
    }
    
    // Check for open attendance records using NULL driver_id and user_id in notes (supervisors)
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
        $openRecords[] = [
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
            'type' => 'supervisor'
        ];
        $hasOpenAttendance = true;
        $currentStatus = 'checked_in';
    }
    $stmt->close();
    
    // Get the most recent attendance record (last 30 days)
    $recentStmt = $conn->prepare("
        SELECT id, driver_id, plant_id, vehicle_id, assignment_id, 
               in_time, out_time, notes, approval_status, source
        FROM attendance 
        WHERE (driver_id = ? OR (driver_id IS NULL AND notes LIKE ?))
        ORDER BY in_time DESC 
        LIMIT 1
    ");
    $recentStmt->bind_param("is", $driverId, $supervisorPattern);
    $recentStmt->execute();
    $recentResult = $recentStmt->get_result();
    
    $lastAttendance = null;
    if ($recentResult->num_rows > 0) {
        $row = $recentResult->fetch_assoc();
        $lastAttendance = [
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
    }
    $recentStmt->close();
    
    apiRespond(200, [
        'status' => 'ok',
        'user_id' => $userId,
        'driver_id' => $driverId,
        'username' => $userData['username'],
        'full_name' => $userData['full_name'],
        'role' => $userData['role'],
        'current_status' => $currentStatus,
        'has_open_attendance' => $hasOpenAttendance,
        'open_records_count' => count($openRecords),
        'open_records' => $openRecords,
        'last_attendance' => $lastAttendance,
        'message' => $hasOpenAttendance 
            ? 'User has open attendance records - currently checked in'
            : 'User is currently checked out'
    ]);
    
} catch (Exception $e) {
    apiRespond(500, [
        'status' => 'error', 
        'error' => $e->getMessage()
    ]);
}
?>
