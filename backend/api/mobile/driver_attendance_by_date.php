<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/common.php';

apiEnsurePost();

$data = apiRequireJson();
$driverId = apiSanitizeInt($data['driverId'] ?? null);
$from = trim((string)($data['from'] ?? ''));
$to = trim((string)($data['to'] ?? ''));

if (!$driverId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId is required']);
}
if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $from) || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $to)) {
    apiRespond(400, ['status' => 'error', 'error' => 'from/to must be YYYY-MM-DD']);
}

try {
    $sql = "
        SELECT
            CASE
              WHEN a.in_time IS NOT NULL
               AND a.in_time <> ''
               AND a.in_time <> '0000-00-00 00:00:00'
              THEN DATE(a.in_time)
              ELSE DATE(a.out_time)
            END AS day_key,
            MAX(
              CASE
                WHEN a.in_time IS NOT NULL
                 AND a.in_time <> ''
                 AND a.in_time <> '0000-00-00 00:00:00'
                THEN 1 ELSE 0
              END
            ) AS has_in,
            MAX(
              CASE
                WHEN a.out_time IS NOT NULL
                 AND a.out_time <> ''
                 AND a.out_time <> '0000-00-00 00:00:00'
                THEN 1 ELSE 0
              END
            ) AS has_out,
            MIN(
              CASE
                WHEN a.in_time IS NOT NULL
                 AND a.in_time <> ''
                 AND a.in_time <> '0000-00-00 00:00:00'
                THEN a.in_time ELSE NULL
              END
            ) AS first_in,
            MAX(
              CASE
                WHEN a.out_time IS NOT NULL
                 AND a.out_time <> ''
                 AND a.out_time <> '0000-00-00 00:00:00'
                THEN a.out_time ELSE NULL
              END
            ) AS last_out
        FROM attendance a
        WHERE a.driver_id = ?
          AND (
            (a.in_time IS NOT NULL AND a.in_time <> '' AND a.in_time <> '0000-00-00 00:00:00' AND DATE(a.in_time) BETWEEN ? AND ?)
            OR
            (a.out_time IS NOT NULL AND a.out_time <> '' AND a.out_time <> '0000-00-00 00:00:00' AND DATE(a.out_time) BETWEEN ? AND ?)
          )
        GROUP BY day_key
        ORDER BY day_key DESC
    ";

    $stmt = $conn->prepare($sql);
    $stmt->bind_param('issss', $driverId, $from, $to, $from, $to);
    $stmt->execute();
    $rows = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    $byDate = [];
    foreach ($rows as $row) {
        $dateKey = (string)($row['day_key'] ?? '');
        if ($dateKey === '') {
            continue;
        }
        $byDate[$dateKey] = [
            'hasIn' => ((int)($row['has_in'] ?? 0) === 1),
            'hasOut' => ((int)($row['has_out'] ?? 0) === 1),
            'firstIn' => $row['first_in'] ?? null,
            'lastOut' => $row['last_out'] ?? null,
        ];
    }

    apiRespond(200, [
        'status' => 'ok',
        'driverId' => (int)$driverId,
        'from' => $from,
        'to' => $to,
        'byDate' => $byDate,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}

