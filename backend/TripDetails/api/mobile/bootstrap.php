<?php
declare(strict_types=1);

require_once __DIR__ . '/../../../api/mobile/common.php';

$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
if ($origin === '') {
    header('Access-Control-Allow-Origin: *');
} else {
    header('Access-Control-Allow-Origin: ' . $origin);
}

header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Origin, X-Requested-With, Content-Type, Accept, Authorization');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

if (session_status() === PHP_SESSION_NONE) {
    $isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
        || ((int)($_SERVER['SERVER_PORT'] ?? 80) === 443);

    session_name('TDSESSID');
    session_set_cookie_params([
        'lifetime' => 0,
        'path' => '/TripDetails/',
        'domain' => '',
        'secure' => $isHttps,
        'httponly' => true,
        'samesite' => 'Lax',
    ]);

    session_start();
}

$__request = array_merge($_GET ?? [], $_POST ?? []);
if (empty($__request)) {
    $__request = apiRequireJson();
}

$GLOBALS['TD_MOBILE_REQUEST'] = $__request;

if (!function_exists('td_request_value')) {
    function td_request_value(string $key, $default = null) {
        return $GLOBALS['TD_MOBILE_REQUEST'][$key] ?? $default;
    }
}

if (!function_exists('td_has_column')) {
    function td_has_column(string $table, string $column): bool
    {
        global $conn;
        $table = $conn->real_escape_string($table);
        $column = $conn->real_escape_string($column);
        $sql = "SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '{$table}' AND COLUMN_NAME = '{$column}' LIMIT 1";
        $res = $conn->query($sql);
        return $res && $res->num_rows > 0;
    }
}

$roleRaw = strtolower(trim((string)($__request['role'] ?? '')));
$sessionRole = isset($_SESSION['role']) ? strtolower(trim((string)$_SESSION['role'])) : '';
$resolvedRole = $roleRaw !== '' ? $roleRaw : ($sessionRole !== '' ? $sessionRole : 'driver');

$userIdRaw = apiSanitizeInt($__request['userId'] ?? null);
if ($userIdRaw === null && isset($_SESSION['user_id'])) {
    $userIdRaw = apiSanitizeInt($_SESSION['user_id']);
}

$driverIdRaw = apiSanitizeInt($__request['driverId'] ?? null);
if ($driverIdRaw === null && isset($_SESSION['driver_id'])) {
    $driverIdRaw = apiSanitizeInt($_SESSION['driver_id']);
}

define('TD_MOBILE_ROLE', $resolvedRole);
define('TD_MOBILE_USER_ID', $userIdRaw);
define('TD_MOBILE_DRIVER_ID', $driverIdRaw);
