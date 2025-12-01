<?php
declare(strict_types=1);

/**
 * Shared helpers to snapshot trip data and record deletion notifications.
 */

if (!function_exists('td_trip_first_valid_int')) {
    function td_trip_first_valid_int(array $candidates): ?int
    {
        foreach ($candidates as $candidate) {
            if ($candidate === null || $candidate === '' || $candidate === false) {
                continue;
            }
            if (is_int($candidate)) {
                if ($candidate > 0) {
                    return $candidate;
                }
                continue;
            }
            if (is_numeric($candidate)) {
                $intVal = (int)$candidate;
                if ($intVal > 0) {
                    return $intVal;
                }
            }
        }
        return null;
    }
}

if (!function_exists('td_trip_first_non_empty_string')) {
    function td_trip_first_non_empty_string(array $candidates): ?string
    {
        foreach ($candidates as $candidate) {
            if (!is_string($candidate)) {
                continue;
            }
            $trimmed = trim($candidate);
            if ($trimmed !== '') {
                return $trimmed;
            }
        }
        return null;
    }
}

if (!function_exists('td_trip_table_exists')) {
    function td_trip_table_exists(mysqli $db, string $table): bool
    {
        static $cache = [];
        $key = strtolower($table);
        if (array_key_exists($key, $cache)) {
            return $cache[$key];
        }

        $tableEsc = $db->real_escape_string($table);
        $sql = "
            SELECT 1
            FROM INFORMATION_SCHEMA.TABLES
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = '{$tableEsc}'
            LIMIT 1
        ";
        $res = $db->query($sql);
        $cache[$key] = $res && $res->num_rows > 0;
        if ($res instanceof mysqli_result) {
            $res->free();
        }

        return $cache[$key];
    }
}

if (!function_exists('td_trip_column_exists')) {
    function td_trip_column_exists(mysqli $db, string $table, string $column): bool
    {
        static $cache = [];
        $cacheKey = strtolower($table) . '.' . strtolower($column);
        if (array_key_exists($cacheKey, $cache)) {
            return $cache[$cacheKey];
        }

        if (!td_trip_table_exists($db, $table)) {
            $cache[$cacheKey] = false;
            return false;
        }

        $tableEsc = $db->real_escape_string($table);
        $columnEsc = $db->real_escape_string($column);
        $sql = "
            SELECT 1
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = '{$tableEsc}'
              AND COLUMN_NAME = '{$columnEsc}'
            LIMIT 1
        ";
        $res = $db->query($sql);
        $cache[$cacheKey] = $res && $res->num_rows > 0;
        if ($res instanceof mysqli_result) {
            $res->free();
        }

        return $cache[$cacheKey];
    }
}

if (!function_exists('td_trip_vehicle_number_column')) {
    function td_trip_vehicle_number_column(mysqli $db): ?string
    {
        static $cached = false;
        static $column = null;

        if ($cached) {
            return $column;
        }

        $cached = true;
        if (!td_trip_table_exists($db, 'vehicles')) {
            return $column;
        }

        $candidates = ['vehicle_no', 'vehicle_number', 'reg_no', 'registration_no', 'plate_no', 'number'];
        foreach ($candidates as $candidate) {
            if (td_trip_column_exists($db, 'vehicles', $candidate)) {
                $column = $candidate;
                break;
            }
        }

        return $column;
    }
}

if (!function_exists('td_trip_fetch_snapshot')) {
    function td_trip_fetch_snapshot(mysqli $db, int $tripId): ?array
    {
        if ($tripId <= 0 || !td_trip_table_exists($db, 'trips')) {
            return null;
        }

        $columns = [
            't.id',
            't.vehicle_id',
        ];

        foreach (['start_date', 'end_date', 'status', 'start_km', 'end_km', 'note', 'trip_number'] as $field) {
            if (td_trip_column_exists($db, 'trips', $field)) {
                $columns[] = "t.`{$field}` AS `{$field}`";
            } else {
                $columns[] = "NULL AS `{$field}`";
            }
        }

        $vehicleJoin = '';
        $vehicleColumn = td_trip_vehicle_number_column($db);
        if ($vehicleColumn !== null) {
            $safeVehicleCol = preg_replace('/[^a-z0-9_]/i', '', $vehicleColumn) ?: 'vehicle_no';
            $columns[] = "v.`{$safeVehicleCol}` AS vehicle_number";
            $vehicleJoin = ' LEFT JOIN vehicles v ON v.id = t.vehicle_id';
        } else {
            $columns[] = 'NULL AS vehicle_number';
        }

        $sql = 'SELECT ' . implode(', ', $columns) . ' FROM trips t' . $vehicleJoin . ' WHERE t.id = ? LIMIT 1';
        $stmt = $db->prepare($sql);
        if (!$stmt) {
            return null;
        }

        $stmt->bind_param('i', $tripId);
        $stmt->execute();
        $res = $stmt->get_result();
        $row = $res ? $res->fetch_assoc() : null;
        $stmt->close();

        if (!$row) {
            return null;
        }

        $startKm = array_key_exists('start_km', $row) && $row['start_km'] !== null && $row['start_km'] !== ''
            ? (float)$row['start_km']
            : null;
        $endKm = array_key_exists('end_km', $row) && $row['end_km'] !== null && $row['end_km'] !== ''
            ? (float)$row['end_km']
            : null;

        return [
            'id' => (int)$row['id'],
            'trip_number' => isset($row['trip_number']) && $row['trip_number'] !== null && $row['trip_number'] !== ''
                ? (string)$row['trip_number']
                : null,
            'vehicle_id' => $row['vehicle_id'] !== null ? (int)$row['vehicle_id'] : null,
            'vehicle_number' => isset($row['vehicle_number']) && $row['vehicle_number'] !== null && $row['vehicle_number'] !== ''
                ? (string)$row['vehicle_number']
                : null,
            'start_date' => $row['start_date'] ?? null,
            'end_date' => $row['end_date'] ?? null,
            'status' => $row['status'] ?? null,
            'start_km' => $startKm,
            'end_km' => $endKm,
            'note' => $row['note'] ?? null,
        ];
    }
}

