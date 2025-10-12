<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/common.php';

apiEnsurePost();

$data = apiRequireJson();

$driverId   = apiSanitizeInt($data['driverId'] ?? null);
$plantId    = apiSanitizeInt($data['plantId'] ?? null);
$vehicleId  = apiSanitizeInt($data['vehicleId'] ?? null);
$assignmentId = apiSanitizeInt($data['assignmentId'] ?? null);
$actionRaw  = strtolower(trim($data['action'] ?? ''));
$notes      = trim($data['notes'] ?? '');
$source     = trim($data['source'] ?? 'mobile');
$timestamp  = trim($data['timestamp'] ?? '');
$locationJson = $data['locationJson'] ?? null;

if (!$driverId || !$plantId || !$vehicleId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId, plantId, and vehicleId are required']);
}

if (!in_array($actionRaw, ['check_in', 'check_out'], true)) {
    apiRespond(400, ['status' => 'error', 'error' => 'action must be check_in or check_out']);
}

$eventTime = $timestamp !== '' ? strtotime($timestamp) : time();
if ($eventTime === false) {
    apiRespond(400, ['status' => 'error', 'error' => 'Invalid timestamp']);
}
$eventTimeSql = date('Y-m-d H:i:s', $eventTime);

// Check if the ID exists in drivers table, if not check users table (for supervisors without driver_id)
$driverStmt = $conn->prepare('SELECT id FROM drivers WHERE id = ? LIMIT 1');
$driverStmt->bind_param('i', $driverId);
$driverStmt->execute();
$driverExists = $driverStmt->get_result()->fetch_assoc();
$driverStmt->close();

if (!$driverExists) {
    // Check if it's a user ID (for supervisors without driver_id)
    $userStmt = $conn->prepare('SELECT id FROM users WHERE id = ? AND role = "supervisor" LIMIT 1');
    $userStmt->bind_param('i', $driverId);
    $userStmt->execute();
    $userExists = $userStmt->get_result()->fetch_assoc();
    $userStmt->close();
    
    if (!$userExists) {
        apiRespond(404, ['status' => 'error', 'error' => 'Driver or supervisor not found']);
    }
}

if (!$assignmentId) {
    // For drivers, look in assignments table by driver_id
    if ($driverExists) {
        $assignStmt = $conn->prepare('SELECT id FROM assignments WHERE driver_id = ? LIMIT 1');
        $assignStmt->bind_param('i', $driverId);
        $assignStmt->execute();
        $assignRow = $assignStmt->get_result()->fetch_assoc();
        $assignStmt->close();
        if ($assignRow) {
            $assignmentId = (int)$assignRow['id'];
        }
    }
    // For supervisors without driver_id, we don't need assignment lookup
}

