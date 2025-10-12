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
                COUNT(DISTINCT day_key) AS days_present,
                SEC_TO_TIME(SUM(total_seconds)) AS total_hours,
                TIME_FORMAT(SEC_TO_TIME(AVG(first_in_seconds)), "%H:%i") AS avg_in_time,
                TIME_FORMAT(SEC_TO_TIME(AVG(total_seconds)), "%H:%i") AS avg_hours_per_day
           FROM (
                SELECT DATE_FORMAT(a.in_time, "%Y-%m") AS month_key,
                       DATE(a.in_time) AS day_key,
                       MIN(TIME_TO_SEC(TIME(a.in_time))) AS first_in_seconds,
                       SUM(GREATEST(0, TIMESTAMPDIFF(SECOND, a.in_time, COALESCE(a.out_time, a.in_time)))) AS total_seconds
                  FROM attendance a
                 WHERE a.driver_id = ?
                   AND a.approval_status = "Approved"
              GROUP BY month_key, day_key
           ) daily
       GROUP BY month_key
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
