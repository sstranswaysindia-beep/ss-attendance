<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

if (!function_exists('td_table_exists')) {
    function td_table_exists(mysqli $db, string $table): bool
    {
        $table = $db->real_escape_string($table);
        $res = $db->query("SHOW TABLES LIKE '{$table}'");
        return $res && $res->num_rows > 0;
    }
}

if (!function_exists('td_has_column')) {
    function td_has_column(string $table, string $column): bool
    {
        global $conn, $mysqli, $con;
        $db = $conn instanceof mysqli ? $conn
            : ($mysqli instanceof mysqli ? $mysqli
            : ($con instanceof mysqli ? $con : null));
        
        if (!$db) return false;
        
        $table = $db->real_escape_string($table);
        $column = $db->real_escape_string($column);
        $sql = "SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '{$table}' AND COLUMN_NAME = '{$column}' LIMIT 1";
        $res = $db->query($sql);
        return $res && $res->num_rows > 0;
    }
}

$role = TD_MOBILE_ROLE;
$userId = TD_MOBILE_USER_ID;
$driverId = TD_MOBILE_DRIVER_ID;

if (!$driverId) {
    apiRespond(401, ['ok' => false, 'error' => 'Driver ID required']);
}

$plantId = apiSanitizeInt(td_request_value('plant_id', td_request_value('plantId')));

try {
    global $conn, $mysqli, $con;
    /** @var mysqli|null $db */
    $db = $conn instanceof mysqli ? $conn
        : ($mysqli instanceof mysqli ? $mysqli
        : ($con instanceof mysqli ? $con : null));
    
    if (!$db || $db->connect_errno) {
        apiRespond(500, ['ok' => false, 'error' => 'Database connection not available']);
    }
    
    // If assignments table is missing, return graceful nulls so UI doesn't break
    if (!td_table_exists($db, 'assignments')) {
        apiRespond(200, ['ok' => true, 'vehicle_id' => null, 'vehicle_no' => null]);
    }

    // Admin/Supervisor can call GET; return nulls (no "personal" assignment)
    if ($driverId <= 0 && in_array($role, ['admin', 'supervisor'], true)) {
        apiRespond(200, ['ok' => true, 'vehicle_id' => null, 'vehicle_no' => null]);
    }

    $vehicleId = null;
    if ($plantId > 0) {
        $stmt = $db->prepare("SELECT vehicle_id FROM assignments WHERE driver_id=? AND plant_id=? ORDER BY id DESC LIMIT 1");
        if ($stmt) {
            $stmt->bind_param('ii', $driverId, $plantId);
            $stmt->execute();
            $stmt->bind_result($vid);
            if ($stmt->fetch()) {
                $vehicleId = $vid ? (int)$vid : null;
            }
            $stmt->close();
        }
    } else {
        $stmt = $db->prepare("SELECT vehicle_id FROM assignments WHERE driver_id=? ORDER BY id DESC LIMIT 1");
        if ($stmt) {
            $stmt->bind_param('i', $driverId);
            $stmt->execute();
            $stmt->bind_result($vid);
            if ($stmt->fetch()) {
                $vehicleId = $vid ? (int)$vid : null;
            }
            $stmt->close();
        }
    }

    $vehicleNo = null;
    if ($vehicleId) {
        // Check if vehicles table exists and has vehicle_no column
        if (td_table_exists($db, 'vehicles') && td_has_column('vehicles', 'vehicle_no')) {
            $q = $db->prepare("SELECT vehicle_no FROM vehicles WHERE id=?");
            if ($q) {
                $q->bind_param('i', $vehicleId);
                $q->execute();
                $q->bind_result($vno);
                if ($q->fetch()) {
                    $vehicleNo = $vno;
                }
                $q->close();
            }
        }
    }

    apiRespond(200, ['ok' => true, 'vehicle_id' => $vehicleId, 'vehicle_no' => $vehicleNo]);

} catch (mysqli_sql_exception $e) {
    error_log("[driver_vehicle] SQL {$e->getCode()}: {$e->getMessage()}");
    apiRespond(500, ['ok' => false, 'error' => 'Database error', 'code' => (int)$e->getCode()]);
} catch (Throwable $e) {
    error_log("[driver_vehicle] Fatal: {$e->getMessage()} @ {$e->getFile()}:{$e->getLine()}");
    apiRespond(500, ['ok' => false, 'error' => 'Unexpected server error']);
}