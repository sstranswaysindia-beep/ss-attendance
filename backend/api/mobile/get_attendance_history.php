<?php
require_once 'common.php';

// Handle both GET and POST requests
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $data = apiRequireJson();
    $userId = $data['userId'] ?? '';
    $startDate = $data['startDate'] ?? '';
    $endDate = $data['endDate'] ?? '';
} else {
    $userId = $_GET['userId'] ?? '';
    $startDate = $_GET['startDate'] ?? '';
    $endDate = $_GET['endDate'] ?? '';
}

if (empty($userId)) {
    apiRespond(400, ['status' => 'error', 'error' => 'Missing userId']);
}

// Set default date range if not provided
if (empty($startDate) || empty($endDate)) {
    $endDate = date('Y-m-d');
    $startDate = date('Y-m-d', strtotime('-30 days'));
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
    $attendanceRecords = [];
    
    // Get attendance history using driver_id
    if ($driverId && !empty($driverId)) {
        $stmt = $conn->prepare("
            SELECT id, driver_id, plant_id, vehicle_id, assignment_id, 
                   in_time, out_time, notes, approval_status, source
            FROM attendance 
            WHERE driver_id = ? 
            AND DATE(in_time) BETWEEN ? AND ?
            ORDER BY in_time DESC
        ");
        $stmt->bind_param("iss", $driverId, $startDate, $endDate);
        $stmt->execute();
        $result = $stmt->get_result();
        
        while ($row = $result->fetch_assoc()) {
            $attendanceRecords[] = [
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
        }
        $stmt->close();
    }
    
    // Get attendance history using NULL driver_id and user_id in notes (supervisors)
    $supervisorPattern = "SUPERVISOR_USER_ID:$userId%";
    $stmt = $conn->prepare("
        SELECT id, driver_id, plant_id, vehicle_id, assignment_id, 
               in_time, out_time, notes, approval_status, source
        FROM attendance 
        WHERE driver_id IS NULL 
        AND notes LIKE ? 
        AND DATE(in_time) BETWEEN ? AND ?
        ORDER BY in_time DESC
    ");
    $stmt->bind_param("sss", $supervisorPattern, $startDate, $endDate);
    $stmt->execute();
    $result = $stmt->get_result();
    
    while ($row = $result->fetch_assoc()) {
        $attendanceRecords[] = [
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
    }
    $stmt->close();
    
    // Sort all records by in_time descending
    usort($attendanceRecords, function($a, $b) {
        return strtotime($b['in_time']) - strtotime($a['in_time']);
    });
    
    // Calculate statistics
    $totalRecords = count($attendanceRecords);
    $openRecords = array_filter($attendanceRecords, function($record) {
        return $record['out_time'] === null;
    });
    $closedRecords = array_filter($attendanceRecords, function($record) {
        return $record['out_time'] !== null;
    });
    
    // Calculate total working time
    $totalWorkingMinutes = 0;
    foreach ($closedRecords as $record) {
        if ($record['in_time'] && $record['out_time']) {
            $inTime = new DateTime($record['in_time']);
            $outTime = new DateTime($record['out_time']);
            $diff = $outTime->diff($inTime);
            $totalWorkingMinutes += ($diff->h * 60) + $diff->i;
        }
    }
    
    $totalWorkingHours = round($totalWorkingMinutes / 60, 2);
    
    apiRespond(200, [
        'status' => 'ok',
        'user_id' => $userId,
        'driver_id' => $driverId,
        'username' => $userData['username'],
        'full_name' => $userData['full_name'],
        'role' => $userData['role'],
        'date_range' => [
            'start_date' => $startDate,
            'end_date' => $endDate,
        ],
        'statistics' => [
            'total_records' => $totalRecords,
            'open_records' => count($openRecords),
            'closed_records' => count($closedRecords),
            'total_working_hours' => $totalWorkingHours,
        ],
        'attendance_records' => $attendanceRecords,
        'message' => "Found $totalRecords attendance records for the specified period"
    ]);
    
} catch (Exception $e) {
    apiRespond(500, [
        'status' => 'error', 
        'error' => $e->getMessage()
    ]);
}
?>
