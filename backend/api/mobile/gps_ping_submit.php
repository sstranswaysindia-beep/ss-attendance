<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/common.php';

apiEnsurePost();

$data = apiRequireJson();

$driverId  = apiSanitizeInt($data['driverId'] ?? null);
$plantId   = apiSanitizeInt($data['plantId'] ?? null);
$lat       = isset($data['lat']) ? (float)$data['lat'] : null;
$lng       = isset($data['lng']) ? (float)$data['lng'] : null;
$accuracy  = isset($data['accuracy']) ? (float)$data['accuracy'] : null;
$source    = trim((string)($data['source'] ?? 'mobile_fg'));
$captured  = trim((string)($data['capturedAt'] ?? ''));

if (!$driverId || $lat === null || $lng === null) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId, lat, and lng are required']);
}

if (!in_array($source, ['mobile_fg', 'mobile_bg', 'device'], true)) {
    $source = 'mobile_fg';
}

$capturedAt = $captured !== '' ? strtotime($captured) : time();
if ($capturedAt === false) {
    apiRespond(400, ['status' => 'error', 'error' => 'Invalid capturedAt timestamp']);
}
$capturedAtSql = date('Y-m-d H:i:s', $capturedAt);

try {
    $stmt = $conn->prepare(
        "INSERT INTO gps_pings (
            driver_id,
            plant_id,
            lat,
            lng,
            accuracy_m,
            captured_at,
            source
        ) VALUES (?, NULLIF(?, 0), ?, ?, NULLIF(?, ''), ?, ?)"
    );

    $plantValue = $plantId ?? 0;
    $accuracyValue = $accuracy !== null ? (string)$accuracy : '';

    $stmt->bind_param(
        'iiddsss',
        $driverId,
        $plantValue,
        $lat,
        $lng,
        $accuracyValue,
        $capturedAtSql,
        $source
    );
    $stmt->execute();
    $stmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'pingId' => $conn->insert_id,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
