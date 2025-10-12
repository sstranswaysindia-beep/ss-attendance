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
    $openRecords = [];
    $hasOpenAttendance = false;
    
    // Check for open attendance records using driver_id
    if ($driverId && !empty($driverId)) {
        $stmt = $conn->prepare("
            SELECT id, driver_id, plant_id, vehicle_id, assignment_id, 
                   in_time, out_time, notes, approval_status, source
            FROM attendance 
            WHERE driver_id = ? AND out_time IS NULL 
            ORDER BY in_time DESC 
            LIMIT 5
        ");
        $stmt->bind_param("i", $driverId);
        $stmt->execute();
        $result = $stmt->get_result();
        
        while ($row = $result->fetch_assoc()) {
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
        }
        $stmt->close();
    }
    
    // Check for open attendance records using NULL driver_id and user_id in notes
    $supervisorPattern = "SUPERVISOR_USER_ID:$userId%";
    $stmt = $conn->prepare("
        SELECT id, driver_id, plant_id, vehicle_id, assignment_id, 
               in_time, out_time, notes, approval_status, source
        FROM attendance 
        WHERE driver_id IS NULL AND notes LIKE ? AND out_time IS NULL 
        ORDER BY in_time DESC 
        LIMIT 5
    ");
    $stmt->bind_param("s", $supervisorPattern);
    $stmt->execute();
    $result = $stmt->get_result();
    
    while ($row = $result->fetch_assoc()) {
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
    }
    $stmt->close();
    
    apiRespond(200, [
        'status' => 'ok',
        'has_open_attendance' => $hasOpenAttendance,
        'open_records_count' => count($openRecords),
        'open_records' => $openRecords,
        'user_id' => $userId,
        'driver_id' => $driverId,
        'message' => $hasOpenAttendance 
            ? 'User has open attendance records that need to be resolved'
            : 'No open attendance records found'
    ]);
    
} catch (Exception $e) {
    apiRespond(500, [
        'status' => 'error', 
        'error' => $e->getMessage()
    ]);
}
?>
