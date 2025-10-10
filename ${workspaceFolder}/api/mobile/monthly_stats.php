<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require __DIR__ . '/common.php';

$driverId = apiSanitizeInt($_GET['driverId'] ?? null);
$limit    = apiSanitizeInt($_GET['limit'] ?? 12);

if (!$driverId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId is required']);
}

if ($limit === null || $limit <= 0 || $limit > 24) {
    $limit = 12;
}

try {
    $stmt = $conn->prepare(
        'SELECT month_key,
                days_present,
                total_hours,
                avg_in_time,
                avg_hours_per_day
           FROM v_driver_monthly_stats
          WHERE driver_id = ?
       ORDER BY month_key DESC
          LIMIT ?'
    );
    $stmt->bind_param('ii', $driverId, $limit);
    $stmt->execute();
    $result = $stmt->get_result();
    $rows = [];
    while ($row = $result->fetch_assoc()) {
        $rows[] = [
            'month'          => $row['month_key'],
            'daysPresent'    => (int)$row['days_present'],
            'totalHours'     => $row['total_hours'],
            'averageInTime'  => $row['avg_in_time'],
            'averageHours'   => $row['avg_hours_per_day'],
        ];
    }
    $stmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'driverId' => $driverId,
        'limit' => $limit,
        'stats' => $rows,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
