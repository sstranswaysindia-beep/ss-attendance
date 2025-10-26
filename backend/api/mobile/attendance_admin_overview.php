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
    http_response_code(405);
    echo json_encode(['status' => 'error', 'error' => 'Method not allowed']);
    exit;
}

require __DIR__ . '/common.php';

$monthParam = $_GET['month'] ?? date('Y-m');
$searchRaw  = isset($_GET['search']) ? trim((string) $_GET['search']) : '';
$plantRaw   = isset($_GET['plantId']) ? trim((string) $_GET['plantId']) : '';
$plantId    = null;
if ($plantRaw !== '') {
    if (ctype_digit($plantRaw)) {
        $plantId = (int) $plantRaw;
    } elseif (in_array(strtolower($plantRaw), ['unassigned', 'none'], true)) {
        $plantId = 'UNASSIGNED';
    }
}

if (!preg_match('/^\d{4}-\d{2}$/', $monthParam)) {
    apiRespond(400, ['status' => 'error', 'error' => 'Invalid month format. Use YYYY-MM.']);
}

try {
    $monthDate = DateTime::createFromFormat('Y-m', $monthParam);
    if (!$monthDate) {
        apiRespond(400, ['status' => 'error', 'error' => 'Unable to parse month.']);
    }

    $startDate = $monthDate->format('Y-m-01');
    $endDate = $monthDate->format('Y-m-t');
    $daysInMonth = (int) $monthDate->format('t');

    // Ensure we can capture longer group concat strings
    $conn->query('SET SESSION group_concat_max_len = 100000');

    $sql = '
        SELECT d.id AS driver_id,
               d.name AS driver_name,
               d.role AS driver_role,
               d.plant_id,
               COALESCE(p.plant_name, "") AS plant_name,
               d.profile_photo_url,
               COUNT(DISTINCT DATE(a.in_time)) AS days_present,
               GROUP_CONCAT(DISTINCT DATE(a.in_time) ORDER BY DATE(a.in_time) SEPARATOR ",") AS worked_dates
          FROM drivers d
     LEFT JOIN attendance a
            ON a.driver_id = d.id
           AND a.approval_status = "Approved"
           AND DATE(a.in_time) BETWEEN ? AND ?
     LEFT JOIN plants p
            ON p.id = d.plant_id
         WHERE d.status = "Active"
    ';

    $types = 'ss';
    $params = [$startDate, $endDate];

    if ($searchRaw !== '') {
        $sql .= ' AND (d.name LIKE ? OR p.plant_name LIKE ?)';
        $searchLike = '%' . $searchRaw . '%';
        $types .= 'ss';
        $params[] = $searchLike;
        $params[] = $searchLike;
    }
    if ($plantId !== null) {
        if ($plantId === 'UNASSIGNED') {
            $sql .= ' AND d.plant_id IS NULL';
        } else {
            $sql .= ' AND d.plant_id = ?';
            $types .= 'i';
            $params[] = $plantId;
        }
    }

    $sql .= '
      GROUP BY d.id, d.name, d.role, d.plant_id, plant_name, d.profile_photo_url
      ORDER BY d.name ASC
    ';

    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        throw new RuntimeException('Failed to prepare statement: ' . $conn->error);
    }

    apiBindParams($stmt, $types, $params);
    $stmt->execute();
    $result = $stmt->get_result();

    $drivers = [];
    while ($row = $result->fetch_assoc()) {
        $rawDates = $row['worked_dates'] ?? '';
        $dates = [];
        if (!empty($rawDates)) {
            foreach (explode(',', $rawDates) as $dateStr) {
                $dateStr = trim($dateStr);
                if ($dateStr !== '') {
                    $dates[] = $dateStr;
                }
            }
        }

        $drivers[] = [
            'driverId' => (int) $row['driver_id'],
            'driverName' => $row['driver_name'],
            'role' => $row['driver_role'] ?? '',
            'plantId' => $row['plant_id'] !== null ? (int) $row['plant_id'] : null,
            'plantName' => $row['plant_name'] ?? '',
            'profilePhoto' => apiBuildProfileUrl($row['profile_photo_url'] ?? null),
            'daysWorked' => (int) $row['days_present'],
            'totalDays' => $daysInMonth,
            'datesWorked' => $dates,
        ];
    }
    $stmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'month' => $monthParam,
        'startDate' => $startDate,
        'endDate' => $endDate,
        'totalDays' => $daysInMonth,
        'driverCount' => count($drivers),
        'search' => $searchRaw,
        'drivers' => $drivers,
        'generatedAt' => (new DateTimeImmutable('now'))->format(DateTimeInterface::ATOM),
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