$locationJsonValue = null;
if ($locationJson !== null) {
    if (is_array($locationJson)) {
        $locationJsonValue = json_encode($locationJson, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    } elseif (is_string($locationJson)) {
        $locationJsonValue = $locationJson;
    }
}

try {
    if ($actionRaw === 'check_in') {
        // Check for existing open attendance record
        if ($driverExists) {
            // For drivers, check by driver_id
            $openStmt = $conn->prepare('SELECT id FROM attendance WHERE driver_id = ? AND out_time IS NULL ORDER BY in_time DESC LIMIT 1');
            $openStmt->bind_param('i', $driverId);
        } else {
            // For supervisors without driver_id, check by NULL driver_id and user_id in notes field
            $supervisorUserIdPattern = "SUPERVISOR_USER_ID:$driverId%";
            $openStmt = $conn->prepare('SELECT id FROM attendance WHERE driver_id IS NULL AND notes LIKE ? AND out_time IS NULL ORDER BY in_time DESC LIMIT 1');
            $openStmt->bind_param('s', $supervisorUserIdPattern);
        }
        
        $openStmt->execute();
        if ($openStmt->get_result()->fetch_assoc()) {
            $openStmt->close();
            apiRespond(409, ['status' => 'error', 'error' => 'User already has an open attendance record']);
        }
        $openStmt->close();

        // Get custom path and filename from request if provided
        $photoPath = $_POST['photo_path'] ?? null;
        $photoFilename = $_POST['photo_filename'] ?? null;
        
        $photoUrl = apiSaveUploadedFile('photo', $driverId, 'attendance_in', $photoPath, $photoFilename);

        // For supervisors without driver_id, use NULL instead of user ID
        $attendanceDriverId = $driverExists ? $driverId : null;
        
        // Set approval status based on user type
        $pendingStatus = 'Pending'; // Default
        $approverUserId = null;
        $approverRole = null;
        
        if ($driverExists) {
            // Check if this driver is actually a supervisor with driver_id
            $userStmt = $conn->prepare('SELECT id, role FROM users WHERE driver_id = ? AND role = "supervisor" LIMIT 1');
            $userStmt->bind_param('i', $driverId);
            $userStmt->execute();
            $userData = $userStmt->get_result()->fetch_assoc();
            $userStmt->close();
            
            if ($userData) {
                // This is a supervisor with driver_id - check approval workflow
                $workflowStmt = $conn->prepare("
                    SELECT approver_user_id, approver_role 
                    FROM attendance_approval_workflow 
                    WHERE user_id = ? AND user_type = 'supervisor_with_driver_id'
                ");
                $workflowStmt->bind_param('i', $userData['id']);
                $workflowStmt->execute();
                $workflow = $workflowStmt->get_result()->fetch_assoc();
                $workflowStmt->close();
                
                if ($workflow) {
                    $approverUserId = $workflow['approver_user_id'];
                    $approverRole = $workflow['approver_role'];
                    error_log("DEBUG: Supervisor with driver_id (User ID: {$userData['id']}, Driver ID: $driverId) - Routing to approver: User ID $approverUserId, Role: $approverRole");
                } else {
                    error_log("DEBUG: Supervisor with driver_id (User ID: {$userData['id']}, Driver ID: $driverId) - No workflow found, using default");
                }
            } else {
                // Regular driver - no special approval routing
                error_log("DEBUG: Regular driver (Driver ID: $driverId) - Using default approval");
            }
        } else {
            // For supervisors without driver_id, check approval workflow
            $workflowStmt = $conn->prepare("
                SELECT approver_user_id, approver_role 
                FROM attendance_approval_workflow 
                WHERE user_id = ? AND user_type = 'supervisor_without_driver_id'
            ");
            $workflowStmt->bind_param('i', $driverId);
            $workflowStmt->execute();
            $workflow = $workflowStmt->get_result()->fetch_assoc();
            $workflowStmt->close();
            
            if ($workflow) {
                $approverUserId = $workflow['approver_user_id'];
                $approverRole = $workflow['approver_role'];
                error_log("DEBUG: Supervisor without driver_id (User ID: $driverId) - Routing to approver: User ID $approverUserId, Role: $approverRole");
            } else {
                error_log("DEBUG: Supervisor without driver_id (User ID: $driverId) - No workflow found, using default");
            }
        }
        
        // Use different SQL based on whether driver_id is NULL or not
        if ($attendanceDriverId === null) {
            // For supervisors without driver_id, store user_id in notes field for tracking
            $supervisorNotes = "SUPERVISOR_USER_ID:$driverId" . ($notes ? " | $notes" : "");
            
            $insertStmt = $conn->prepare(
                'INSERT INTO attendance (
                    driver_id,
                    plant_id,
                    vehicle_id,
                    assignment_id,
                    in_time,
                    in_photo_url,
                    notes,
                    source,
                    approval_status,
                    pending_sync,
                    in_location_json
                ) VALUES (NULL, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)'
            );
            $insertStmt->bind_param(
                'iiissssss',
                $plantId,
                $vehicleId,
                $assignmentId,
                $eventTimeSql,
                $photoUrl,
                $supervisorNotes,
                $source,
                $pendingStatus,
                $locationJsonValue
            );
        } else {
            $insertStmt = $conn->prepare(
                'INSERT INTO attendance (
                    driver_id,
                    plant_id,
                    vehicle_id,
                    assignment_id,
                    in_time,
                    in_photo_url,
                    notes,
                    source,
                    approval_status,
                    pending_sync,
                    in_location_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)'
            );
            $insertStmt->bind_param(
                'iiiissssss',
                $attendanceDriverId,
                $plantId,
                $vehicleId,
                $assignmentId,
                $eventTimeSql,
                $photoUrl,
                $notes,
                $source,
                $pendingStatus,
                $locationJsonValue
            );
        }
        $insertStmt->execute();
        $attendanceId = $insertStmt->insert_id;
        $insertStmt->close();

        apiRespond(200, [
            'status' => 'ok',
            'attendanceId' => (int)$attendanceId,
            'action' => 'check_in',
            'timestamp' => $eventTimeSql,
            'photo' => $photoUrl,
        ]);
    }

    // Find open attendance record for check-out
    if ($driverExists) {
        // For drivers, check by driver_id
        $openStmt = $conn->prepare('SELECT id FROM attendance WHERE driver_id = ? AND out_time IS NULL ORDER BY in_time DESC LIMIT 1');
        $openStmt->bind_param('i', $driverId);
    } else {
        // For supervisors without driver_id, check by NULL driver_id and user_id in notes field
        $supervisorUserIdPattern = "SUPERVISOR_USER_ID:$driverId%";
        $openStmt = $conn->prepare('SELECT id FROM attendance WHERE driver_id IS NULL AND notes LIKE ? AND out_time IS NULL ORDER BY in_time DESC LIMIT 1');
        $openStmt->bind_param('s', $supervisorUserIdPattern);
    }
    
    $openStmt->execute();
    $openRow = $openStmt->get_result()->fetch_assoc();
    $openStmt->close();

    if (!$openRow) {
        apiRespond(404, ['status' => 'error', 'error' => 'No open attendance record to close']);
    }

    $attendanceId = (int)$openRow['id'];
    
    // Get custom path and filename from request if provided
    $photoPath = $_POST['photo_path'] ?? null;
    $photoFilename = $_POST['photo_filename'] ?? null;
    
    $photoUrl = apiSaveUploadedFile('photo', $driverId, 'attendance_out', $photoPath, $photoFilename);

    $updateStmt = $conn->prepare(
        'UPDATE attendance
            SET out_time = ?,
                out_photo_url = ?,
                vehicle_id = ?,
                plant_id = ?,
                assignment_id = ?,
                pending_sync = 0,
                out_location_json = ?,
                approval_status = CASE
                    WHEN approval_status IS NULL OR approval_status = "" THEN "Pending"
                    ELSE approval_status
                END,
                notes = CASE WHEN ? <> \'\' THEN ? ELSE notes END,
                source = CASE WHEN ? <> \'\' THEN ? ELSE source END
          WHERE id = ?'
    );
    $updateStmt->bind_param(
        'ssiiisssssi',
        $eventTimeSql,
        $photoUrl,
        $vehicleId,
        $plantId,
        $assignmentId,
        $locationJsonValue,
        $notes,
        $notes,
        $source,
        $source,
        $attendanceId
    );
    $updateStmt->execute();
    $updateStmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'attendanceId' => $attendanceId,
        'action' => 'check_out',
        'timestamp' => $eventTimeSql,
        'photo' => $photoUrl,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
