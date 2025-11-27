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
$username = trim((string)($payload['username'] ?? ''));
$deviceId = trim((string)($payload['deviceId'] ?? $payload['device_id'] ?? ''));
$appIdentifier = trim((string)($payload['appIdentifier'] ?? $payload['packageName'] ?? ''));
$platform = strtolower(trim((string)($payload['devicePlatform'] ?? $payload['platform'] ?? '')));
$deviceModel = trim((string)($payload['deviceModel'] ?? ''));
$osVersion = trim((string)($payload['osVersion'] ?? ''));
$appVersion = trim((string)($payload['appVersion'] ?? ''));
$appBuild = trim((string)($payload['appBuild'] ?? ''));
$meta = isset($payload['meta']) && is_array($payload['meta'])
    ? json_encode($payload['meta'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)
    : null;

if (!$userId && $username === '') {
    apiRespond(400, ['status' => 'error', 'error' => 'userId or username is required.']);
}

if ($userId === null && $username !== '') {
    $lookup = $conn->prepare('SELECT id FROM users WHERE username = ? LIMIT 1');
    if (!$lookup) {
        apiRespond(500, ['status' => 'error', 'error' => 'Unable to prepare user lookup.']);
    }
    $lookup->bind_param('s', $username);
    $lookup->execute();
    $userId = $lookup->get_result()->fetch_column() ?: null;
    $lookup->close();
    if ($userId === null) {
        apiRespond(404, ['status' => 'error', 'error' => 'User not found.']);
    }
}

if ($deviceId === '' || $platform === '' || $appIdentifier === '') {
    apiRespond(400, ['status' => 'error', 'error' => 'deviceId, devicePlatform, and appIdentifier are required.']);
}

$validPlatforms = ['android', 'ios', 'web', 'macos', 'windows', 'linux'];
if (!in_array($platform, $validPlatforms, true)) {
    $platform = 'unknown';
}

try {
    $stmt = $conn->prepare(
        'INSERT INTO user_devices
            (user_id, device_id, app_identifier, platform, device_model, os_version, app_version, app_build, meta_json, first_seen_at, last_seen_at)
         VALUES (?, ?, ?, ?, NULLIF(?, \'\'), NULLIF(?, \'\'), NULLIF(?, \'\'), NULLIF(?, \'\'), ?, NOW(), NOW())
         ON DUPLICATE KEY UPDATE
            platform = VALUES(platform),
            device_model = VALUES(device_model),
            os_version = VALUES(os_version),
            app_version = VALUES(app_version),
            app_build = VALUES(app_build),
            meta_json = VALUES(meta_json),
            last_seen_at = NOW()'
    );
    if (!$stmt) {
        throw new RuntimeException('Failed to prepare device sync statement: ' . $conn->error);
    }
    $stmt->bind_param(
        'issssssss',
        $userId,
        $deviceId,
        $appIdentifier,
        $platform,
        $deviceModel,
        $osVersion,
        $appVersion,
        $appBuild,
        $meta
    );
    $stmt->execute();
    $stmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'userId' => $userId,
        'deviceId' => $deviceId,
        'appIdentifier' => $appIdentifier,
        'platform' => $platform,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
