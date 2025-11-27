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

$driverId = apiSanitizeInt($payload['driverId'] ?? $payload['driver_id'] ?? null);
if (!$driverId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driver_id_required']);
}

$rawStatus = $payload['status'] ?? $payload['driverStatus'] ?? $payload['enabled'] ?? null;
if ($rawStatus === null) {
    apiRespond(400, ['status' => 'error', 'error' => 'status_required']);
}

if (is_bool($rawStatus)) {
    $normalizedStatus = $rawStatus ? 'Active' : 'In-Active';
} else {
    $normalized = strtolower(trim((string) $rawStatus));
    if (in_array($normalized, ['active', 'a', '1', 'y', 'yes', 'enabled', 'true'], true)) {
        $normalizedStatus = 'Active';
    } elseif (in_array($normalized, ['inactive', 'in-active', 'in_active', '0', 'n', 'no', 'disabled', 'false'], true)) {
        $normalizedStatus = 'In-Active';
    } else {
        apiRespond(400, ['status' => 'error', 'error' => 'invalid_status']);
    }
}

try {
    $lookup = $conn->prepare('SELECT id, status FROM drivers WHERE id = ? LIMIT 1');
    if (!$lookup) {
        throw new RuntimeException('Failed to prepare lookup statement: ' . $conn->error);
    }
    $lookup->bind_param('i', $driverId);
    $lookup->execute();
    $result = $lookup->get_result();
    $driverRow = $result ? $result->fetch_assoc() : null;
    $lookup->close();

    if (!$driverRow) {
        apiRespond(404, ['status' => 'error', 'error' => 'driver_not_found']);
    }

    if ($normalizedStatus === ($driverRow['status'] ?? '')) {
        apiRespond(200, [
            'status' => 'ok',
            'driverId' => $driverId,
            'driverStatus' => $normalizedStatus,
        ]);
    }

    $update = $conn->prepare(
        'UPDATE drivers
            SET status = ?, updated_at = NOW()
          WHERE id = ?
          LIMIT 1'
    );
    if (!$update) {
        throw new RuntimeException('Failed to prepare update statement: ' . $conn->error);
    }
    $update->bind_param('si', $normalizedStatus, $driverId);
    $update->execute();
    $update->close();

    apiRespond(200, [
        'status' => 'ok',
        'driverId' => $driverId,
        'driverStatus' => $normalizedStatus,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
