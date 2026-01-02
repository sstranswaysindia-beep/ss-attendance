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

$driverId = apiSanitizeInt($data['driverId'] ?? $data['driver_id'] ?? null);
if (!$driverId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId is required']);
}

try {
    $stmt = $conn->prepare('SELECT esi_number, uan_number FROM drivers WHERE id = ? LIMIT 1');
    $stmt->bind_param('i', $driverId);
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$row) {
        apiRespond(404, ['status' => 'error', 'error' => 'Driver not found']);
    }

    apiRespond(200, [
        'status' => 'ok',
        'driverId' => (int)$driverId,
        'esiNumber' => $row['esi_number'] ?? null,
        'uanNumber' => $row['uan_number'] ?? null,
    ]);
} catch (Throwable $e) {
    apiRespond(500, ['status' => 'error', 'error' => $e->getMessage()]);
}


