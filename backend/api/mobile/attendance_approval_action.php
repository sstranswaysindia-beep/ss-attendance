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

$supervisorUserId = apiSanitizeInt($data['supervisorUserId'] ?? null);
$attendanceId     = apiSanitizeInt($data['attendanceId'] ?? null);
$actionRaw        = strtolower(trim((string)($data['action'] ?? '')));
$notes            = trim((string)($data['notes'] ?? ''));

if (!$supervisorUserId || !$attendanceId) {
    apiRespond(400, ['status' => 'error', 'error' => 'supervisorUserId and attendanceId are required']);
}

if (!in_array($actionRaw, ['approve', 'reject'], true)) {
    apiRespond(400, ['status' => 'error', 'error' => 'action must be approve or reject']);
}

try {
    $userStmt = $conn->prepare('SELECT driver_id, role FROM users WHERE id = ? LIMIT 1');
    $userStmt->bind_param('i', $supervisorUserId);
    $userStmt->execute();
    $userRow = $userStmt->get_result()->fetch_assoc();
    $userStmt->close();

    if (!$userRow) {
        apiRespond(404, ['status' => 'error', 'error' => 'User not found']);
    }

    $isAdmin = isset($userRow['role']) && $userRow['role'] === 'admin';
    $attendanceRow = null;

    if ($isAdmin) {
        $attendanceStmt = $conn->prepare(
            'SELECT plant_id,
                    approval_status,
                    driver_id,
                    in_time,
                    out_time,
                    notes
               FROM attendance
              WHERE id = ?
              LIMIT 1'
        );
        $attendanceStmt->bind_param('i', $attendanceId);
        $attendanceStmt->execute();
        $attendanceRow = $attendanceStmt->get_result()->fetch_assoc();
        $attendanceStmt->close();

        if (!$attendanceRow) {
            apiRespond(404, ['status' => 'error', 'error' => 'Attendance record not found']);
        }
    } else {
        // Resolve plants for supervisor (user mapping + optional driver mapping).
        $plantIds = [];

        $plantStmt = $conn->prepare('SELECT plant_id FROM supervisor_plants WHERE user_id = ?');
        $plantStmt->bind_param('i', $supervisorUserId);
        $plantStmt->execute();
        $plantResult = $plantStmt->get_result();
        while ($row = $plantResult->fetch_assoc()) {
            if (!empty($row['plant_id'])) {
                $plantIds[] = (int) $row['plant_id'];
            }
        }
        $plantStmt->close();

        if (!empty($userRow['driver_id'])) {
            $driverId = (int) $userRow['driver_id'];
            $driverStmt = $conn->prepare('SELECT supervisor_of_plant_id FROM drivers WHERE id = ? LIMIT 1');
            $driverStmt->bind_param('i', $driverId);
            $driverStmt->execute();
            $driverRow = $driverStmt->get_result()->fetch_assoc();
            $driverStmt->close();
            if ($driverRow && !empty($driverRow['supervisor_of_plant_id'])) {
                $plantIds[] = (int) $driverRow['supervisor_of_plant_id'];
            }
        }

        $plantIds = array_values(array_unique(array_filter($plantIds)));
        if (empty($plantIds)) {
            apiRespond(403, ['status' => 'error', 'error' => 'Supervisor is not assigned to any plants']);
        }

        // Verify attendance belongs to allowed plant.
        $placeholders = implode(',', array_fill(0, count($plantIds), '?'));
        $types = str_repeat('i', count($plantIds) + 1);
        $attendanceStmt = $conn->prepare(
            sprintf(
                'SELECT plant_id,
                        approval_status,
                        driver_id,
                        in_time,
                        out_time,
                        notes
                   FROM attendance
                  WHERE id = ?
                    AND plant_id IN (%s)
                  LIMIT 1',
                $placeholders
            )
        );
        $params = array_merge([$attendanceId], $plantIds);
        apiBindParams($attendanceStmt, $types, $params);
        $attendanceStmt->execute();
        $attendanceRow = $attendanceStmt->get_result()->fetch_assoc();
        $attendanceStmt->close();

        if (!$attendanceRow) {
            apiRespond(404, ['status' => 'error', 'error' => 'Attendance record not found for supervisor plants']);
        }
    }

    $newStatus = $actionRaw === 'approve' ? 'Approved' : 'Rejected';

    $updateStmt = $conn->prepare(
        'UPDATE attendance
            SET approval_status = ?,
                notes = CASE WHEN ? <> "" THEN ? ELSE notes END,
                closed_by_id = ?,
                closed_at = NOW()
          WHERE id = ?'
    );
    $updateStmt->bind_param('sssii', $newStatus, $notes, $notes, $supervisorUserId, $attendanceId);
    $updateStmt->execute();
    $affected = $updateStmt->affected_rows;
    $updateStmt->close();

    if ($affected <= 0) {
        if (isset($attendanceRow['approval_status'])
            && strcasecmp((string) $attendanceRow['approval_status'], $newStatus) === 0
        ) {
            apiRespond(200, [
                'status' => 'ok',
                'attendanceId' => $attendanceId,
                'newStatus' => $newStatus,
                'alreadyUpdated' => true,
            ]);
        }

        apiRespond(500, ['status' => 'error', 'error' => 'Unable to update attendance']);
    }

    $adjustRequestId = null;
    if (!empty($attendanceRow['notes'])
        && preg_match('/#(\d+)/', (string) $attendanceRow['notes'], $match)
    ) {
        $adjustRequestId = (int) $match[1];
    }

    if ($adjustRequestId) {
        $resolutionNote = $notes !== '' ? $notes : '';
        $adjustStmt = $conn->prepare(
            'UPDATE attendance_adjust_requests
                SET status = ?,
                    resolved_by_id = ?,
                    resolved_at = NOW(),
                    resolution_note = NULLIF(?, "")
              WHERE id = ?
              LIMIT 1'
        );
        $adjustStmt->bind_param('sisi', $newStatus, $supervisorUserId, $resolutionNote, $adjustRequestId);
        $adjustStmt->execute();
        $adjustStmt->close();
    }

    apiRespond(200, [
        'status' => 'ok',
        'attendanceId' => $attendanceId,
        'newStatus' => $newStatus,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
