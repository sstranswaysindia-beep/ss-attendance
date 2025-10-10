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
$month    = trim($_GET['month'] ?? date('Y-m'));
$limit    = apiSanitizeInt($_GET['limit'] ?? null);

if (!$driverId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId is required']);
}

if (!preg_match('/^\d{4}-\d{2}$/', $month)) {
    apiRespond(400, ['status' => 'error', 'error' => 'month must be in YYYY-MM format']);
}

try {
    $start = DateTime::createFromFormat('Y-m-d', $month . '-01');
    if (!$start) {
        throw new RuntimeException('Invalid month format');
    }
    $end = clone $start;
    $end->modify('+1 month');

    $sql = 'SELECT a.id,
                   a.driver_id,
                   a.plant_id,
                   a.vehicle_id,
                   a.assignment_id,
                   a.in_time,
                   a.out_time,
                   a.in_photo_url,
                   a.out_photo_url,
                   a.approval_status,
                   a.notes,
                   a.pending_sync,
                   a.source,
                   p.plant_name,
                   v.vehicle_no
              FROM attendance a
         LEFT JOIN plants p   ON p.id = a.plant_id
         LEFT JOIN vehicles v ON v.id = a.vehicle_id
             WHERE a.driver_id = ?
               AND a.in_time >= ?
               AND a.in_time < ?
          ORDER BY a.in_time DESC';

    if ($limit !== null && $limit > 0) {
        $sql .= ' LIMIT ?';
    }

    $query = $conn->prepare($sql);
    $startStr = $start->format('Y-m-d 00:00:00');
    $endStr   = $end->format('Y-m-d 00:00:00');
    if ($limit !== null && $limit > 0) {
        $query->bind_param('issi', $driverId, $startStr, $endStr, $limit);
    } else {
        $query->bind_param('iss', $driverId, $startStr, $endStr);
    }
    $query->execute();
    $result = $query->get_result();
    $records = [];
    while ($row = $result->fetch_assoc()) {
        $records[] = [
            'attendanceId'   => (int)$row['id'],
            'driverId'       => (int)$row['driver_id'],
            'plantId'        => $row['plant_id'],
            'plantName'      => $row['plant_name'],
            'vehicleId'      => $row['vehicle_id'],
            'vehicleNumber'  => $row['vehicle_no'],
            'assignmentId'   => $row['assignment_id'],
            'inTime'         => $row['in_time'],
            'outTime'        => $row['out_time'],
            'inPhotoUrl'     => $row['in_photo_url'],
            'outPhotoUrl'    => $row['out_photo_url'],
            'status'         => $row['approval_status'],
            'notes'          => $row['notes'],
            'pendingSync'    => (bool)$row['pending_sync'],
            'source'         => $row['source'],
        ];
    }
    $query->close();

    apiRespond(200, [
        'status' => 'ok',
        'driverId' => $driverId,
        'month' => $month,
        'records' => $records,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
