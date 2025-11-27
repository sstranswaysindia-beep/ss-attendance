<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/common.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

apiEnsurePost();

$payload = apiRequireJson();

$supervisorUserId = apiSanitizeInt($payload['supervisorUserId'] ?? $payload['supervisor_user_id'] ?? null);
$driverId = apiSanitizeInt($payload['driverId'] ?? $payload['driver_id'] ?? null);
$plantId = apiSanitizeInt($payload['plantId'] ?? $payload['plant_id'] ?? null);
$absentRaw = $payload['absent'] ?? $payload['isAbsent'] ?? null;
$note = isset($payload['note']) ? trim((string) $payload['note']) : null;

if (!$supervisorUserId || !$driverId || !$plantId || $absentRaw === null) {
    apiRespond(400, ['status' => 'error', 'error' => 'Missing required parameters.']);
}

$markAbsent = false;
if (is_bool($absentRaw)) {
    $markAbsent = $absentRaw;
} else {
    $normalized = strtolower(trim((string) $absentRaw));
    $markAbsent = in_array($normalized, ['1', 'true', 'yes', 'y', 'absent'], true);
}

$tz = new DateTimeZone('Asia/Kolkata');
$todayDate = (new DateTimeImmutable('now', $tz))->format('Y-m-d');

try {
    // Ensure supervisor has access to the plant.
    $accessStmt = $conn->prepare(
        'SELECT 1 FROM plants WHERE supervisor_user_id = ? AND id = ?
         UNION
         SELECT 1 FROM supervisor_plants WHERE user_id = ? AND plant_id = ?
         LIMIT 1'
    );
    if (!$accessStmt) {
        throw new RuntimeException('Failed to prepare access statement: ' . $conn->error);
    }
    $accessStmt->bind_param('iiii', $supervisorUserId, $plantId, $supervisorUserId, $plantId);
    $accessStmt->execute();
    $hasAccess = $accessStmt->get_result()->num_rows > 0;
    $accessStmt->close();

    if (!$hasAccess) {
        apiRespond(403, ['status' => 'error', 'error' => 'You do not have access to this plant.']);
    }

    // Ensure driver is mapped to the plant.
    $driverStmt = $conn->prepare('SELECT id FROM drivers WHERE id = ? AND plant_id = ? LIMIT 1');
    if (!$driverStmt) {
        throw new RuntimeException('Failed to prepare driver lookup: ' . $conn->error);
    }
    $driverStmt->bind_param('ii', $driverId, $plantId);
    $driverStmt->execute();
    $driverExists = $driverStmt->get_result()->num_rows > 0;
    $driverStmt->close();

    if (!$driverExists) {
        apiRespond(404, ['status' => 'error', 'error' => 'Driver not found for the specified plant.']);
    }

    if ($markAbsent) {
        $insert = $conn->prepare(
            'INSERT INTO supervisor_absence_marks
                (absence_date, driver_id, plant_id, supervisor_user_id, marked_absent, note)
             VALUES (?, ?, ?, ?, 1, NULLIF(?, \'\'))
             ON DUPLICATE KEY UPDATE
                marked_absent = VALUES(marked_absent),
                supervisor_user_id = VALUES(supervisor_user_id),
                note = VALUES(note),
                updated_at = CURRENT_TIMESTAMP'
        );
        if (!$insert) {
            throw new RuntimeException('Failed to prepare absence insert: ' . $conn->error);
        }
        $insert->bind_param('siiis', $todayDate, $driverId, $plantId, $supervisorUserId, $note);
        $insert->execute();
        $insert->close();

        $audit = $conn->prepare(
            'INSERT INTO supervisor_absence_audit
                (absence_mark_id, action, supervisor_user_id, action_note)
             SELECT id, "marked_absent", ?, NULLIF(?, \'\')
               FROM supervisor_absence_marks
              WHERE driver_id = ? AND plant_id = ? AND absence_date = ?
              LIMIT 1'
        );
        if ($audit) {
            $audit->bind_param('isiss', $supervisorUserId, $note, $driverId, $plantId, $todayDate);
            $audit->execute();
            $audit->close();
        }
    } else {
        $update = $conn->prepare(
            'UPDATE supervisor_absence_marks
                SET marked_absent = 0,
                    supervisor_user_id = ?,
                    note = NULLIF(?, \'\'),
                    updated_at = CURRENT_TIMESTAMP
              WHERE driver_id = ? AND plant_id = ? AND absence_date = ?
              LIMIT 1'
        );
        if (!$update) {
            throw new RuntimeException('Failed to prepare absence update: ' . $conn->error);
        }
        $update->bind_param('isiss', $supervisorUserId, $note, $driverId, $plantId, $todayDate);
        $update->execute();
        $affected = $update->affected_rows;
        $update->close();

        if ($affected > 0) {
            $audit = $conn->prepare(
                'INSERT INTO supervisor_absence_audit
                    (absence_mark_id, action, supervisor_user_id, action_note)
                 SELECT id, "cleared", ?, NULLIF(?, \'\')
                   FROM supervisor_absence_marks
                  WHERE driver_id = ? AND plant_id = ? AND absence_date = ?
                  LIMIT 1'
            );
            if ($audit) {
                $audit->bind_param('isiss', $supervisorUserId, $note, $driverId, $plantId, $todayDate);
                $audit->execute();
                $audit->close();
            }
        }
    }

    apiRespond(200, [
        'status' => 'ok',
        'driverId' => $driverId,
        'plantId' => $plantId,
        'absenceDate' => $todayDate,
        'isAbsent' => $markAbsent,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