if (!function_exists('td_trip_lookup_user_name')) {
    function td_trip_lookup_user_name(mysqli $db, int $userId): ?string
    {
        if ($userId <= 0 || !td_trip_table_exists($db, 'users')) {
            return null;
        }

        $fields = [];
        if (td_trip_column_exists($db, 'users', 'full_name')) {
            $fields[] = '`full_name`';
        }
        if (td_trip_column_exists($db, 'users', 'username')) {
            $fields[] = '`username`';
        }
        if (empty($fields)) {
            return null;
        }

        $sql = 'SELECT ' . implode(', ', $fields) . ' FROM users WHERE id = ? LIMIT 1';
        $stmt = $db->prepare($sql);
        if (!$stmt) {
            return null;
        }

        $stmt->bind_param('i', $userId);
        $stmt->execute();
        $res = $stmt->get_result();
        $row = $res ? $res->fetch_assoc() : null;
        $stmt->close();

        if (!$row) {
            return null;
        }

        $fullName = isset($row['full_name']) ? trim((string)$row['full_name']) : '';
        $username = isset($row['username']) ? trim((string)$row['username']) : '';

        if ($fullName !== '') {
            return $fullName;
        }
        if ($username !== '') {
            return $username;
        }

        return null;
    }
}

if (!function_exists('td_trip_lookup_driver_name')) {
    function td_trip_lookup_driver_name(mysqli $db, int $driverId): ?string
    {
        if ($driverId <= 0 || !td_trip_table_exists($db, 'drivers')) {
            return null;
        }

        $fields = [];
        if (td_trip_column_exists($db, 'drivers', 'name')) {
            $fields[] = '`name`';
        }
        if (td_trip_column_exists($db, 'drivers', 'full_name')) {
            $fields[] = '`full_name`';
        }
        if (empty($fields)) {
            return null;
        }

        $sql = 'SELECT ' . implode(', ', $fields) . ' FROM drivers WHERE id = ? LIMIT 1';
        $stmt = $db->prepare($sql);
        if (!$stmt) {
            return null;
        }

        $stmt->bind_param('i', $driverId);
        $stmt->execute();
        $res = $stmt->get_result();
        $row = $res ? $res->fetch_assoc() : null;
        $stmt->close();

        if (!$row) {
            return null;
        }

        $name = isset($row['name']) ? trim((string)$row['name']) : '';
        $fullName = isset($row['full_name']) ? trim((string)$row['full_name']) : '';

        if ($name !== '') {
            return $name;
        }
        if ($fullName !== '') {
            return $fullName;
        }

        return null;
    }
}

