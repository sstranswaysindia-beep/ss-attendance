<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/common.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($method === 'POST') {
    apiEnsurePost();
    $payload = apiRequireJson();
    $driverId = apiSanitizeInt($payload['driverId'] ?? $payload['driver_id'] ?? null);
    $plantId = apiSanitizeInt($payload['plantId'] ?? $payload['plant_id'] ?? null);
} else {
    $driverId = apiSanitizeInt($_GET['driverId'] ?? $_GET['driver_id'] ?? null);
    $plantId = apiSanitizeInt($_GET['plantId'] ?? $_GET['plant_id'] ?? null);
}

if (!$driverId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId is required.']);
}

try {
    if ($plantId === null) {
        $plantStmt = $conn->prepare('SELECT plant_id FROM drivers WHERE id = ? LIMIT 1');
        if (!$plantStmt) {
            throw new RuntimeException('Failed to prepare plant lookup: ' . $conn->error);
        }
        $plantStmt->bind_param('i', $driverId);
        $plantStmt->execute();
        $plantRow = $plantStmt->get_result()->fetch_assoc();
        $plantStmt->close();
        if ($plantRow && isset($plantRow['plant_id'])) {
            $plantId = (int) $plantRow['plant_id'];
        }
    }

    $tz = new DateTimeZone('Asia/Kolkata');
    $todayDate = (new DateTimeImmutable('now', $tz))->format('Y-m-d');

    $isAbsent = false;
    $absenceNote = null;
    $markedBy = null;

    if ($plantId !== null) {
        $absenceStmt = $conn->prepare(
            'SELECT supervisor_user_id, note
               FROM supervisor_absence_marks
              WHERE driver_id = ? AND plant_id = ? AND absence_date = ? AND marked_absent = 1
              LIMIT 1'
        );
        if (!$absenceStmt) {
            throw new RuntimeException('Failed to prepare absence lookup: ' . $conn->error);
        }
        $absenceStmt->bind_param('iis', $driverId, $plantId, $todayDate);
        $absenceStmt->execute();
        $absenceRow = $absenceStmt->get_result()->fetch_assoc();
        $absenceStmt->close();

        if ($absenceRow) {
            $isAbsent = true;
            $absenceNote = $absenceRow['note'] ?? null;
            $markedBy = isset($absenceRow['supervisor_user_id'])
                ? (int) $absenceRow['supervisor_user_id']
                : null;
        }
    }

    apiRespond(200, [
        'status' => 'ok',
        'driverId' => $driverId,
        'plantId' => $plantId,
        'absenceDate' => $todayDate,
        'isAbsent' => $isAbsent,
        'note' => $absenceNote,
        'supervisorUserId' => $markedBy,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
