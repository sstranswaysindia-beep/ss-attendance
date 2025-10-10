<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

$plantId = apiSanitizeInt(
    td_request_value('plantId', td_request_value('plant_id', td_request_value('plantid')))
);
$vehicleId = apiSanitizeInt(
    td_request_value('vehicleId', td_request_value('vehicle_id', td_request_value('vehicleid')))
);

if (!$plantId) {
    apiRespond(200, ['status' => 'ok', 'helpers' => []]);
}

try {
    global $conn, $mysqli, $con;
    /** @var mysqli|null $db */
    $db = $conn instanceof mysqli ? $conn
        : ($mysqli instanceof mysqli ? $mysqli
        : ($con instanceof mysqli ? $con : null));

    if (!$db || $db->connect_errno) {
        apiRespond(500, ['status' => 'error', 'error' => 'DB unavailable']);
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

    $helpers = [];

    if (td_table_exists($db, 'helpers') && td_has_col($db, 'helpers', 'id')) {
        $nameColumn = null;
        foreach (['name', 'helper_name', 'full_name'] as $candidate) {
            if (td_has_col($db, 'helpers', $candidate)) {
                $nameColumn = $candidate;
                break;
            }
        }

        if ($nameColumn) {
            $columns = ["id", "`{$nameColumn}` AS helper_name"];
            $conditions = [];

            if (td_has_col($db, 'helpers', 'plant_id')) {
                $columns[] = 'plant_id';
                $conditions[] = 'plant_id = ?';
            }

            if (td_has_col($db, 'helpers', 'active')) {
                $conditions[] = 'active = 1';
            }
            if (td_has_col($db, 'helpers', 'is_active')) {
                $conditions[] = 'is_active = 1';
            }
            if (td_has_col($db, 'helpers', 'status')) {
                $conditions[] = "(status = 'active' OR status = '1')";
            }

            $sql = 'SELECT ' . implode(',', $columns) . ' FROM helpers';
            if (!empty($conditions)) {
                $sql .= ' WHERE ' . implode(' AND ', $conditions);
            }
            $sql .= " ORDER BY `{$nameColumn}`";

            $stmt = $db->prepare($sql);
            if ($stmt) {
                if (strpos($sql, 'plant_id = ?') !== false) {
                    $stmt->bind_param('i', $plantId);
                }
                $stmt->execute();
                $res = $stmt->get_result();
                while ($row = $res->fetch_assoc()) {
                    $name = trim((string)($row['helper_name'] ?? ''));
                    if ($name === '') {
                        continue;
                    }
                    $helpers[] = [
                        'id' => (int)$row['id'],
                        'name' => $name,
                        'plant_id' => $row['plant_id'] ?? $plantId,
                        'vehicle_id' => $vehicleId,
                    ];
                }
                $stmt->close();
            }
        }
    }

    if (empty($helpers) && td_table_exists($db, 'drivers') && td_has_col($db, 'drivers', 'plant_id')) {
        $roleColumnExists = td_has_col($db, 'drivers', 'role');
        $statusColumnExists = td_has_col($db, 'drivers', 'status');

        $nameExpression = 'CONCAT("Helper #", id)';
        if (td_has_col($db, 'drivers', 'name')) {
            $nameExpression = 'name';
        } elseif (td_has_col($db, 'drivers', 'first_name') && td_has_col($db, 'drivers', 'last_name')) {
            $nameExpression = "TRIM(CONCAT(COALESCE(first_name,''), ' ', COALESCE(last_name,'')))";
        } elseif (td_has_col($db, 'drivers', 'first_name')) {
            $nameExpression = 'first_name';
        }

        $sql = "SELECT id, {$nameExpression} AS helper_name FROM drivers WHERE plant_id = ?";
        if ($roleColumnExists) {
            $sql .= " AND LOWER(role) = 'helper'";
        }
        if ($statusColumnExists) {
            $sql .= " AND (LOWER(status) = 'active' OR status = '1')";
        }
        $sql .= ' ORDER BY helper_name';

        $stmt = $db->prepare($sql);
        if ($stmt) {
            $stmt->bind_param('i', $plantId);
            $stmt->execute();
            $res = $stmt->get_result();
            while ($row = $res->fetch_assoc()) {
                $name = trim((string)($row['helper_name'] ?? ''));
                if ($name === '') {
                    continue;
                }
                $helpers[] = [
                    'id' => (int)$row['id'],
                    'name' => $name,
                    'plant_id' => $plantId,
                    'vehicle_id' => $vehicleId,
                ];
            }
            $stmt->close();
        }
    }

    apiRespond(200, ['status' => 'ok', 'helpers' => $helpers]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
