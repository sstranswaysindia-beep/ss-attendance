<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

// Handle preflight requests
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

try {
    require_once 'common.php';
    
    // Handle both GET and POST requests
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $data = json_decode(file_get_contents('php://input'), true);
        $userId = $data['userId'] ?? '';
        $driverId = $data['driverId'] ?? null;
    } else {
        $userId = $_GET['userId'] ?? '';
        $driverId = $_GET['driverId'] ?? null;
    }
    
    if (empty($userId)) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'error' => 'Missing userId']);
        exit();
    }
    
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
    
    // Check for open attendance records using NULL driver_id and user_id in notes (supervisors)
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
    
    http_response_code(200);
    echo json_encode([
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
    http_response_code(500);
    echo json_encode([
        'status' => 'error', 
        'error' => $e->getMessage()
    ]);
}
?>
