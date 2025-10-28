<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/common.php';

apiEnsurePost();

$data = apiRequireJson();

$supervisorUserId = apiSanitizeInt($data['supervisorUserId'] ?? null);
$targetDriverId   = apiSanitizeInt($data['driverId'] ?? null);
$targetUserId     = apiSanitizeInt($data['userId'] ?? null);
$actionRaw        = strtolower(trim((string)($data['action'] ?? '')));
$notesRaw         = trim((string)($data['notes'] ?? ''));

if (!$supervisorUserId || !$targetDriverId) {
    apiRespond(400, ['status' => 'error', 'error' => 'supervisorUserId and driverId are required']);
}

if (!in_array($actionRaw, ['check_in', 'check_out'], true)) {
    apiRespond(400, ['status' => 'error', 'error' => 'action must be check_in or check_out']);
}

$eventTime = date('Y-m-d H:i:s');

try {
    // Validate supervisor
    $userStmt = $conn->prepare('SELECT role, proxy_enabled, full_name FROM users WHERE id = ? LIMIT 1');
    $userStmt->bind_param('i', $supervisorUserId);
    $userStmt->execute();
    $userRow = $userStmt->get_result()->fetch_assoc();
    $userStmt->close();

    if (!$userRow || strtolower((string)$userRow['role']) !== 'supervisor') {
        apiRespond(403, ['status' => 'error', 'error' => 'User is not authorised for proxy attendance']);
    }
    if (strtoupper((string)($userRow['proxy_enabled'] ?? 'N')) !== 'Y') {
        apiRespond(403, ['status' => 'error', 'error' => 'Proxy attendance is disabled for this supervisor']);
    }
    $supervisorName = $userRow['full_name'] ?? ('Supervisor #' . $supervisorUserId);

    // Determine plants accessible by supervisor
    $plantIds = [];

    $directStmt = $conn->prepare('SELECT id FROM plants WHERE supervisor_user_id = ?');
    if ($directStmt) {
        $directStmt->bind_param('i', $supervisorUserId);
        $directStmt->execute();
        $directResult = $directStmt->get_result();
        while ($row = $directResult->fetch_assoc()) {
            $plantIds[(int)$row['id']] = true;
        }
        $directStmt->close();
    }

    $linkedStmt = $conn->prepare('SELECT plant_id FROM supervisor_plants WHERE user_id = ?');
    if ($linkedStmt) {
        $linkedStmt->bind_param('i', $supervisorUserId);
        $linkedStmt->execute();
        $linkedResult = $linkedStmt->get_result();
        while ($row = $linkedResult->fetch_assoc()) {
            $plantIds[(int)$row['plant_id']] = true;
        }
        $linkedStmt->close();
    }

    if (empty($plantIds)) {
        apiRespond(403, ['status' => 'error', 'error' => 'No plants mapped to supervisor']);
    }

    // Fetch driver + user mapping
    $driverStmt = $conn->prepare(
        'SELECT d.id,
                d.name,
                d.status,
                d.plant_id,
                d.role AS driver_role,
                u.id   AS user_id,
                u.username,
                u.proxy_enabled AS user_proxy_enabled
           FROM drivers d
      LEFT JOIN users u ON u.driver_id = d.id
          WHERE d.id = ?
          LIMIT 1'
    );
    $driverStmt->bind_param('i', $targetDriverId);
    $driverStmt->execute();
    $driverRow = $driverStmt->get_result()->fetch_assoc();
    $driverStmt->close();

    if (!$driverRow) {
        apiRespond(404, ['status' => 'error', 'error' => 'Driver not found']);
    }
    if (strtolower((string)$driverRow['status']) !== 'active') {
        apiRespond(409, ['status' => 'error', 'error' => 'Driver is not active']);
    }

    $driverPlantId = $driverRow['plant_id'] !== null ? (int)$driverRow['plant_id'] : null;
    if ($driverPlantId === null || !isset($plantIds[$driverPlantId])) {
        apiRespond(403, ['status' => 'error', 'error' => 'Driver is not mapped to supervisor plants']);
    }

    $driverUserId = $driverRow['user_id'] !== null ? (int)$driverRow['user_id'] : null;
    if ($targetUserId !== null && $driverUserId !== null && $targetUserId !== $driverUserId) {
        apiRespond(403, ['status' => 'error', 'error' => 'Driver/user mismatch']);
    }

    if ($driverUserId === null) {
        apiRespond(409, ['status' => 'error', 'error' => 'Driver does not have an associated user account']);
    }

    if (strtoupper((string)($driverRow['user_proxy_enabled'] ?? 'N')) !== 'Y') {
        apiRespond(403, ['status' => 'error', 'error' => 'Proxy attendance is disabled for this driver']);
    }

    // Determine current open attendance
    $openStmt = $conn->prepare(
        'SELECT id, plant_id, vehicle_id, assignment_id, notes
           FROM attendance
          WHERE driver_id = ? AND out_time IS NULL
          ORDER BY in_time DESC
          LIMIT 1'
    );
    $openStmt->bind_param('i', $targetDriverId);
    $openStmt->execute();
    $openRow = $openStmt->get_result()->fetch_assoc();
    $openStmt->close();

    $proxyNote = sprintf(
        'Proxy %s by %s (#%d)',
        $actionRaw === 'check_in' ? 'check-in' : 'check-out',
        $supervisorName,
        $supervisorUserId
    );
    $combinedNotes = trim($notesRaw) !== '' ? ($notesRaw . ' | ' . $proxyNote) : $proxyNote;

    if ($actionRaw === 'check_in') {
        if ($openRow) {
            apiRespond(409, ['status' => 'error', 'error' => 'Driver already has an open attendance record']);
        }

        $assignmentStmt = $conn->prepare(
            'SELECT id, plant_id, vehicle_id
               FROM assignments
              WHERE driver_id = ?
              ORDER BY assigned_date DESC
              LIMIT 1'
        );
        $assignmentStmt->bind_param('i', $targetDriverId);
        $assignmentStmt->execute();
        $assignmentRow = $assignmentStmt->get_result()->fetch_assoc();
        $assignmentStmt->close();

        if (!$assignmentRow || empty($assignmentRow['vehicle_id'])) {
            apiRespond(409, [
                'status' => 'error',
                'error' => 'Active assignment with vehicle is required for proxy check-in.',
            ]);
        }

        $assignmentId = (int)$assignmentRow['id'];
        $vehicleId = (int)$assignmentRow['vehicle_id'];
        $plantId = $assignmentRow['plant_id'] !== null
            ? (int)$assignmentRow['plant_id']
            : $driverPlantId;

        if ($plantId === null || !isset($plantIds[$plantId])) {
            apiRespond(403, ['status' => 'error', 'error' => 'Driver assignment is outside supervisor plants']);
        }

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
            ) VALUES (?, ?, ?, ?, ?, NULL, ?, "proxy", "Pending", 0, NULL, 0)'
        );
        if (!$insertStmt) {
            throw new RuntimeException('Failed to prepare proxy insert: ' . $conn->error);
        }

        $insertStmt->bind_param(
            'iiiiss',
            $targetDriverId,
            $plantId,
            $vehicleId,
            $assignmentId,
            $eventTime,
            $combinedNotes
        );
        $insertStmt->execute();
        $attendanceId = $insertStmt->insert_id;
        $insertStmt->close();

        apiRespond(200, [
            'status' => 'ok',
            'attendanceId' => (int)$attendanceId,
            'action' => 'check_in',
            'timestamp' => $eventTime,
        ]);
    }

    // Handle check-out
    if (!$openRow) {
        apiRespond(404, ['status' => 'error', 'error' => 'No open attendance record to close']);
    }

    $existingNotes = trim((string)($openRow['notes'] ?? ''));
    $combined = $existingNotes;
    if ($notesRaw !== '') {
        $combined = $combined !== '' ? ($combined . ' | ' . $notesRaw) : $notesRaw;
    }
    $finalNotes = $combined !== '' ? ($combined . ' | ' . $proxyNote) : $proxyNote;

    $updateStmt = $conn->prepare(
        'UPDATE attendance
            SET out_time = ?,
                out_photo_url = NULL,
                out_location_json = NULL,
                pending_sync = 0,
                notes = ?,
                source = CASE WHEN source IS NULL OR source = \'\' THEN \'proxy\' ELSE source END
          WHERE id = ?'
    );
    if (!$updateStmt) {
        throw new RuntimeException('Failed to prepare proxy checkout update: ' . $conn->error);
    }

    $attendanceId = (int)$openRow['id'];
    $updateStmt->bind_param('ssi', $eventTime, $finalNotes, $attendanceId);
    $updateStmt->execute();
    $updateStmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'attendanceId' => $attendanceId,
        'action' => 'check_out',
        'timestamp' => $eventTime,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
