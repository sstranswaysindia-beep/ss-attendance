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

$userId = apiSanitizeInt($payload['userId'] ?? $payload['user_id'] ?? null);
if (!$userId) {
    apiRespond(400, ['status' => 'error', 'error' => 'user_id_required']);
}

$rawFlag = $payload['enabled'] ?? $payload['proxyEnabled'] ?? $payload['proxy'] ?? null;
if ($rawFlag === null) {
    apiRespond(400, ['status' => 'error', 'error' => 'enabled_flag_required']);
}

$enabled = false;
if (is_bool($rawFlag)) {
    $enabled = $rawFlag;
} else {
    $normalized = strtolower(trim((string) $rawFlag));
    $enabled = in_array($normalized, ['y', 'yes', 'true', '1', 'enable', 'enabled'], true);
}

try {
    $lookup = $conn->prepare('SELECT id FROM users WHERE id = ? LIMIT 1');
    if (!$lookup) {
        throw new RuntimeException('Failed to prepare lookup statement: ' . $conn->error);
    }
    $lookup->bind_param('i', $userId);
    $lookup->execute();
    $lookupResult = $lookup->get_result();
    $exists = $lookupResult && $lookupResult->num_rows > 0;
    $lookup->close();

    if (!$exists) {
        apiRespond(404, ['status' => 'error', 'error' => 'user_not_found']);
    }

    $flag = $enabled ? 'Y' : 'N';

    $update = $conn->prepare('UPDATE users SET proxy_enabled = ? WHERE id = ?');
    if (!$update) {
        throw new RuntimeException('Failed to prepare update statement: ' . $conn->error);
    }
    $update->bind_param('si', $flag, $userId);
    $update->execute();
    $update->close();

    apiRespond(200, [
        'status' => 'ok',
        'userId' => $userId,
        'proxyEnabled' => $enabled,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
