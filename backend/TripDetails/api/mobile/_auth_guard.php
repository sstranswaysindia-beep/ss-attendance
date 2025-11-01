<?php
declare(strict_types=1);

// Bootstrap should already be loaded by the caller, but ensure the session exists.
if (!defined('TD_MOBILE_ROLE')) {
    require __DIR__ . '/bootstrap.php';
}

$userId   = defined('TD_MOBILE_USER_ID') ? TD_MOBILE_USER_ID : null;
$driverId = defined('TD_MOBILE_DRIVER_ID') ? TD_MOBILE_DRIVER_ID : null;

$hasIdentity =
    (is_int($userId)   && $userId   > 0) ||
    (is_int($driverId) && $driverId > 0);

if (!$hasIdentity) {
    if (function_exists('ob_get_level')) {
        while (ob_get_level() > 0) {
            @ob_end_clean();
        }
    }

    http_response_code(401);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, private');

    echo json_encode([
        'ok'    => false,
        'error' => 'Unauthorized',
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

