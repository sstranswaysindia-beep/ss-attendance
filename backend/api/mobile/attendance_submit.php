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

$driverStmt = $conn->prepare('SELECT id FROM drivers WHERE id = ? LIMIT 1');
$driverStmt->bind_param('i', $driverId);
$driverStmt->execute();
if (!$driverStmt->get_result()->fetch_assoc()) {
    $driverStmt->close();
    apiRespond(404, ['status' => 'error', 'error' => 'Driver not found']);
}
$driverStmt->close();

if (!$assignmentId) {
    $assignStmt = $conn->prepare('SELECT id FROM assignments WHERE driver_id = ? LIMIT 1');
    $assignStmt->bind_param('i', $driverId);
    $assignStmt->execute();
    $assignRow = $assignStmt->get_result()->fetch_assoc();
    $assignStmt->close();
    if ($assignRow) {
        $assignmentId = (int)$assignRow['id'];
    }
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
        $openStmt = $conn->prepare('SELECT id FROM attendance WHERE driver_id = ? AND out_time IS NULL ORDER BY in_time DESC LIMIT 1');
        $openStmt->bind_param('i', $driverId);
        $openStmt->execute();
        if ($openStmt->get_result()->fetch_assoc()) {
            $openStmt->close();
            apiRespond(409, ['status' => 'error', 'error' => 'Driver already has an open attendance record']);
        }
        $openStmt->close();

        // Get custom path and filename from request if provided
        $photoPath = $_POST['photo_path'] ?? null;
        $photoFilename = $_POST['photo_filename'] ?? null;
        
        $photoUrl = apiSaveUploadedFile('photo', $driverId, 'attendance_in', $photoPath, $photoFilename);

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
        $pendingStatus = 'Pending';
        $insertStmt->bind_param(
            'iiiissssss',
            $driverId,
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

    $openStmt = $conn->prepare('SELECT id FROM attendance WHERE driver_id = ? AND out_time IS NULL ORDER BY in_time DESC LIMIT 1');
    $openStmt->bind_param('i', $driverId);
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
