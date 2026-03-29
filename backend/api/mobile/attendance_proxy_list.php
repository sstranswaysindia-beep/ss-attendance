<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    apiRespond(405, ['status' => 'error', 'error' => 'Method not allowed']);
}

require __DIR__ . '/common.php';

$supervisorUserId = apiSanitizeInt($_GET['supervisorUserId'] ?? null);
$plantFilter = apiSanitizeInt($_GET['plantId'] ?? null);
$attendanceDateRaw = trim((string) ($_GET['date'] ?? ''));

if (!$supervisorUserId) {
    apiRespond(400, ['status' => 'error', 'error' => 'supervisorUserId is required']);
}

$attendanceDate = date('Y-m-d');
if ($attendanceDateRaw !== '') {
    $parsedDate = DateTime::createFromFormat('Y-m-d', $attendanceDateRaw);
    $dateErrors = DateTime::getLastErrors();
    if (
        !$parsedDate ||
        ($dateErrors !== false && (($dateErrors['warning_count'] ?? 0) > 0 || ($dateErrors['error_count'] ?? 0) > 0))
    ) {
        apiRespond(400, ['status' => 'error', 'error' => 'date must be in YYYY-MM-DD format']);
    }
    $attendanceDate = $parsedDate->format('Y-m-d');
}

try {
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

    $plantIds = [];
    $plantNames = [];

    // Direct supervision mapping
    $directStmt = $conn->prepare('SELECT id, plant_name FROM plants WHERE supervisor_user_id = ?');
    if ($directStmt) {
        $directStmt->bind_param('i', $supervisorUserId);
        $directStmt->execute();
        $directResult = $directStmt->get_result();
        while ($row = $directResult->fetch_assoc()) {
            $pid = (int)$row['id'];
            $plantIds[$pid] = true;
            $plantNames[$pid] = $row['plant_name'] ?? '';
        }
        $directStmt->close();
    }

    // Additional mapped plants
    $linkedStmt = $conn->prepare(
        'SELECT p.id, p.plant_name
           FROM supervisor_plants sp
           JOIN plants p ON p.id = sp.plant_id
          WHERE sp.user_id = ?
          ORDER BY p.plant_name ASC'
    );
    if ($linkedStmt) {
        $linkedStmt->bind_param('i', $supervisorUserId);
        $linkedStmt->execute();
        $linkedResult = $linkedStmt->get_result();
        while ($row = $linkedResult->fetch_assoc()) {
            $pid = (int)$row['id'];
            $plantIds[$pid] = true;
            $plantNames[$pid] = $row['plant_name'] ?? '';
        }
        $linkedStmt->close();
    }

    $accessiblePlantIdList = array_keys($plantIds);
    sort($accessiblePlantIdList);

    if ($plantFilter !== null) {
        if (!isset($plantIds[$plantFilter])) {
            apiRespond(403, ['status' => 'error', 'error' => 'You do not supervise this plant']);
        }
        $plantIds = [$plantFilter => true];
    }

    if (empty($plantIds)) {
        apiRespond(200, [
            'status' => 'ok',
            'employees' => [],
            'plants' => [],
            'generatedAt' => gmdate('c'),
        ]);
    }

    $plantIdList = array_keys($plantIds);
    sort($plantIdList);

    $placeholders = implode(',', array_fill(0, count($plantIdList), '?'));

    $sql = "
        SELECT
            u.id AS user_id,
            u.username,
            u.full_name,
            u.proxy_enabled,
            d.id AS driver_id,
            d.name AS driver_name,
            COALESCE(d.role, 'driver') AS driver_role,
            d.status AS driver_status,
            d.plant_id,
            COALESCE(p.plant_name, '') AS plant_name,
            selected_attendance.in_time AS last_in_time,
            selected_attendance.out_time AS last_out_time
        FROM users u
        JOIN drivers d ON d.id = u.driver_id
        LEFT JOIN plants p ON p.id = d.plant_id
        LEFT JOIN attendance AS selected_attendance
            ON selected_attendance.id = (
                SELECT a1.id
                FROM attendance a1
                WHERE a1.driver_id = d.id
                  AND (
                    (a1.in_time IS NOT NULL AND DATE(a1.in_time) = ?)
                    OR (a1.out_time IS NOT NULL AND DATE(a1.out_time) = ?)
                  )
                ORDER BY
                    COALESCE(a1.out_time, a1.in_time) DESC,
                    a1.in_time DESC,
                    a1.id DESC
                LIMIT 1
            )
        WHERE u.proxy_enabled = 'Y'
          AND d.status = 'Active'
          AND d.plant_id IN ($placeholders)
        ORDER BY p.plant_name ASC, d.name ASC
    ";

    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        throw new RuntimeException('Failed to prepare proxy list query: ' . $conn->error);
    }

    $types = 'ss' . str_repeat('i', count($plantIdList));
    $params = array_merge([$attendanceDate, $attendanceDate], $plantIdList);
    apiBindParams($stmt, $types, $params);

    $stmt->execute();
    $result = $stmt->get_result();

    $employees = [];
    while ($row = $result->fetch_assoc()) {
        $driverId = (int)$row['driver_id'];
        $plantId = isset($row['plant_id']) ? (int)$row['plant_id'] : null;
        $lastIn = $row['last_in_time'] ?? null;
        $lastOut = $row['last_out_time'] ?? null;
        $hasOpenShift = $lastIn !== null && ($lastOut === null || $lastOut === '');

        $employees[] = [
            'userId' => (int)$row['user_id'],
            'driverId' => $driverId,
            'username' => $row['username'],
            'fullName' => $row['full_name'] ?? $row['driver_name'],
            'driverName' => $row['driver_name'],
            'driverRole' => $row['driver_role'],
            'plantId' => $plantId,
            'plantName' => $row['plant_name'],
            'lastCheckIn' => $lastIn,
            'lastCheckOut' => $lastOut,
            'hasOpenShift' => $hasOpenShift,
        ];
    }
    $stmt->close();

    $plantsPayload = [];
    foreach ($accessiblePlantIdList as $pid) {
        $plantsPayload[] = [
            'plantId' => $pid,
            'plantName' => $plantNames[$pid] ?? ('Plant #' . $pid),
        ];
    }

    apiRespond(200, [
        'status' => 'ok',
        'employees' => $employees,
        'plants' => $plantsPayload,
        'attendanceDate' => $attendanceDate,
        'generatedAt' => gmdate('c'),
        'supervisor' => [
            'userId' => $supervisorUserId,
            'name' => $userRow['full_name'] ?? null,
        ],
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
