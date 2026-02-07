<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/common.php';

function plantAllowsNullVehicle(mysqli $conn, ?int $plantId): bool {
    static $cache = [];
    if ($plantId === null) {
        return false;
    }
    if (array_key_exists($plantId, $cache)) {
        return $cache[$plantId];
    }
    $stmt = $conn->prepare('SELECT plant_name FROM plants WHERE id = ? LIMIT 1');
    if (!$stmt) {
        $cache[$plantId] = false;
        return false;
    }
    $stmt->bind_param('i', $plantId);
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();
    if (!$row) {
        $cache[$plantId] = false;
        return false;
    }
    $name = strtolower(trim((string)($row['plant_name'] ?? '')));
    $cache[$plantId] = $name !== '' && str_contains($name, 'office');
    return $cache[$plantId];
}

function driverAllowsNullVehicle(?string $role): bool {
    if ($role === null) {
        return false;
    }
    $normalized = strtolower(trim($role));
    return $normalized !== '' && str_contains($normalized, 'office');
}

apiEnsurePost();

$data = apiRequireJson();

$logDir = __DIR__ . '/logs';
$logFile = $logDir . '/checkin_out_log.log';
if (!is_dir($logDir)) {
    @mkdir($logDir, 0775, true);
}
function logCheckInOut(string $message, string $logFile): void {
    $timestamp = date('Y-m-d H:i:s');
    error_log("[$timestamp] $message\n", 3, $logFile);
}

$driverId   = apiSanitizeInt($data['driverId'] ?? null);
$plantId    = apiSanitizeInt($data['plantId'] ?? null);
$vehicleId  = apiSanitizeInt($data['vehicleId'] ?? null);
$assignmentId = apiSanitizeInt($data['assignmentId'] ?? null);
$actionRaw  = strtolower(trim($data['action'] ?? ''));
$notes      = trim($data['notes'] ?? '');
$source     = trim($data['source'] ?? 'mobile');
$timestamp  = trim($data['timestamp'] ?? '');
$locationJson = $data['locationJson'] ?? null;
if ($locationJson === null && isset($_POST['location_json'])) {
    $posted = trim((string)$_POST['location_json']);
    if ($posted !== '') {
        $decoded = json_decode($posted, true);
        $locationJson = $decoded ?? $posted;
    }
}

if (!$driverId || !$plantId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId, plantId, and vehicleId are required']);
}

if ($vehicleId !== null && $vehicleId <= 0) {
    $vehicleId = null;
}

$plantAllowsMissingVehicle = plantAllowsNullVehicle($conn, $plantId);

if (!in_array($actionRaw, ['check_in', 'check_out'], true)) {
    apiRespond(400, ['status' => 'error', 'error' => 'action must be check_in or check_out']);
}

$eventTime = $timestamp !== '' ? strtotime($timestamp) : time();
if ($eventTime === false) {
    apiRespond(400, ['status' => 'error', 'error' => 'Invalid timestamp']);
}
$eventTimeSql = date('Y-m-d H:i:s', $eventTime);
$tzNow = new DateTimeZone('Asia/Kolkata');
$todayDate = (new DateTimeImmutable('now', $tzNow))->format('Y-m-d');

logCheckInOut(
    sprintf(
        'start action=%s driverId=%s plantId=%s vehicleId=%s assignmentId=%s timestamp=%s',
        $actionRaw,
        (string) $driverId,
        (string) $plantId,
        (string) $vehicleId,
        $assignmentId === null ? 'null' : (string) $assignmentId,
        $eventTimeSql
    ),
    $logFile
);

// Check if the ID exists in drivers table, if not check users table (for supervisors without driver_id)
$driverStmt = $conn->prepare('SELECT id, role FROM drivers WHERE id = ? LIMIT 1');
$driverStmt->bind_param('i', $driverId);
$driverStmt->execute();
$driverRow = $driverStmt->get_result()->fetch_assoc();
$driverStmt->close();
$driverExists = (bool)$driverRow;
$driverRole = $driverRow['role'] ?? null;
$driverAllowsMissingVehicle = driverAllowsNullVehicle($driverRole);
$userAllowsMissingVehicle = false;

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
    $userAllowsMissingVehicle = true;
}

