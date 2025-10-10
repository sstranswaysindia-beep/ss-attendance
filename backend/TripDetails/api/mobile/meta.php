<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

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

    $drivers = [];
    if (td_table_exists($db, 'drivers') && td_has_col($db, 'drivers', 'id')) {
        $nameColumn = null;
        foreach (['name', 'driver_name', 'full_name'] as $candidate) {
            if (td_has_col($db, 'drivers', $candidate)) {
                $nameColumn = $candidate;
                break;
            }
        }

        if ($nameColumn) {
            $conditions = [];
            if (td_has_col($db, 'drivers', 'active')) {
                $conditions[] = 'd.active = 1';
            }
            if (td_has_col($db, 'drivers', 'is_active')) {
                $conditions[] = 'd.is_active = 1';
            }
            if (td_has_col($db, 'drivers', 'status')) {
                $conditions[] = "(LOWER(d.status) = 'active' OR d.status = '1')";
            }
            if (td_has_col($db, 'drivers', 'role')) {
                $conditions[] = "(LOWER(d.role) = 'driver' OR LOWER(d.role) = 'supervisor')";
            }

            $sql = "
                SELECT
                    d.id,
                    d.`{$nameColumn}` AS name,
                    d.plant_id,
                    d.role,
                    COALESCE(sd.name, su.full_name, su.username) AS supervisor_name
                FROM drivers d
                LEFT JOIN plants p ON p.id = d.plant_id
                LEFT JOIN drivers sd ON sd.id = p.supervisor_driver_id
                LEFT JOIN users su ON su.id = p.supervisor_user_id
            ";

            if (!empty($conditions)) {
                $sql .= ' WHERE ' . implode(' AND ', $conditions);
            }

            $sql .= " ORDER BY d.`{$nameColumn}`";

            if ($rs = $db->query($sql)) {
                while ($row = $rs->fetch_assoc()) {
                    $drivers[] = [
                        'id' => (int)$row['id'],
                        'name' => (string)$row['name'],
                        'plant_id' => array_key_exists('plant_id', $row) ? (int)$row['plant_id'] : null,
                        'role' => $row['role'] ?? null,
                        'supervisor_name' => !empty($row['supervisor_name']) ? (string)$row['supervisor_name'] : null,
                    ];
                }
                $rs->close();
            }
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
            $columns = ["id", "`{$nameColumn}` AS name"];
            $conditions = [];

            $hasPlantCol = td_has_col($db, 'helpers', 'plant_id');
            if ($hasPlantCol) {
                $columns[] = 'plant_id';
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

            if ($rs = $db->query($sql)) {
                while ($row = $rs->fetch_assoc()) {
                    $name = trim((string)($row['name'] ?? ''));
                    if ($name === '') {
                        continue;
                    }
                    $helpers[] = [
                        'id' => (int)$row['id'],
                        'name' => $name,
                        'plant_id' => ($hasPlantCol && array_key_exists('plant_id', $row)) ? (int)$row['plant_id'] : null,
                    ];
                }
                $rs->close();
            }
        }
    }

    if (empty($helpers) && td_table_exists($db, 'drivers') && td_has_col($db, 'drivers', 'plant_id')) {
        $nameExpression = 'CONCAT("Helper #", id)';
        if (td_has_col($db, 'drivers', 'name')) {
            $nameExpression = 'name';
        } elseif (td_has_col($db, 'drivers', 'first_name') && td_has_col($db, 'drivers', 'last_name')) {
            $nameExpression = "TRIM(CONCAT(COALESCE(first_name,''), ' ', COALESCE(last_name,'')))";
        } elseif (td_has_col($db, 'drivers', 'first_name')) {
            $nameExpression = 'first_name';
        }

        $conditions = [];
        if (td_has_col($db, 'drivers', 'role')) {
            $conditions[] = "LOWER(role)='helper'";
        }
        if (td_has_col($db, 'drivers', 'status')) {
            $conditions[] = "(LOWER(status)='active' OR status='1')";
        }
        if (td_has_col($db, 'drivers', 'active')) {
            $conditions[] = 'active=1';
        }

        $sql = "SELECT id, plant_id, {$nameExpression} AS name FROM drivers";
        if (!empty($conditions)) {
            $sql .= ' WHERE ' . implode(' AND ', $conditions);
        }
        $sql .= ' ORDER BY name';

        if ($rs = $db->query($sql)) {
            while ($row = $rs->fetch_assoc()) {
                $name = trim((string)($row['name'] ?? ''));
                if ($name === '') {
                    continue;
                }
                $helpers[] = [
                    'id' => (int)$row['id'],
                    'name' => $name,
                    'plant_id' => array_key_exists('plant_id', $row) ? (int)$row['plant_id'] : null,
                ];
            }
            $rs->close();
        }
    }

    $customers = [];
    if (td_table_exists($db, 'customers') && td_has_col($db, 'customers', 'id')) {
        $customerNameCol = null;
        foreach (['name', 'customer_name', 'title'] as $field) {
            if (td_has_col($db, 'customers', $field)) {
                $customerNameCol = $field;
                break;
            }
        }

        if ($customerNameCol) {
            $sql = "SELECT DISTINCT `{$customerNameCol}` AS name FROM customers
                    WHERE `{$customerNameCol}` IS NOT NULL AND TRIM(`{$customerNameCol}`) != ''
                    ORDER BY `{$customerNameCol}` LIMIT 1000";
            if ($rs = $db->query($sql)) {
                while ($row = $rs->fetch_assoc()) {
                    $name = trim((string)($row['name'] ?? ''));
                    if ($name !== '') {
                        $customers[] = ['name' => $name];
                    }
                }
                $rs->close();
            }
        }
    }

    if (empty($customers) && td_table_exists($db, 'trip_customers') && td_has_col($db, 'trip_customers', 'trip_id')) {
        $customerNameCol = null;
        foreach (['customer_name', 'name', 'title'] as $field) {
            if (td_has_col($db, 'trip_customers', $field)) {
                $customerNameCol = $field;
                break;
            }
        }

        if ($customerNameCol) {
            $sql = "SELECT DISTINCT `{$customerNameCol}` AS name FROM trip_customers
                    WHERE `{$customerNameCol}` IS NOT NULL AND TRIM(`{$customerNameCol}`) != ''
                    ORDER BY `{$customerNameCol}` LIMIT 1000";
            if ($rs = $db->query($sql)) {
                while ($row = $rs->fetch_assoc()) {
                    $name = trim((string)($row['name'] ?? ''));
                    if ($name !== '') {
                        $customers[] = ['name' => $name];
                    }
                }
                $rs->close();
            }
        }
    }

    apiRespond(200, [
        'status' => 'ok',
        'drivers' => $drivers,
        'helpers' => $helpers,
        'customers' => $customers,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
