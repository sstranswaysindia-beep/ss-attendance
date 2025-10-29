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

/* -------- Body parsing -------- */
function read_body_array(): array {
    $ct = strtolower($_SERVER['CONTENT_TYPE'] ?? '');
    $raw = file_get_contents('php://input') ?: '';
    if (strpos($ct,'json') !== false) {
        $j = json_decode($raw,true);
        if (is_array($j)) return $j;
    }
    if (!empty($_POST)) return $_POST;
    $j = json_decode($raw,true); 
    return is_array($j) ? $j : [];
}

/* -------- DB handle -------- */
try {
    global $conn, $mysqli, $con;
    /** @var mysqli|null $db */
    $db = $conn instanceof mysqli ? $conn
        : ($mysqli instanceof mysqli ? $mysqli
        : ($con instanceof mysqli ? $con : null));
    
    if (!$db || $db->connect_errno) {
        apiRespond(500, ['ok' => false, 'error' => 'Database connection not available']);
    }
    
    @$db->set_charset('utf8mb4');
    mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

    /* -------- Small helpers -------- */
    function get_trip_vehicle_and_plant(mysqli $db, int $trip_id): ?array {
        $sql = "SELECT t.vehicle_id, v.plant_id
                FROM trips t
                JOIN vehicles v ON v.id = t.vehicle_id
                WHERE t.id=? LIMIT 1";
        $st = $db->prepare($sql);
        $st->bind_param('i', $trip_id);
        $st->execute();
        $st->bind_result($vid, $pid);
        $ok = $st->fetch();
        $st->close();
        return $ok ? ['vehicle_id'=>(int)$vid, 'plant_id'=>(int)$pid] : null;
    }

    /** Upsert per-driver assignment (UNIQUE on driver_id) */
    function upsert_assignment(mysqli $db, int $driver_id, int $vehicle_id, int $plant_id): void {
        if (!td_table_exists($db,'assignments')) return;
        $sql = "
            INSERT INTO assignments (driver_id, plant_id, vehicle_id, assigned_date)
            VALUES (?, ?, ?, CURDATE())
            ON DUPLICATE KEY UPDATE
                plant_id      = VALUES(plant_id),
                vehicle_id    = VALUES(vehicle_id),
                assigned_date = VALUES(assigned_date)
        ";
        $st = $db->prepare($sql);
        $st->bind_param('iii', $driver_id, $plant_id, $vehicle_id);
        $st->execute();
        $st->close();
    }

    /* -------- Only POST -------- */
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
        apiRespond(405, ['ok' => false, 'error' => 'Method not allowed']);
    }

    $in = read_body_array();

    /* -------- Inputs -------- */
    $trip_id = isset($in['trip_id']) ? (int)$in['trip_id'] : 0;

    $add_customers = (isset($in['add_customer_names']) && is_array($in['add_customer_names']))
        ? array_values(array_filter(array_map(fn($c)=> trim((string)$c), $in['add_customer_names']), fn($x)=> $x !== ''))
        : [];

    $set_customers = (isset($in['set_customer_names']) && is_array($in['set_customer_names']))
        ? array_values(array_filter(array_map(fn($c)=> trim((string)$c), $in['set_customer_names']), fn($x)=> $x !== ''))
        : [];

$helper_id =
  (array_key_exists('helper_id',$in))
    ? (($in['helper_id'] === '' || $in['helper_id'] === null) ? 0 : (int)$in['helper_id']) // 0 => clear
    : null; // null => do not touch

$helperIdsToApply = null;
if (array_key_exists('helper_ids', $in)) {
    $helperIdsToApply = array_values(array_unique(array_filter(
        array_map('intval', (array)$in['helper_ids']),
        fn($v) => $v > 0
    )));
}
if ($helperIdsToApply === null && $helper_id !== null) {
    $helperIdsToApply = $helper_id > 0 ? [$helper_id] : [];
}

