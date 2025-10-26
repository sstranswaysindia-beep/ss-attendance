<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/common.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    apiRespond(405, ['status' => 'error', 'error' => 'Method not allowed']);
}

$plantFilterRaw = $_GET['plantId'] ?? null;

$plantFilter = null;
if ($plantFilterRaw !== null && $plantFilterRaw !== '') {
    if (!is_numeric($plantFilterRaw)) {
        apiRespond(400, ['status' => 'error', 'error' => 'Invalid plantId filter']);
    }
    $plantFilter = (int) $plantFilterRaw;
}

$tz = new DateTimeZone('Asia/Kolkata');
$today = new DateTimeImmutable('now', $tz);
$todayDate = $today->format('Y-m-d');

try {
    $plantIds = [];
    $plantNames = [];

    if ($plantFilter !== null) {
        $stmt = $conn->prepare('SELECT id, plant_name FROM plants WHERE id = ? LIMIT 1');
        if ($stmt) {
            $stmt->bind_param('i', $plantFilter);
            $stmt->execute();
            $result = $stmt->get_result();
            while ($row = $result->fetch_assoc()) {
                $plantIds[(int) $row['id']] = true;
                $plantNames[(int) $row['id']] = $row['plant_name'] ?? '';
            }
            $stmt->close();
        }
    } else {
        $plantResult = $conn->query('SELECT id, plant_name FROM plants ORDER BY plant_name ASC');
        if ($plantResult) {
            while ($row = $plantResult->fetch_assoc()) {
                $plantIds[(int) $row['id']] = true;
                $plantNames[(int) $row['id']] = $row['plant_name'] ?? '';
            }
            $plantResult->free();
        }
    }

    if (empty($plantIds)) {
        apiRespond(200, [
            'status' => 'ok',
            'date' => $todayDate,
            'plants' => [],
        ]);
    }

    $plantIdList = array_keys($plantIds);
    sort($plantIdList);

    $placeholders = implode(',', array_fill(0, count($plantIdList), '?'));
    $query = "
        SELECT d.id AS driver_id,
               d.name AS driver_name,
               d.profile_photo_url,
               d.role AS driver_role,
               d.plant_id,
               COALESCE(p.plant_name, '') AS plant_name,
               in_data.first_check_in,
               in_data.last_check_in,
               in_data.last_check_out AS in_scope_last_checkout,
               out_data.last_check_out
          FROM drivers d
     LEFT JOIN plants p ON p.id = d.plant_id
     LEFT JOIN (
            SELECT driver_id,
                   MIN(in_time) AS first_check_in,
                   MAX(in_time) AS last_check_in,
                   MAX(out_time) AS last_check_out
              FROM attendance
             WHERE in_time IS NOT NULL
               AND DATE(in_time) = ?
               AND approval_status IN ('Pending', 'Approved')
             GROUP BY driver_id
        ) AS in_data ON in_data.driver_id = d.id
     LEFT JOIN (
            SELECT driver_id,
                   MAX(out_time) AS last_check_out
              FROM attendance
             WHERE out_time IS NOT NULL
               AND DATE(out_time) = ?
               AND approval_status IN ('Pending', 'Approved')
             GROUP BY driver_id
        ) AS out_data ON out_data.driver_id = d.id
         WHERE d.status = 'Active'
";

    if (!empty($plantIdList)) {
        $query .= " AND d.plant_id IN ($placeholders)";
    }

    $query .= ' ORDER BY p.plant_name ASC, d.name ASC';

    $stmt = $conn->prepare($query);
    if (!$stmt) {
        throw new RuntimeException('Failed to prepare attendance query: ' . $conn->error);
    }

    $types = 'ss' . str_repeat('i', count($plantIdList));
    $params = [$todayDate, $todayDate, ...$plantIdList];
    apiBindParams($stmt, $types, $params);

    $stmt->execute();
    $result = $stmt->get_result();

    $plantBuckets = [];
    foreach ($plantIdList as $pid) {
        $plantBuckets[$pid] = [
            'plantId' => $pid,
            'plantName' => $plantNames[$pid] ?? 'Plant #' . $pid,
            'drivers' => [],
        ];
    }

    while ($row = $result->fetch_assoc()) {
        $plantId = isset($row['plant_id']) ? (int) $row['plant_id'] : null;
        if ($plantId === null || !isset($plantBuckets[$plantId])) {
            continue;
        }

        $firstCheckIn = $row['first_check_in'] ?? null;
        $lastCheckOut = $row['last_check_out'] ?? null;
        if (!$lastCheckOut && isset($row['in_scope_last_checkout'])) {
            $lastCheckOut = $row['in_scope_last_checkout'];
        }

        $hasCheckIn = $firstCheckIn !== null && $firstCheckIn !== '';
        $hasCheckOut = $lastCheckOut !== null && $lastCheckOut !== '';

        $plantBuckets[$plantId]['drivers'][] = [
            'driverId' => (int) $row['driver_id'],
            'driverName' => $row['driver_name'] ?? '',
            'profilePhoto' => apiBuildProfileUrl($row['profile_photo_url'] ?? null),
            'role' => $row['driver_role'] ?? null,
            'hasCheckIn' => $hasCheckIn,
            'hasCheckOut' => $hasCheckOut,
            'checkInTime' => $firstCheckIn,
            'checkOutTime' => $lastCheckOut,
        ];
    }
    $stmt->close();

    $plantsPayload = array_values(array_map(
        static function (array $plant): array {
            return $plant;
        },
        $plantBuckets
    ));

    apiRespond(200, [
        'status' => 'ok',
        'date' => $todayDate,
        'plants' => $plantsPayload,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
