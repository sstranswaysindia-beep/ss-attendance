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

require dirname(__DIR__, 2) . '/backend/api/mobile/common.php';

$from = trim((string)($_GET['from'] ?? date('Y-m-01')));
$to = trim((string)($_GET['to'] ?? date('Y-m-d')));
$statusFilter = trim((string)($_GET['status'] ?? 'All'));
$plantId = apiSanitizeInt($_GET['plantId'] ?? null);

if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $from) || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $to)) {
    apiRespond(400, ['status' => 'error', 'error' => 'from and to must be in YYYY-MM-DD format']);
}

if ($to < $from) {
    apiRespond(400, ['status' => 'error', 'error' => 'to date must be after from date']);
}

$filters = [
    'from' => $from,
    'to' => $to,
    'status' => $statusFilter === '' ? 'All' : $statusFilter,
    'plantId' => $plantId,
];

$conditions = ['t.start_date BETWEEN ? AND ?'];
$types = 'ss';
$params = [$from, $to];

if ($plantId) {
    $conditions[] = 'p.id = ?';
    $types .= 'i';
    $params[] = $plantId;
}

if ($statusFilter !== '' && strcasecmp($statusFilter, 'All') !== 0) {
    $conditions[] = 't.status = ?';
    $types .= 's';
    $params[] = $statusFilter;
}

$whereClause = 'WHERE ' . implode(' AND ', $conditions);

$sql = "
    SELECT
        t.id,
        t.start_date,
        t.end_date,
        t.start_km,
        t.end_km,
        t.status,
        t.note,
        t.gps_lat,
        t.gps_lng,
        v.vehicle_no,
        p.id AS plant_id,
        p.plant_name,
        GROUP_CONCAT(DISTINCT d.name ORDER BY d.name SEPARATOR ', ') AS drivers,
        GROUP_CONCAT(DISTINCT c.customer_name SEPARATOR ', ') AS customers,
        h.name AS helper
    FROM trips t
    JOIN vehicles v ON v.id = t.vehicle_id
    JOIN plants p ON p.id = v.plant_id
    LEFT JOIN trip_drivers td ON td.trip_id = t.id
    LEFT JOIN drivers d ON d.id = td.driver_id
    LEFT JOIN trip_customers c ON c.trip_id = t.id
    LEFT JOIN trip_helper th ON th.trip_id = t.id
    LEFT JOIN drivers h ON h.id = th.helper_id
    $whereClause
    GROUP BY t.id
    ORDER BY t.start_date DESC, t.id DESC
    LIMIT 500
";

$stmt = $conn->prepare($sql);
apiBindParams($stmt, $types, $params);
$stmt->execute();
$result = $stmt->get_result();

$trips = [];
$totalRunKm = 0;
$completedTrips = 0;
$openTrips = 0;

while ($row = $result->fetch_assoc()) {
    $startKm = $row['start_km'];
    $endKm = $row['end_km'];
    $runKm = null;
    if ($startKm !== null && $startKm !== '' && $endKm !== null && $endKm !== '') {
        $runKm = (float)$endKm - (float)$startKm;
        if ($runKm > 0) {
            $totalRunKm += $runKm;
        }
    }

    $status = $row['status'] ?? 'planned';
    if (strcasecmp($status, 'ended') === 0 || strcasecmp($status, 'completed') === 0) {
        $completedTrips++;
    } else {
        $openTrips++;
    }

    $trips[] = [
        'id' => (int)$row['id'],
        'startDate' => $row['start_date'],
        'endDate' => $row['end_date'],
        'plantId' => $row['plant_id'] !== null ? (int)$row['plant_id'] : null,
        'plantName' => $row['plant_name'],
        'vehicleNumber' => $row['vehicle_no'],
        'drivers' => $row['drivers'] ?? '',
        'helper' => $row['helper'],
        'customers' => $row['customers'] ?? '',
        'startKm' => $startKm !== null ? (float)$startKm : null,
        'endKm' => $endKm !== null ? (float)$endKm : null,
        'runKm' => $runKm,
        'status' => $status,
        'note' => $row['note'],
        'gpsLat' => $row['gps_lat'] !== null ? (float)$row['gps_lat'] : null,
        'gpsLng' => $row['gps_lng'] !== null ? (float)$row['gps_lng'] : null,
    ];
}
$stmt->close();

$plantRows = $conn->query('SELECT id, plant_name FROM plants ORDER BY plant_name ASC');
$plants = [];
if ($plantRows) {
    while ($plant = $plantRows->fetch_assoc()) {
        $plants[] = [
            'plantId' => (int)$plant['id'],
            'plantName' => $plant['plant_name'],
        ];
    }
}

$summary = [
    'totalTrips' => count($trips),
    'completedTrips' => $completedTrips,
    'openTrips' => $openTrips,
    'totalRunKm' => $totalRunKm,
];

apiRespond(200, [
    'status' => 'ok',
    'filters' => $filters,
    'summary' => $summary,
    'plants' => $plants,
    'trips' => $trips,
]);
