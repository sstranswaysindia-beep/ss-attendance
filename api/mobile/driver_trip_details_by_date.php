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

if (!function_exists('column_exists')) {
    function column_exists(mysqli $db, string $table, string $column): bool
    {
        $tableEsc = $db->real_escape_string($table);
        $columnEsc = $db->real_escape_string($column);
        $sql = "SELECT 1
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = '{$tableEsc}'
                  AND COLUMN_NAME = '{$columnEsc}'
                LIMIT 1";
        $res = $db->query($sql);
        $exists = $res && $res->num_rows > 0;
        if ($res instanceof mysqli_result) {
            $res->free();
        }
        return $exists;
    }
}

if (!function_exists('table_exists')) {
    function table_exists(mysqli $db, string $table): bool
    {
        $tableEsc = $db->real_escape_string($table);
        $res = $db->query("SHOW TABLES LIKE '{$tableEsc}'");
        $exists = $res && $res->num_rows > 0;
        if ($res instanceof mysqli_result) {
            $res->free();
        }
        return $exists;
    }
}

try {
    $participantSources = [];
    if (table_exists($conn, 'trip_drivers') && column_exists($conn, 'trip_drivers', 'driver_id')) {
        $participantSources[] = 'SELECT trip_id, driver_id AS person_id FROM trip_drivers';
    }
    if (table_exists($conn, 'trip_helpers') && column_exists($conn, 'trip_helpers', 'helper_id')) {
        $participantSources[] = 'SELECT trip_id, helper_id AS person_id FROM trip_helpers';
    }
    if (table_exists($conn, 'trip_helper') && column_exists($conn, 'trip_helper', 'helper_id')) {
        $participantSources[] = 'SELECT trip_id, helper_id AS person_id FROM trip_helper';
    }

    if (empty($participantSources)) {
        apiRespond(200, [
            'status' => 'ok',
            'driverId' => (int)$driverId,
            'from' => $from,
            'to' => $to,
            'byDate' => (object)[],
        ]);
    }

    $participantSql = implode(' UNION ALL ', $participantSources);

    $sql = "
        SELECT
            t.id AS trip_id,
            t.start_date,
            t.end_date,
            t.status,
            t.note,
            t.start_km,
            t.end_km,
            v.vehicle_no,
            p.plant_name,
            GROUP_CONCAT(DISTINCT d.name ORDER BY d.name SEPARATOR ', ') AS drivers,
            GROUP_CONCAT(DISTINCT c.customer_name SEPARATOR ', ') AS customers
        FROM trips t
        JOIN ({$participantSql}) person_map ON person_map.trip_id = t.id
        JOIN vehicles v ON v.id = t.vehicle_id
        JOIN plants p ON p.id = v.plant_id
        LEFT JOIN trip_drivers td ON td.trip_id = t.id
        LEFT JOIN drivers d ON d.id = td.driver_id
        LEFT JOIN trip_customers c ON c.trip_id = t.id
        WHERE person_map.person_id = ?
          AND t.start_date <= ?
          AND COALESCE(NULLIF(t.end_date, '0000-00-00'), t.start_date) >= ?
        GROUP BY t.id
        ORDER BY t.start_date DESC, t.id DESC
        LIMIT 2000
    ";

    $stmt = $conn->prepare($sql);
    $stmt->bind_param('iss', $driverId, $to, $from);
    $stmt->execute();
    $rows = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    $byDate = [];
    foreach ($rows as $row) {
        $tripStart = (string)($row['start_date'] ?? '');
        if ($tripStart === '') {
            continue;
        }
        $tripEnd = (string)($row['end_date'] ?? '');
        $tripEnd = ($tripEnd !== '' && $tripEnd !== '0000-00-00') ? $tripEnd : $tripStart;

        $currentDate = $tripStart < $from ? $from : $tripStart;
        $lastDate = $tripEnd > $to ? $to : $tripEnd;
        while ($currentDate <= $lastDate) {
            if (!isset($byDate[$currentDate])) {
                $byDate[$currentDate] = [];
            }
            $byDate[$currentDate][] = [
            'tripId' => isset($row['trip_id']) ? (int)$row['trip_id'] : 0,
            'startDate' => $row['start_date'] ?? null,
            'endDate' => $row['end_date'] ?? null,
            'status' => $row['status'] ?? '',
            'vehicleNumber' => $row['vehicle_no'] ?? '',
            'plantName' => $row['plant_name'] ?? '',
            'drivers' => $row['drivers'] ?? '',
            'helpers' => '',
            'customers' => $row['customers'] ?? '',
            'startKm' => $row['start_km'] !== null ? (int)$row['start_km'] : null,
            'endKm' => $row['end_km'] !== null ? (int)$row['end_km'] : null,
            'note' => $row['note'] ?? '',
            ];
            $nextTs = strtotime($currentDate . ' +1 day');
            if ($nextTs === false) {
                break;
            }
            $currentDate = date('Y-m-d', $nextTs);
        }
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
