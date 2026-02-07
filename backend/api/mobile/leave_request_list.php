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
$limit = apiSanitizeInt($data['limit'] ?? 10) ?? 10;
if ($limit < 1) $limit = 10;
if ($limit > 50) $limit = 50;

if (!$driverId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId is required']);
}

try {
    $stmt = $conn->prepare(
        'SELECT
            id,
            driver_id,
            requested_by_id,
            leave_type,
            leave_start_date,
            leave_end_date,
            total_days,
            leave_duration,
            half_day_session,
            reason,
            status,
            applied_on,
            approved_at,
            manager_remarks
         FROM leave_requests
         WHERE driver_id = ?
         ORDER BY applied_on DESC, id DESC
         LIMIT ?'
    );
    $stmt->bind_param('ii', $driverId, $limit);
    $stmt->execute();
    $result = $stmt->get_result();
    $rows = $result ? $result->fetch_all(MYSQLI_ASSOC) : [];
    $stmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'requests' => $rows,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
