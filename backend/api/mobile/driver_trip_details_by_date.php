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
$userId = apiSanitizeInt($data['userId'] ?? null);
$role = strtolower(trim((string) ($data['role'] ?? 'driver')));
$from = trim((string)($data['from'] ?? ''));
$to = trim((string)($data['to'] ?? ''));

if (!in_array($role, ['driver', 'supervisor'], true)) {
    $role = 'driver';
}

if ($role === 'supervisor') {
    if (!$userId) {
        apiRespond(400, ['status' => 'error', 'error' => 'userId is required']);
    }
} elseif (!$driverId) {
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
    $sql = '';
    $bindTypes = '';
    $bindValues = [];

    if ($role === 'supervisor') {
        $plantIds = [];

        $directStmt = $conn->prepare('SELECT id FROM plants WHERE supervisor_user_id = ?');
        $directStmt->bind_param('i', $userId);
        $directStmt->execute();
        $directRes = $directStmt->get_result();
        while ($row = $directRes->fetch_assoc()) {
            $pid = isset($row['id']) ? (int) $row['id'] : 0;
            if ($pid > 0) {
                $plantIds[] = $pid;
            }
        }
        $directStmt->close();

        if (table_exists($conn, 'supervisor_plants') && column_exists($conn, 'supervisor_plants', 'user_id') && column_exists($conn, 'supervisor_plants', 'plant_id')) {
            $mapStmt = $conn->prepare('SELECT plant_id FROM supervisor_plants WHERE user_id = ?');
            $mapStmt->bind_param('i', $userId);
            $mapStmt->execute();
            $mapRes = $mapStmt->get_result();
            while ($row = $mapRes->fetch_assoc()) {
                $pid = isset($row['plant_id']) ? (int) $row['plant_id'] : 0;
                if ($pid > 0) {
                    $plantIds[] = $pid;
                }
            }
            $mapStmt->close();
        }

        $plantIds = array_values(array_unique(array_filter($plantIds, static fn($id): bool => (int) $id > 0)));
        if (empty($plantIds)) {
            apiRespond(200, [
                'status' => 'ok',
                'userId' => (int) $userId,
                'from' => $from,
                'to' => $to,
                'byDate' => (object)[],
            ]);
        }

        $placeholders = implode(',', array_fill(0, count($plantIds), '?'));
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
            JOIN vehicles v ON v.id = t.vehicle_id
            JOIN plants p ON p.id = v.plant_id
            LEFT JOIN trip_drivers td ON td.trip_id = t.id
            LEFT JOIN drivers d ON d.id = td.driver_id
            LEFT JOIN trip_customers c ON c.trip_id = t.id
            WHERE v.plant_id IN ({$placeholders})
              AND t.start_date BETWEEN ? AND ?
            GROUP BY t.id
            ORDER BY t.start_date DESC, t.id DESC
            LIMIT 2000
        ";
        $bindTypes = str_repeat('i', count($plantIds)) . 'ss';
        $bindValues = array_merge($plantIds, [$from, $to]);
    } else {
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
              AND t.start_date BETWEEN ? AND ?
            GROUP BY t.id
            ORDER BY t.start_date DESC, t.id DESC
            LIMIT 2000
        ";
        $bindTypes = 'iss';
        $bindValues = [$driverId, $from, $to];
    }

    $stmt = $conn->prepare($sql);
    $stmt->bind_param($bindTypes, ...$bindValues);
    $stmt->execute();
    $rows = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    $byDate = [];
    foreach ($rows as $row) {
        $dateKey = (string)($row['start_date'] ?? '');
        if ($dateKey === '') {
            continue;
        }
        if (!isset($byDate[$dateKey])) {
            $byDate[$dateKey] = [];
        }
        $byDate[$dateKey][] = [
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
    }

    apiRespond(200, [
        'status' => 'ok',
        'role' => $role,
        'userId' => $userId ? (int) $userId : null,
        'driverId' => (int)$driverId,
        'from' => $from,
        'to' => $to,
        'byDate' => empty($byDate) ? (object)[] : $byDate,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
