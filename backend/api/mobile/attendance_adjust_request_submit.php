<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require __DIR__ . '/common.php';

apiEnsurePost();

$data = apiRequireJson();

$driverId       = apiSanitizeInt($data['driverId'] ?? null);
$requestedById  = apiSanitizeInt($data['requestedById'] ?? null);
$proposedInRaw  = trim((string)($data['proposedIn'] ?? ''));
$proposedOutRaw = trim((string)($data['proposedOut'] ?? ''));
$reason         = trim((string)($data['reason'] ?? ''));
$plantId        = apiSanitizeInt($data['plantId'] ?? null);
$vehicleId      = apiSanitizeInt($data['vehicleId'] ?? null);

if (!$driverId || !$requestedById) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId and requestedById are required']);
}

if ($reason === '') {
    apiRespond(400, ['status' => 'error', 'error' => 'reason is required']);
}

try {
    $proposedIn = new DateTime($proposedInRaw);
    $proposedOut = new DateTime($proposedOutRaw);
} catch (Throwable $e) {
    apiRespond(400, ['status' => 'error', 'error' => 'Invalid date/time provided']);
}

if ($proposedOut <= $proposedIn) {
    apiRespond(400, ['status' => 'error', 'error' => 'Out time must be after in time']);
}

$requestDate = $proposedIn->format('Y-m-d');

try {
    // Resolve fallback plant/vehicle
    $assignmentId = null;

    if (!$plantId || !$vehicleId) {
        $driverStmt = $conn->prepare('SELECT plant_id FROM drivers WHERE id = ? LIMIT 1');
        $driverStmt->bind_param('i', $driverId);
        $driverStmt->execute();
        $driverRow = $driverStmt->get_result()->fetch_assoc();
        $driverStmt->close();

        if (!$plantId && $driverRow && !empty($driverRow['plant_id'])) {
            $plantId = (int) $driverRow['plant_id'];
        }

        $assignmentStmt = $conn->prepare(
            'SELECT id, plant_id, vehicle_id
               FROM assignments
              WHERE driver_id = ?
           ORDER BY assigned_date DESC
              LIMIT 1'
        );
        $assignmentStmt->bind_param('i', $driverId);
        $assignmentStmt->execute();
        $assignmentRow = $assignmentStmt->get_result()->fetch_assoc();
        $assignmentStmt->close();

        if (!$plantId && $assignmentRow && !empty($assignmentRow['plant_id'])) {
            $plantId = (int) $assignmentRow['plant_id'];
        }
        if (!$vehicleId && $assignmentRow && !empty($assignmentRow['vehicle_id'])) {
            $vehicleId = (int) $assignmentRow['vehicle_id'];
        }

        $assignmentId = $assignmentRow['id'] ?? null;
    } else {
        $assignmentStmt = $conn->prepare(
            'SELECT id
               FROM assignments
              WHERE driver_id = ?
                AND vehicle_id = ?
           ORDER BY assigned_date DESC
              LIMIT 1'
        );
        $assignmentStmt->bind_param('ii', $driverId, $vehicleId);
        $assignmentStmt->execute();
        $assignmentRow = $assignmentStmt->get_result()->fetch_assoc();
        $assignmentStmt->close();
        $assignmentId = $assignmentRow['id'] ?? null;
    }

    if (!$plantId || !$vehicleId) {
        apiRespond(400, ['status' => 'error', 'error' => 'Plant or vehicle mapping missing for driver']);
    }

    // Avoid duplicate attendance records for the same day
    $existingAttendanceStmt = $conn->prepare(
        'SELECT id
           FROM attendance
          WHERE driver_id = ?
            AND DATE(in_time) = ?
          LIMIT 1'
    );
    $existingAttendanceStmt->bind_param('is', $driverId, $requestDate);
    $existingAttendanceStmt->execute();
    $existingRow = $existingAttendanceStmt->get_result()->fetch_assoc();
    $existingAttendanceStmt->close();

    if ($existingRow) {
        apiRespond(409, ['status' => 'error', 'error' => 'Attendance already exists for the selected date']);
    }

    // Avoid duplicate pending requests for same day
    $duplicateStmt = $conn->prepare(
        'SELECT id
           FROM attendance
          WHERE driver_id = ?
            AND DATE(in_time) = ?
            AND source = "adjust_request"
            AND approval_status IN ("Pending", "Approved")
          LIMIT 1'
    );
    $duplicateStmt->bind_param('is', $driverId, $requestDate);
    $duplicateStmt->execute();
    $duplicateRow = $duplicateStmt->get_result()->fetch_assoc();
    $duplicateStmt->close();

    if ($duplicateRow) {
        apiRespond(409, ['status' => 'error', 'error' => 'An adjustment request already exists for this date']);
    }

    $conn->begin_transaction();

    $notes = mb_substr($reason, 0, 240, 'UTF-8');

    $attendanceStmt = $conn->prepare(
        'INSERT INTO attendance (
             driver_id,
             plant_id,
             vehicle_id,
             assignment_id,
             in_time,
             out_time,
             source,
             approval_status,
             notes
         ) VALUES (?, ?, ?, NULLIF(?, 0), ?, ?, "adjust_request", "Pending", ?)' // phpcs:ignore
    );
    $assignmentIdParam = $assignmentId ? (int) $assignmentId : 0;
    $inTimeStr = $proposedIn->format('Y-m-d H:i:s');
    $outTimeStr = $proposedOut->format('Y-m-d H:i:s');
    $attendanceStmt->bind_param(
        'iiiisss',
        $driverId,
        $plantId,
        $vehicleId,
        $assignmentIdParam,
        $inTimeStr,
        $outTimeStr,
        $notes
    );
    $attendanceStmt->execute();
    $attendanceId = (int) $attendanceStmt->insert_id;
    $attendanceStmt->close();

    $adjustStmt = $conn->prepare(
        'INSERT INTO attendance_adjust_requests (
             driver_id,
             requested_by_id,
             request_date,
             proposed_in,
             proposed_out,
             reason,
             status
         ) VALUES (?, ?, ?, ?, ?, ?, "Pending")'
    );
    $proposedInStr = $proposedIn->format('Y-m-d H:i:s');
    $proposedOutStr = $proposedOut->format('Y-m-d H:i:s');
    $adjustStmt->bind_param(
        'iissss',
        $driverId,
        $requestedById,
        $requestDate,
        $proposedInStr,
        $proposedOutStr,
        $reason
    );
    $adjustStmt->execute();
    $adjustRequestId = (int) $adjustStmt->insert_id;
    $adjustStmt->close();

    $noteStmt = $conn->prepare('UPDATE attendance SET notes = ? WHERE id = ?');
    $noteValue = sprintf('Adjust Request #%d: %s', $adjustRequestId, $notes);
    $noteStmt->bind_param('si', $noteValue, $attendanceId);
    $noteStmt->execute();
    $noteStmt->close();

    $conn->commit();

    apiRespond(200, [
        'status' => 'ok',
        'attendanceId' => $attendanceId,
        'adjustRequestId' => $adjustRequestId,
    ]);
} catch (Throwable $error) {
    if ($conn->in_transaction) {
        $conn->rollback();
    }
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
