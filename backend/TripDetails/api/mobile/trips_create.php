<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

if (!function_exists('td_json')) {
    function td_json(array $payload, int $status = 200): void
    {
        if (function_exists('ob_get_level')) {
            while (ob_get_level() > 0) {
                @ob_end_clean();
            }
        }
        if (!headers_sent()) {
            http_response_code($status);
            header('Content-Type: application/json; charset=utf-8');
            header('Cache-Control: no-store, no-cache, must-revalidate, private');
        }
        echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }
}

/** @var mysqli|null $conn */
/** @var mysqli|null $mysqli */
/** @var mysqli|null $con */
$db = $conn instanceof mysqli ? $conn : ($mysqli instanceof mysqli ? $mysqli : ($con instanceof mysqli ? $con : null));
if (!$db || $db->connect_errno) {
    td_json(['status' => 'error', 'error' => 'Database connection not available'], 500);
}
@$db->set_charset('utf8mb4');

if (!function_exists('td_table_exists')) {
    function td_table_exists(mysqli $db, string $table): bool
    {
        $table = $db->real_escape_string($table);
        $res = $db->query("SHOW TABLES LIKE '{$table}'");
        return $res && $res->num_rows > 0;
    }
}

if (!function_exists('td_has_col')) {
    function td_has_col(mysqli $db, string $table, string $column): bool
    {
        $table = $db->real_escape_string($table);
        $column = $db->real_escape_string($column);
        $sql = "SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE()
                   AND TABLE_NAME = '{$table}'
                   AND COLUMN_NAME = '{$column}'
                 LIMIT 1";
        $res = $db->query($sql);
        return $res && $res->num_rows > 0;
    }
}

function td_read_body(): array
{
    $payload = $GLOBALS['TD_MOBILE_REQUEST'] ?? [];
    if (!is_array($payload) || empty($payload)) {
        $raw = file_get_contents('php://input') ?: '';
        if ($raw !== '') {
            $json = json_decode($raw, true);
            if (is_array($json)) {
                $payload = $json;
            }
        }
    }
    if (!is_array($payload)) {
        $payload = [];
    }
    return $payload;
}

function td_vehicle_plant(mysqli $db, int $vehicleId): ?int
{
    $stmt = $db->prepare('SELECT plant_id FROM vehicles WHERE id = ? LIMIT 1');
    $stmt->bind_param('i', $vehicleId);
    $stmt->execute();
    $stmt->bind_result($plantId);
    $found = $stmt->fetch();
    $stmt->close();
    return $found ? (int)$plantId : null;
}

function td_upsert_assignment(mysqli $db, int $driverId, int $vehicleId, int $plantId): void
{
    if (!td_table_exists($db, 'assignments')) {
        return;
    }
    $sql = "INSERT INTO assignments (driver_id, plant_id, vehicle_id, assigned_date)
            VALUES (?, ?, ?, CURDATE())
            ON DUPLICATE KEY UPDATE
              plant_id = VALUES(plant_id),
              vehicle_id = VALUES(vehicle_id),
              assigned_date = VALUES(assigned_date)";
    $stmt = $db->prepare($sql);
    $stmt->bind_param('iii', $driverId, $plantId, $vehicleId);
    $stmt->execute();
    $stmt->close();
}

if (!td_table_exists($db, 'trips')) {
    td_json(['status' => 'error', 'error' => 'trips table missing'], 500);
}

$data = td_read_body();

$vehicleId = isset($data['vehicle_id']) ? (int)$data['vehicle_id'] : 0;
$startDate = trim((string)($data['start_date'] ?? ''));
$startKm = array_key_exists('start_km', $data) ? (int)$data['start_km'] : null;
$driverIds = array_values(array_filter(array_map('intval', (array)($data['driver_ids'] ?? []))));

$legacyHelper = (isset($data['helper_id']) && $data['helper_id'] !== '' && $data['helper_id'] !== null)
    ? (int)$data['helper_id'] : null;
$helperIds = array_values(array_filter(array_map('intval', (array)($data['helper_ids'] ?? []))));
if ($legacyHelper && !in_array($legacyHelper, $helperIds, true)) {
    $helperIds[] = $legacyHelper;
}
$helperIds = array_values(array_unique(array_filter($helperIds, fn($id) => (int)$id > 0)));

$customerNames = array_values(array_filter(array_map('trim', (array)($data['customer_names'] ?? [])), fn($name) => $name !== ''));
$note = trim((string)($data['note'] ?? ''));
$gpsLat = isset($data['gps_lat']) && $data['gps_lat'] !== '' ? (float)$data['gps_lat'] : null;
$gpsLng = isset($data['gps_lng']) && $data['gps_lng'] !== '' ? (float)$data['gps_lng'] : null;

if ($vehicleId <= 0 || $startDate === '' || $startKm === null || empty($driverIds) || empty($customerNames)) {
    td_json([
        'status' => 'error',
        'error' => 'Required fields missing',
        'fields' => [
            'vehicle_id' => $vehicleId,
            'start_date' => $startDate,
            'start_km' => $startKm,
            'driver_ids_count' => count($driverIds),
            'customers_count' => count($customerNames),
        ],
    ], 400);
}

mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

try {
    $db->begin_transaction();

    $lastEndKm = null;
    $check = $db->prepare('SELECT end_km FROM trips WHERE vehicle_id = ? AND end_km IS NOT NULL ORDER BY id DESC LIMIT 1');
    $check->bind_param('i', $vehicleId);
    $check->execute();
    $res = $check->get_result();
    if ($res && $res->num_rows) {
        $lastEndKm = (int)$res->fetch_assoc()['end_km'];
    }
    $check->close();

    if ($lastEndKm !== null && $startKm < $lastEndKm) {
        td_json([
            'status' => 'error',
            'error' => 'Start KM must be greater than or equal to last ended KM',
            'last_end_km' => $lastEndKm,
        ], 422);
    }

    $cols = ['vehicle_id', 'start_date', 'start_km', 'status', 'note', 'started_at'];
    $marks = ['?', '?', '?', '?', '?', 'NOW()'];
    $types = 'isiss';
    $params = [$vehicleId, $startDate, $startKm, 'ongoing', $note];

    if ($gpsLat !== null) {
        $cols[] = 'gps_lat';
        $marks[] = '?';
        $types .= 'd';
        $params[] = $gpsLat;
    }
    if ($gpsLng !== null) {
        $cols[] = 'gps_lng';
        $marks[] = '?';
        $types .= 'd';
        $params[] = $gpsLng;
    }

    $insertSql = 'INSERT INTO trips (' . implode(',', $cols) . ') VALUES (' . implode(',', $marks) . ')';
    $insertStmt = $db->prepare($insertSql);
    $bindParams = [$types];
    foreach ($params as $index => &$value) {
        $bindParams[] = &$value;
    }
    call_user_func_array([$insertStmt, 'bind_param'], $bindParams);
    $insertStmt->execute();
    $tripId = $insertStmt->insert_id ?: $db->insert_id;
    $insertStmt->close();

    if (!empty($driverIds) && td_table_exists($db, 'trip_drivers')) {
        $driverStmt = $db->prepare('INSERT IGNORE INTO trip_drivers (trip_id, driver_id) VALUES (?, ?)');
        foreach ($driverIds as $driverId) {
            $driverStmt->bind_param('ii', $tripId, $driverId);
            $driverStmt->execute();
        }
        $driverStmt->close();
    }

    if (!empty($customerNames) && td_table_exists($db, 'trip_customers')) {
        $customerStmt = $db->prepare('INSERT INTO trip_customers (trip_id, customer_name) VALUES (?, ?)');
        foreach ($customerNames as $customer) {
            $customerStmt->bind_param('is', $tripId, $customer);
            $customerStmt->execute();
        }
        $customerStmt->close();
    }

    $hasPluralHelpers = td_table_exists($db, 'trip_helpers');
    $hasLegacyHelper = td_table_exists($db, 'trip_helper');
    if (!empty($helperIds)) {
        if ($hasPluralHelpers) {
            $helperStmt = $db->prepare('INSERT IGNORE INTO trip_helpers (trip_id, helper_id) VALUES (?, ?)');
            foreach ($helperIds as $helperId) {
                $helperStmt->bind_param('ii', $tripId, $helperId);
                $helperStmt->execute();
            }
            $helperStmt->close();
        } elseif ($hasLegacyHelper) {
            $primaryHelper = (int)$helperIds[0];
            if ($primaryHelper > 0) {
                $legacyStmt = $db->prepare('REPLACE INTO trip_helper (trip_id, helper_id) VALUES (?, ?)');
                $legacyStmt->bind_param('ii', $tripId, $primaryHelper);
                $legacyStmt->execute();
                $legacyStmt->close();
            }
        }
    }

    $plantId = td_vehicle_plant($db, $vehicleId);
    if ($plantId === null) {
        throw new RuntimeException('Vehicle plant not found');
    }

    if (td_has_col($db, 'drivers', 'plant_id')) {
        foreach ($driverIds as $driverId) {
            $update = $db->prepare('UPDATE drivers SET plant_id = ? WHERE id = ?');
            $update->bind_param('ii', $plantId, $driverId);
            $update->execute();
            $update->close();
        }
        foreach ($helperIds as $helperId) {
            $update = $db->prepare('UPDATE drivers SET plant_id = ? WHERE id = ?');
            $update->bind_param('ii', $plantId, $helperId);
            $update->execute();
            $update->close();
        }
    }

    foreach ($driverIds as $driverId) {
        td_upsert_assignment($db, $driverId, $vehicleId, $plantId);
    }

    $db->commit();

    td_json([
        'status' => 'ok',
        'trip_id' => $tripId,
    ]);
} catch (mysqli_sql_exception $exception) {
    $db->rollback();
    td_json([
        'status' => 'error',
        'error' => 'Database error',
        'code' => (int)$exception->getCode(),
        'detail' => $exception->getMessage(),
    ], 500);
} catch (Throwable $exception) {
    $db->rollback();
    td_json([
        'status' => 'error',
        'error' => $exception->getMessage(),
    ], 500);
}