$note = array_key_exists('note',$in) ? trim((string)$in['note']) : null;

    $set_driver_ids = array_values(array_unique(array_filter(
        array_map('intval', (array)($in['set_driver_ids'] ?? [])),
        fn($v)=> $v>0
    )));
    $doSyncDrivers = !empty($set_driver_ids);

    /* -------- Basic validation -------- */
    if ($trip_id <= 0) {
        apiRespond(400, ['ok' => false, 'error' => 'trip_id required']);
    }

    /* Ensure trip exists and is ongoing */
    $st = $db->prepare("SELECT status FROM trips WHERE id=? LIMIT 1");
    $st->bind_param('i',$trip_id); 
    $st->execute();
    $res = $st->get_result(); 
    $row = $res ? $res->fetch_assoc() : null; 
    $st->close();
    
    if (!$row) {
        apiRespond(404, ['ok' => false, 'error' => 'Trip not found']);
    }
    
    $status = strtolower((string)($row['status'] ?? ''));
    if ($status !== 'ongoing' && $status !== '1') {
        apiRespond(400, ['ok' => false, 'error' => 'Trip is not ongoing']);
    }

    /* We'll need vehicle_id/plant_id for assignments + optional driver plant mirror */
$tp = get_trip_vehicle_and_plant($db, $trip_id);
if (!$tp) {
    apiRespond(500, ['ok' => false, 'error' => 'Trip vehicle not found']);
}
$vehicle_id = (int)$tp['vehicle_id'];
$plant_id   = (int)$tp['plant_id'];

$hasTripHelpersTable = td_table_exists($db,'trip_helpers');
$hasTripHelperLegacy = td_table_exists($db,'trip_helper');
$hasHelperTextColumn = td_has_column('trips','helper_text');
$driversHavePlantColumn = td_has_column('drivers','plant_id');