if (!function_exists('td_trip_resolve_deleted_by')) {
    function td_trip_resolve_deleted_by(mysqli $db, ?int $userId, ?int $driverId, ?string $fallbackName = null): array
    {
        $session = (isset($_SESSION) && is_array($_SESSION)) ? $_SESSION : [];
        $sessionUser = (isset($session['user']) && is_array($session['user'])) ? $session['user'] : [];
        $sessionDriver = (isset($session['driver']) && is_array($session['driver'])) ? $session['driver'] : [];
        $request = isset($GLOBALS['TD_MOBILE_REQUEST']) && is_array($GLOBALS['TD_MOBILE_REQUEST'])
            ? $GLOBALS['TD_MOBILE_REQUEST']
            : [];

        $resolvedUserId = ($userId && $userId > 0) ? (int)$userId : null;
        if ($resolvedUserId === null) {
            $resolvedUserId = td_trip_first_valid_int([
                $session['user_id'] ?? null,
                $session['id'] ?? null,
                $sessionUser['id'] ?? null,
                $sessionUser['user_id'] ?? null,
                $session['userId'] ?? null,
                $request['deleted_by_user_id'] ?? null,
                $request['deletedByUserId'] ?? null,
                $request['user_id'] ?? null,
                $request['userId'] ?? null,
                $_REQUEST['deleted_by_user_id'] ?? null,
                $_REQUEST['deletedByUserId'] ?? null,
                $_REQUEST['user_id'] ?? null,
                $_REQUEST['userId'] ?? null,
                defined('TD_MOBILE_USER_ID') ? TD_MOBILE_USER_ID : null,
            ]);
        }

        $resolvedDriverId = ($driverId && $driverId > 0) ? (int)$driverId : null;
        if ($resolvedDriverId === null) {
            $resolvedDriverId = td_trip_first_valid_int([
                $session['driver_id'] ?? null,
                $sessionDriver['id'] ?? null,
                $sessionDriver['driver_id'] ?? null,
                $session['driverId'] ?? null,
                $request['deleted_by_driver_id'] ?? null,
                $request['deletedByDriverId'] ?? null,
                $request['driver_id'] ?? null,
                $request['driverId'] ?? null,
                $_REQUEST['deleted_by_driver_id'] ?? null,
                $_REQUEST['deletedByDriverId'] ?? null,
                $_REQUEST['driver_id'] ?? null,
                $_REQUEST['driverId'] ?? null,
                defined('TD_MOBILE_DRIVER_ID') ? TD_MOBILE_DRIVER_ID : null,
            ]);
        }

        $name = null;
        if ($resolvedUserId) {
            $name = td_trip_lookup_user_name($db, $resolvedUserId);
        }
        if (!$name && $resolvedDriverId) {
            $name = td_trip_lookup_driver_name($db, $resolvedDriverId);
        }
        if (!$name) {
            $fallback = td_trip_first_non_empty_string([
                $fallbackName,
                $session['full_name'] ?? null,
                $session['username'] ?? null,
                $session['name'] ?? null,
                $session['display_name'] ?? null,
                $sessionUser['full_name'] ?? null,
                $sessionUser['username'] ?? null,
                $sessionUser['name'] ?? null,
                $sessionUser['display_name'] ?? null,
                $session['driver_name'] ?? null,
                $sessionDriver['name'] ?? null,
                $sessionDriver['full_name'] ?? null,
                $request['deleted_by_name'] ?? null,
                $request['deletedByName'] ?? null,
                $_REQUEST['deleted_by_name'] ?? null,
                $_REQUEST['deletedByName'] ?? null,
            ]);
            if ($fallback !== null) {
                $name = $fallback;
            } elseif ($resolvedUserId) {
                $name = 'User #' . $resolvedUserId;
            } elseif ($resolvedDriverId) {
                $name = 'Driver #' . $resolvedDriverId;
            } else {
                $name = 'Unknown user';
            }
        }

        return [
            'user_id' => $resolvedUserId,
            'driver_id' => $resolvedDriverId,
            'name' => $name,
        ];
    }
}

if (!function_exists('td_trip_record_notification')) {
    function td_trip_record_notification(mysqli $db, array $trip, array $deletedBy): bool
    {
        if (empty($trip['id']) || !td_trip_table_exists($db, 'notification_trip')) {
            return false;
        }

        $deletedByName = isset($deletedBy['name']) ? trim((string)$deletedBy['name']) : '';
        if ($deletedByName === '') {
            $deletedByName = 'Unknown user';
        }

        $tripId = (int)$trip['id'];
        $tripNumber = isset($trip['trip_number']) && $trip['trip_number'] !== null && $trip['trip_number'] !== ''
            ? (string)$trip['trip_number']
            : null;
        $vehicleId = isset($trip['vehicle_id']) && $trip['vehicle_id'] !== null
            ? (int)$trip['vehicle_id']
            : null;
        $vehicleNumber = isset($trip['vehicle_number']) && $trip['vehicle_number'] !== null && $trip['vehicle_number'] !== ''
            ? (string)$trip['vehicle_number']
            : null;
        $deletedByUserId = isset($deletedBy['user_id']) && $deletedBy['user_id']
            ? (int)$deletedBy['user_id']
            : (isset($deletedBy['driver_id']) && $deletedBy['driver_id']
                ? (int)$deletedBy['driver_id']
                : null);

        $message = $tripNumber
            ? sprintf('Trip %s (#%d) deleted by %s', $tripNumber, $tripId, $deletedByName)
            : sprintf('Trip #%d deleted by %s', $tripId, $deletedByName);
        if (strlen($message) > 255) {
            $message = substr($message, 0, 255);
        }

        $payload = [
            'trip' => $trip,
            'deleted_by' => $deletedBy,
            'recorded_at' => gmdate('c'),
        ];
        $payloadJson = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if ($payloadJson === false) {
            $payloadJson = '{}';
        }

        $sql = "
            INSERT INTO notification_trip
                (trip_id, trip_number, vehicle_id, vehicle_number, deleted_by_user_id, deleted_by_name, message, payload)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ";
        $stmt = $db->prepare($sql);
        if (!$stmt) {
            return false;
        }

        $deletedByNameValue = $deletedByName;
        $messageValue = $message;
        $payloadValue = $payloadJson;

        $stmt->bind_param(
            'isisisss',
            $tripId,
            $tripNumber,
            $vehicleId,
            $vehicleNumber,
            $deletedByUserId,
            $deletedByNameValue,
            $messageValue,
            $payloadValue
        );
        $stmt->execute();
        $stmt->close();

        return true;
    }
}