$allowsMissingVehicle = $plantAllowsMissingVehicle || $driverAllowsMissingVehicle || $userAllowsMissingVehicle;
if (!$vehicleId && !$allowsMissingVehicle) {
    logCheckInOut(
        sprintf(
            'reject_missing_vehicle action=%s driverId=%s plantId=%s vehicleId=%s allowsMissingVehicle=%s',
            $actionRaw,
            (string) $driverId,
            (string) $plantId,
            (string) $vehicleId,
            $allowsMissingVehicle ? 'yes' : 'no'
        ),
        $logFile
    );
    apiRespond(400, ['status' => 'error', 'error' => 'driverId, plantId, and vehicleId are required']);
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

if ($assignmentId) {
    $assignmentCheckStmt = $conn->prepare('SELECT id FROM assignments WHERE id = ? LIMIT 1');
    $assignmentCheckStmt->bind_param('i', $assignmentId);
    $assignmentCheckStmt->execute();
    $assignmentRow = $assignmentCheckStmt->get_result()->fetch_assoc();
    $assignmentCheckStmt->close();
    if (!$assignmentRow) {
        $assignmentId = null;
    }
}

if (!$assignmentId) {
    $assignmentId = null;
}

if ($driverExists) {
    $absenceStmt = $conn->prepare(
        'SELECT 1
           FROM supervisor_absence_marks
          WHERE driver_id = ? AND plant_id = ? AND absence_date = ? AND marked_absent = 1
          LIMIT 1'
    );
    if ($absenceStmt) {
        $absenceStmt->bind_param('iis', $driverId, $plantId, $todayDate);
        $absenceStmt->execute();
        $isAbsentToday = $absenceStmt->get_result()->fetch_assoc() !== null;
        $absenceStmt->close();
        if ($isAbsentToday) {
            apiRespond(423, [
                'status' => 'error',
                'error' => 'Attendance locked for today. Please contact your supervisor.',
            ]);
        }
    }
}

$geofencingEnabled = false;
$locationGeofenceUserRow = null;
if ($driverExists) {
    $geofenceStmt = $conn->prepare('SELECT id, geofencing_enable FROM users WHERE driver_id = ? LIMIT 1');
    if ($geofenceStmt) {
        $geofenceStmt->bind_param('i', $driverId);
        $geofenceStmt->execute();
        $row = $geofenceStmt->get_result()->fetch_assoc();
        $geofenceStmt->close();
        if ($row) {
            $locationGeofenceUserRow = $row;
        }
    }
    if ($locationGeofenceUserRow === null) {
        $fallbackStmt = $conn->prepare('SELECT id, geofencing_enable FROM users WHERE id = ? LIMIT 1');
        if ($fallbackStmt) {
            $fallbackStmt->bind_param('i', $driverId);
            $fallbackStmt->execute();
            $row = $fallbackStmt->get_result()->fetch_assoc();
            $fallbackStmt->close();
            if ($row) {
                $locationGeofenceUserRow = $row;
            }
        }
    }
} else {
    $geofenceStmt = $conn->prepare('SELECT id, geofencing_enable FROM users WHERE id = ? LIMIT 1');
    if ($geofenceStmt) {
        $geofenceStmt->bind_param('i', $driverId);
        $geofenceStmt->execute();
        $row = $geofenceStmt->get_result()->fetch_assoc();
        $geofenceStmt->close();
        if ($row) {
            $locationGeofenceUserRow = $row;
        }
    }
}

if ($locationGeofenceUserRow !== null) {
    $flag = strtoupper(trim((string) ($locationGeofenceUserRow['geofencing_enable'] ?? '')));
    $geofencingEnabled = $flag === 'Y';
}

$locationJsonValue = null;
$locationArray = null;
$locationJsonIsArray = false;
if ($locationJson !== null) {
    if (is_array($locationJson)) {
        $locationArray = $locationJson;
        $locationJsonValue = json_encode($locationJson, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        $locationJsonIsArray = true;
    } elseif (is_string($locationJson)) {
        $locationJsonValue = $locationJson;
        $decodedLocation = json_decode($locationJson, true);
        if (is_array($decodedLocation)) {
            $locationArray = $decodedLocation;
            $locationJsonIsArray = true;
        }
    }
}
if ($locationArray !== null && $locationJsonValue === null) {
    $locationJsonValue = json_encode($locationArray, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    $locationJsonIsArray = true;
}

try {
    if ($actionRaw === 'check_in') {
        $checkInGeofence = geofenceEvaluate($conn, $plantId, $locationArray, $geofencingEnabled);
        if ($checkInGeofence['status'] === 'error') {
            error_log(sprintf(
                'GEOFENCE BLOCK check_in driver=%s plant=%d reason=%s',
                $driverExists ? (string) $driverId : 'user_' . $driverId,
                $plantId,
                $checkInGeofence['message'] ?? 'unknown'
            ));
            apiRespond(422, [
                'status' => 'error',
                'error' => $checkInGeofence['message'] ?? 'Geofence validation failed.',
            ]);
        }
        $outOfGeofenceFlag = $checkInGeofence['out_of_geofence'] ? 1 : 0;
        if ($geofencingEnabled) {
            error_log(sprintf(
                'GEOFENCE check_in driver=%s plant=%d inside=%s',
                $driverExists ? (string) $driverId : 'user_' . $driverId,
                $plantId,
                $outOfGeofenceFlag === 0 ? 'true' : 'false'
            ));
        }

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
                    in_location_json,
                    out_of_geofence
                ) VALUES (NULL, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)'
            );
            $insertStmt->bind_param(
                'iiissssssi',
                $plantId,
                $vehicleId,
                $assignmentId,
                $eventTimeSql,
                $photoUrl,
                $supervisorNotes,
                $source,
                $pendingStatus,
                $locationJsonValue,
                $outOfGeofenceFlag
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
                    in_location_json,
                    out_of_geofence
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)'
            );
            $insertStmt->bind_param(
                'iiiissssssi',
                $attendanceDriverId,
                $plantId,
                $vehicleId,
                $assignmentId,
                $eventTimeSql,
                $photoUrl,
                $notes,
                $source,
                $pendingStatus,
                $locationJsonValue,
                $outOfGeofenceFlag
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

    if (!$openRow && $assignmentId) {
        $fallbackStmt = $conn->prepare('SELECT id FROM attendance WHERE assignment_id = ? AND out_time IS NULL ORDER BY in_time DESC LIMIT 1');
        if ($fallbackStmt) {
            $fallbackStmt->bind_param('i', $assignmentId);
            $fallbackStmt->execute();
            $openRow = $fallbackStmt->get_result()->fetch_assoc();
            $fallbackStmt->close();
            if ($openRow) {
                logCheckInOut(
                    sprintf(
                        'fallback_open_record action=%s driverId=%s assignmentId=%s attendanceId=%s',
                        $actionRaw,
                        (string) $driverId,
                        (string) $assignmentId,
                        (string) $openRow['id']
                    ),
                    $logFile
                );
            } else {
                logCheckInOut(
                    sprintf(
                        'fallback_open_record_none action=%s driverId=%s assignmentId=%s',
                        $actionRaw,
                        (string) $driverId,
                        (string) $assignmentId
                    ),
                    $logFile
                );
            }
        }
    }

    if (!$openRow) {
        logCheckInOut(
            sprintf(
                'no_open_record action=%s driverId=%s plantId=%s vehicleId=%s assignmentId=%s',
                $actionRaw,
                (string) $driverId,
                (string) $plantId,
                (string) $vehicleId,
                $assignmentId === null ? 'null' : (string) $assignmentId
            ),
            $logFile
        );
        apiRespond(404, ['status' => 'error', 'error' => 'No open attendance record to close']);
    }

    $attendanceId = (int)$openRow['id'];
    logCheckInOut(
        sprintf(
            'open_record_found action=%s driverId=%s attendanceId=%s',
            $actionRaw,
            (string) $driverId,
            (string) $attendanceId
        ),
        $logFile
    );
    
    // Get custom path and filename from request if provided
    $photoPath = $_POST['photo_path'] ?? null;
    $photoFilename = $_POST['photo_filename'] ?? null;
    
    $photoUrl = apiSaveUploadedFile('photo', $driverId, 'attendance_out', $photoPath, $photoFilename);

    $checkOutGeofence = geofenceEvaluate($conn, $plantId, $locationArray, $geofencingEnabled);
    if ($checkOutGeofence['status'] === 'error') {
        logCheckInOut(
            sprintf(
                'geofence_block action=%s driverId=%s plantId=%s reason=%s',
                $actionRaw,
                (string) $driverId,
                (string) $plantId,
                (string) ($checkOutGeofence['message'] ?? 'unknown')
            ),
            $logFile
        );
        error_log(sprintf(
            'GEOFENCE BLOCK check_out driver=%s plant=%d reason=%s',
            $driverExists ? (string) $driverId : 'user_' . $driverId,
            $plantId,
            $checkOutGeofence['message'] ?? 'unknown'
        ));
        apiRespond(422, [
            'status' => 'error',
            'error' => $checkOutGeofence['message'] ?? 'Geofence validation failed.',
        ]);
    }
    $checkOutOutOfGeofence = $checkOutGeofence['out_of_geofence'] ? 1 : 0;
    if ($geofencingEnabled) {
        error_log(sprintf(
            'GEOFENCE check_out driver=%s plant=%d inside=%s',
            $driverExists ? (string) $driverId : 'user_' . $driverId,
            $plantId,
            $checkOutOutOfGeofence === 0 ? 'true' : 'false'
        ));
    }

    $updateStmt = $conn->prepare(
        'UPDATE attendance
            SET out_time = ?,
                out_photo_url = ?,
                vehicle_id = ?,
                plant_id = ?,
                assignment_id = ?,
                pending_sync = 0,
                out_location_json = ?,
                out_of_geofence = CASE WHEN ? = 1 THEN 1 ELSE out_of_geofence END,
                approval_status = CASE
                    WHEN approval_status IS NULL OR approval_status = "" THEN "Pending"
                    ELSE approval_status
                END,
                notes = CASE WHEN ? <> \'\' THEN ? ELSE notes END,
                source = CASE WHEN ? <> \'\' THEN ? ELSE source END
          WHERE id = ?'
    );
    $updateStmt->bind_param(
        'ssiiisissssi',
        $eventTimeSql,
        $photoUrl,
        $vehicleId,
        $plantId,
        $assignmentId,
        $locationJsonValue,
        $checkOutOutOfGeofence,
        $notes,
        $notes,
        $source,
        $source,
        $attendanceId
    );
    $updateStmt->execute();
    $updateStmt->close();

    logCheckInOut(
        sprintf(
            'success action=%s driverId=%s plantId=%s vehicleId=%s attendanceId=%s',
            $actionRaw,
            (string) $driverId,
            (string) $plantId,
            (string) $vehicleId,
            (string) $attendanceId
        ),
        $logFile
    );

    apiRespond(200, [
        'status' => 'ok',
        'attendanceId' => $attendanceId,
        'action' => 'check_out',
        'timestamp' => $eventTimeSql,
        'photo' => $photoUrl,
    ]);
} catch (Throwable $error) {
    logCheckInOut(
        sprintf(
            'error action=%s driverId=%s plantId=%s vehicleId=%s message=%s',
            $actionRaw,
            (string) $driverId,
            (string) $plantId,
            (string) $vehicleId,
            $error->getMessage()
        ),
        $logFile
    );
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