$db->begin_transaction();
    try {
        /* Update note */
        if ($note !== null) {
            $u = $db->prepare("UPDATE trips SET note=? WHERE id=?");
            $u->bind_param('si',$note,$trip_id); 
            $u->execute(); 
            $u->close();
        }

        /* Helper upsert/clear (+ assignments + optional drivers.plant_id mirror) */
        if ($helperIdsToApply !== null) {
            if ($hasTripHelpersTable) {
                $del = $db->prepare("DELETE FROM trip_helpers WHERE trip_id=?");
                $del->bind_param('i', $trip_id);
                $del->execute();
                $del->close();

                if (!empty($helperIdsToApply)) {
                    $ins = $db->prepare("INSERT IGNORE INTO trip_helpers (trip_id, helper_id) VALUES (?, ?)");
                    foreach ($helperIdsToApply as $hid) {
                        $ins->bind_param('ii', $trip_id, $hid);
                        $ins->execute();
                    }
                    $ins->close();
                }
            } elseif ($hasHelperTextColumn) {
                $val = !empty($helperIdsToApply)
                    ? implode(',', array_map('strval', $helperIdsToApply))
                    : '';
                $u = $db->prepare("UPDATE trips SET helper_text=? WHERE id=?");
                $u->bind_param('si', $val, $trip_id);
                $u->execute();
                $u->close();
            }

            if ($hasTripHelperLegacy) {
                $d = $db->prepare("DELETE FROM trip_helper WHERE trip_id=?");
                $d->bind_param('i', $trip_id);
                $d->execute();
                $d->close();

                if (!empty($helperIdsToApply)) {
                    $primary = (int)$helperIdsToApply[0];
                    if ($primary > 0) {
                        $i = $db->prepare("INSERT INTO trip_helper (trip_id, helper_id) VALUES (?, ?)");
                        $i->bind_param('ii', $trip_id, $primary);
                        $i->execute();
                        $i->close();
                    }
                }
            } elseif ($hasHelperTextColumn && empty($helperIdsToApply)) {
                $u = $db->prepare("UPDATE trips SET helper_text = NULL WHERE id=?");
                $u->bind_param('i', $trip_id);
                $u->execute();
                $u->close();
            }

            if (!empty($helperIdsToApply)) {
                foreach ($helperIdsToApply as $hid) {
                    upsert_assignment($db, $hid, $vehicle_id, $plant_id);
                    if ($driversHavePlantColumn) {
                        $u = $db->prepare("UPDATE drivers SET plant_id=? WHERE id=?");
                        $u->bind_param('ii', $plant_id, $hid);
                        $u->execute();
                        $u->close();
                    }
                }
            }
        }

        /* Replace customers entirely when set_customer_names present; else add-only path */
        if (!empty($set_customers) && td_table_exists($db,'trip_customers')) {
            $del = $db->prepare("DELETE FROM trip_customers WHERE trip_id=?");
            $del->bind_param('i',$trip_id); 
            $del->execute(); 
            $del->close();

            $ins = $db->prepare("INSERT INTO trip_customers (trip_id, customer_name) VALUES (?, ?)");
            foreach ($set_customers as $c) {
                $ins->bind_param('is',$trip_id,$c); 
                $ins->execute();
            }
            $ins->close();
        } elseif (!empty($add_customers) && td_table_exists($db,'trip_customers')) {
            $existing = [];
            $q = $db->prepare("SELECT customer_name FROM trip_customers WHERE trip_id=?");
            $q->bind_param('i',$trip_id); 
            $q->execute();
            $rs = $q->get_result();
            while ($r = $rs->fetch_assoc()) { 
                $existing[strtolower(trim((string)$r['customer_name']))] = true; 
            }
            $q->close();

            $ins = $db->prepare("INSERT INTO trip_customers (trip_id, customer_name) VALUES (?, ?)");
            foreach ($add_customers as $c) {
                $key = strtolower(trim($c)); 
                if ($key==='' || isset($existing[$key])) continue;
                $ins->bind_param('is',$trip_id,$c); 
                $ins->execute();
                $existing[$key] = true;
            }
            $ins->close();
        }

        /* Driver sync (trip_drivers) + assignments + optional drivers.plant_id mirror */
        if ($doSyncDrivers && td_table_exists($db,'trip_drivers')) {
            // current set
            $current = [];
            $r = $db->prepare("SELECT driver_id FROM trip_drivers WHERE trip_id=?");
            $r->bind_param('i',$trip_id); 
            $r->execute(); 
            $g=$r->get_result();
            while($rw=$g->fetch_assoc()){ 
                $current[(int)$rw['driver_id']] = true; 
            }
            $r->close();
            $target = array_fill_keys($set_driver_ids, true);

            // inserts
            $ins = $db->prepare("INSERT IGNORE INTO trip_drivers (trip_id, driver_id) VALUES (?, ?)");
            foreach ($set_driver_ids as $did) {
                if (!isset($current[$did])) { 
                    $ins->bind_param('ii',$trip_id,$did); 
                    $ins->execute(); 
                }
            }
            $ins->close();

            // deletes
            $toDelete = array_diff(array_keys($current), array_keys($target));
            if (!empty($toDelete)) {
                $place = implode(',', array_fill(0,count($toDelete),'?'));
                $types = str_repeat('i', count($toDelete)+1);
                $sql = "DELETE FROM trip_drivers WHERE trip_id=? AND driver_id IN ($place)";
                $d = $db->prepare($sql);
                $bind = [$types, $trip_id];
                foreach($toDelete as $x){ $bind[] = (int)$x; }
                $refs=[]; foreach($bind as $i=>&$v){ $refs[$i]=&$v; }
                call_user_func_array([$d,'bind_param'],$refs);
                $d->execute(); 
                $d->close();
            }

            // upsert assignments & mirror plant for all current drivers
            foreach ($set_driver_ids as $did) {
                upsert_assignment($db, $did, $vehicle_id, $plant_id);
                if ($driversHavePlantColumn) {
                    $u = $db->prepare("UPDATE drivers SET plant_id=? WHERE id=?");
                    $u->bind_param('ii', $plant_id, $did);
                    $u->execute();
                    $u->close();
                }
            }
        }

        $db->commit();
        apiRespond(200, ['ok' => true]);

    } catch (Throwable $e) {
        $db->rollback();
        error_log("[trips_update] Error: {$e->getMessage()} @ {$e->getFile()}:{$e->getLine()}");
        apiRespond(500, ['ok' => false, 'error' => 'Failed to update ongoing trip', 'detail' => $e->getMessage()]);
    }

} catch (mysqli_sql_exception $e) {
    error_log("[trips_update] SQL {$e->getCode()}: {$e->getMessage()}");
    apiRespond(500, ['ok' => false, 'error' => 'Database error', 'code' => (int)$e->getCode()]);
} catch (Throwable $e) {
    error_log("[trips_update] Fatal: {$e->getMessage()} @ {$e->getFile()}:{$e->getLine()}");
    apiRespond(500, ['ok' => false, 'error' => 'Unexpected server error']);
}
