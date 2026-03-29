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

$userId   = apiSanitizeInt($data['user_id'] ?? null);
$userRole = trim($data['user_role'] ?? 'driver');
$plantId  = apiSanitizeInt($data['plant_id'] ?? null);
$vehicleId = apiSanitizeInt($data['vehicle_id'] ?? null);
$dateFrom = trim($data['date_from'] ?? '');
$dateTo   = trim($data['date_to'] ?? '');

if (!$userId || $userId <= 0) {
    apiRespond(400, ['status' => 'error', 'error' => 'user_id is required.']);
}

// ── Ensure table exists ──────────────────────────────────────────────────
$tableCheck = $conn->query("SHOW TABLES LIKE 'trip_sheets'");
if ($tableCheck->num_rows === 0) {
    apiRespond(200, ['status' => 'ok', 'records' => []]);
}

// ── Build query ──────────────────────────────────────────────────────────
$conditions = [];
$params     = [];
$types      = '';

// Role-based filtering: driver sees own records; supervisor sees all
if ($userRole === 'driver') {
    $conditions[] = 'user_id = ?';
    $params[]     = $userId;
    $types       .= 'i';
}

if ($plantId && $plantId > 0) {
    $conditions[] = 'plant_id = ?';
    $params[]     = $plantId;
    $types       .= 'i';
}

if ($vehicleId && $vehicleId > 0) {
    $conditions[] = 'vehicle_id = ?';
    $params[]     = $vehicleId;
    $types       .= 'i';
}

if ($dateFrom !== '') {
    $conditions[] = 'DATE(created_at) >= ?';
    $params[]     = $dateFrom;
    $types       .= 's';
}

if ($dateTo !== '') {
    $conditions[] = 'DATE(created_at) <= ?';
    $params[]     = $dateTo;
    $types       .= 's';
}

$where = '';
if (!empty($conditions)) {
    $where = 'WHERE ' . implode(' AND ', $conditions);
}

$sql = "SELECT id, user_id, driver_id, plant_id, plant_name, vehicle_id, vehicle_number,
               user_role, image_path, notes, created_at
        FROM trip_sheets
        $where
        ORDER BY created_at DESC
        LIMIT 200";

try {
    $stmt = $conn->prepare($sql);
    if (!empty($params)) {
        $stmt->bind_param($types, ...$params);
    }
    $stmt->execute();
    $result = $stmt->get_result();

    $records = [];
    $baseUrl = 'https://sstranswaysindia.com';

    while ($row = $result->fetch_assoc()) {
        $records[] = [
            'id'             => (int) $row['id'],
            'user_id'        => (int) $row['user_id'],
            'driver_id'      => $row['driver_id'] !== null ? (int) $row['driver_id'] : null,
            'plant_id'       => (int) $row['plant_id'],
            'plant_name'     => $row['plant_name'],
            'vehicle_id'     => (int) $row['vehicle_id'],
            'vehicle_number' => $row['vehicle_number'],
            'user_role'      => $row['user_role'],
            'image_url'      => $baseUrl . $row['image_path'],
            'notes'          => $row['notes'],
            'created_at'     => $row['created_at'],
        ];
    }
    $stmt->close();

    apiRespond(200, [
        'status'  => 'ok',
        'records' => $records,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
