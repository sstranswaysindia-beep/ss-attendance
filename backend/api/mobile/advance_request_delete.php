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

$driverId = apiSanitizeInt($data['driverId'] ?? null);
$requestId = apiSanitizeInt($data['advanceRequestId'] ?? null);

if (!$driverId || !$requestId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId and advanceRequestId are required']);
}

try {
    $stmt = $conn->prepare(
        'DELETE FROM advance_requests WHERE id = ? AND driver_id = ? AND status = "Pending"'
    );
    $stmt->bind_param('ii', $requestId, $driverId);
    $stmt->execute();
    $affected = $stmt->affected_rows;
    $stmt->close();

    if ($affected <= 0) {
        apiRespond(
            409,
            ['status' => 'error', 'error' => 'Only pending advance requests can be deleted']
        );
    }

    apiRespond(200, ['status' => 'ok']);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
