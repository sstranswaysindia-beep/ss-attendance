<?php
declare(strict_types=1);

/**
 * Mobile Trips Create API (FAST + IDEMPOTENT + CONSISTENT RESPONSE)
 * - Success == HTTP 200 with { ok:true, success:true, status:"ok", duplicate:<bool>, trip_id:<int> }
 * - Idempotent on (vehicle_id, start_km)
 * - Multi-helper (trip_helpers) + legacy mirror (trip_helper)
 * - Helper by ID or Name (resolved via drivers)
 * - Column-safe insert; Plant mirror + assignments
 * - NO post-commit hydration (avoid false "failed" in client)
 */

require __DIR__ . '/bootstrap.php';

/* ---------- json out ---------- */
function m_json_out(array $payload, int $status = 200): void {
    if (function_exists('ob_get_level')) { while (ob_get_level() > 0) { @ob_end_clean(); } }
    if (!headers_sent()) {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        header('Cache-Control: no-store, no-cache, must-revalidate, private');
        header('Connection: close');
    }
    echo json_encode($payload, JSON_UNESCAPED_UNICODE);
    exit;
}

/* ---------- DB handle ---------- */
$db = null;
if (isset($conn) && $conn instanceof mysqli) $db = $conn;
elseif (isset($mysqli) && $mysqli instanceof mysqli) $db = $mysqli;
elseif (isset($con) && $con instanceof mysqli) $db = $con;
if (!$db || $db->connect_errno) m_json_out(['ok'=>false,'success'=>false,'status'=>'error','error'=>'Database connection not available'], 500);
@$db->set_charset('utf8mb4');

/* ---------- parse request ---------- */
$ct  = strtolower($_SERVER['CONTENT_TYPE'] ?? '');
$raw = file_get_contents('php://input') ?: '';
$body = (strpos($ct, 'application/json') !== false) ? json_decode($raw, true) : null;
if (!is_array($body)) { $body = $_POST ?? []; if (!is_array($body)) $body = []; }

/* ---------- tolerant auth ---------- */
$roleBoot   = defined('TD_MOBILE_ROLE') ? TD_MOBILE_ROLE : '';
$role       = $roleBoot !== '' ? $roleBoot : 'driver';
$driverBoot = defined('TD_MOBILE_DRIVER_ID') ? TD_MOBILE_DRIVER_ID : null;

$auth = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['Authorization'] ?? '';
$driverFromAuth = null;
if ($auth && preg_match('/Bearer\s+dev:(\d+)/i', $auth, $m)) $driverFromAuth = (int)$m[1];

$driverFromPayload = null;
if (!empty($body['driver_ids']) && is_array($body['driver_ids'])) {
    foreach ($body['driver_ids'] as $v) {
        if (is_numeric($v) && (int)$v > 0) { $driverFromPayload = (int)$v; break; }
    }
}
$driverId = $driverBoot ?: $driverFromAuth ?: $driverFromPayload ?: null;
if (!$driverId) m_json_out(['ok'=>false,'success'=>false,'status'=>'error','error'=>'Driver ID required'], 401);

/* ---------- helpers ---------- */
function m_table_exists(mysqli $db, string $t): bool {
    $t = $db->real_escape_string($t);
    $r = $db->query("SHOW TABLES LIKE '{$t}'");
    return $r && $r->num_rows > 0;
}
function m_has_col(mysqli $db, string $t, string $c): bool {
    $t = $db->real_escape_string($t);
    $c = $db->real_escape_string($c);
    $r = $db->query(
        "SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME='{$t}' AND COLUMN_NAME='{$c}' LIMIT 1"
    );
    return $r && $r->num_rows > 0;
}
function get_vehicle_plant(mysqli $db, int $vehicle_id): ?int {
    $st = $db->prepare("SELECT plant_id FROM vehicles WHERE id=? LIMIT 1");
    $st->bind_param('i', $vehicle_id);
    $st->execute();
    $st->bind_result($pid);
    $ok = $st->fetch();
    $st->close();
    return $ok ? (int)$pid : null;
}
function upsert_assignment(mysqli $db, int $driver_id, int $vehicle_id, int $plant_id): void {
    // assignments writes disabled (requested)
    return;
}
function norm_list($v): array {
    if (is_array($v)) return array_values(array_filter(array_map(fn($x)=>trim((string)$x), $v), fn($s)=>$s!==''));
    if (is_string($v)) return array_values(array_filter(array_map('trim', preg_split('/[,\|]/', $v)), fn($s)=>$s!==''));
    return [];
}
function find_helpers_by_labels(mysqli $db, array $labels, int $limitPer = 5): array {
    if (empty($labels)) return [];
    $out = [];
    $sql = "SELECT id FROM drivers
            WHERE (LOWER(name) LIKE ? OR REPLACE(COALESCE(contact,''),' ','') LIKE REPLACE(?, ' ', ''))
            LIMIT ?";
    $st = $db->prepare($sql);
    foreach ($labels as $lab) {
        $lab = trim((string)$lab);
        if ($lab === '') continue;
        $like = '%'.mb_strtolower($lab).'%';
        $st->bind_param('ssi', $like, $lab, $limitPer);
        $st->execute();
        $rs = $st->get_result();
        while ($r = $rs->fetch_assoc()) $out[(int)$r['id']] = true;
    }
    $st->close();
    return array_map('intval', array_keys($out));
}

function m_extract_customer_code(string $value): string {
    $raw = trim($value);
    if ($raw === '') return '';
    $candidate = $raw;
    foreach ([' - ', '-', '•', '|'] as $sep) {
        if (strpos($candidate, $sep) !== false) {
            $parts = explode($sep, $candidate, 2);
            $candidate = $parts[0];
            break;
        }
    }
    if (strpos($candidate, '(') !== false) {
        $candidate = trim(explode('(', $candidate, 2)[0]);
    }
    $candidate = preg_replace('/[^A-Za-z0-9]/', '', $candidate) ?? '';
    return $candidate !== '' ? strtoupper($candidate) : '';
}

function m_resolve_customers(mysqli $db, array $inputs): array {
    $names = [];
    $ids = [];
    if (empty($inputs)) return [$names, $ids];
    if (!m_table_exists($db, 'customers_master') || !m_has_col($db, 'customers_master', 'customer_name')) {
        foreach ($inputs as $raw) {
            $names[] = $raw;
            $ids[] = null;
        }
        return [$names, $ids];
    }

    $hasShort = m_has_col($db, 'customers_master', 'short_code');
    $hasStatus = m_has_col($db, 'customers_master', 'status');

    $keys = [];
    foreach ($inputs as $raw) {
        $value = trim((string)$raw);
        if ($value === '') continue;
        $keys[] = strtolower($value);
        $code = m_extract_customer_code($value);
        if ($code !== '') $keys[] = strtolower($code);
    }
    $keys = array_values(array_unique(array_filter($keys, fn($v)=>$v!=='')));
    if (empty($keys)) {
        foreach ($inputs as $raw) {
            $names[] = $raw;
            $ids[] = null;
        }
        return [$names, $ids];
    }

    $placeholders = implode(',', array_fill(0, count($keys), '?'));
    $cols = $hasShort ? 'short_code' : 'NULL AS short_code';
    $sql = "SELECT id, customer_name, {$cols} FROM customers_master";
    $clauses = [];
    if ($hasShort) {
        $clauses[] = "LOWER(short_code) IN ({$placeholders})";
    }
    $clauses[] = "LOWER(customer_name) IN ({$placeholders})";
    $sql .= ' WHERE (' . implode(' OR ', $clauses) . ')';
    if ($hasStatus) {
        $sql .= " AND (LOWER(status) = 'active' OR status = '1')";
    }
    $sql .= ' ORDER BY customer_name';

    $stmt = $db->prepare($sql);
    $params = $hasShort ? array_merge($keys, $keys) : $keys;
    $types = str_repeat('s', count($params));
    $bind = [$types];
    foreach ($params as $k => $v) {
        $bind[] = &$params[$k];
    }
    call_user_func_array([$stmt, 'bind_param'], $bind);
    $stmt->execute();
    $rs = $stmt->get_result();
    $shortMap = [];
    $nameMap = [];
    while ($row = $rs->fetch_assoc()) {
        $rowName = trim((string)($row['customer_name'] ?? ''));
        $rowShort = trim((string)($row['short_code'] ?? ''));
        if ($rowShort !== '') $shortMap[strtolower($rowShort)] = $row;
        if ($rowName !== '') $nameMap[strtolower($rowName)] = $row;
    }
    $stmt->close();

    foreach ($inputs as $raw) {
        $value = trim((string)$raw);
        if ($value === '') continue;
        $code = m_extract_customer_code($value);
        $row = null;
        if ($code !== '' && isset($shortMap[strtolower($code)])) {
            $row = $shortMap[strtolower($code)];
        } elseif (isset($nameMap[strtolower($value)])) {
            $row = $nameMap[strtolower($value)];
        }
        if ($row) {
            $resolvedName = trim((string)($row['customer_name'] ?? ''));
            $names[] = $resolvedName !== '' ? $resolvedName : $value;
            $id = isset($row['id']) ? (int)$row['id'] : 0;
            $ids[] = $id > 0 ? (string)$id : null;
        } else {
            $names[] = $value;
            $ids[] = null;
        }
    }

    return [$names, $ids];
}

/* ---------- inputs ---------- */
$vehicle_id = isset($body['vehicle_id']) ? (int)$body['vehicle_id'] : 0;
$start_date = trim((string)($body['start_date'] ?? ''));
$start_km   = array_key_exists('start_km', $body) ? (int)$body['start_km'] : null;

$driver_ids = array_values(array_unique(array_filter(
    array_map('intval', (array)($body['driver_ids'] ?? [])), fn($v)=>$v>0
)));
if ($role === 'driver' && $driverId && !in_array((int)$driverId, $driver_ids, true)) {
    $driver_ids[] = (int)$driverId;
}

$customer_names = array_values(array_filter(
    array_map('trim', (array)($body['customer_names'] ?? [])), fn($s)=>$s!==''
));
$customer_ids = [];
if (!empty($customer_names)) {
    [$customer_names, $customer_ids] = m_resolve_customers($db, $customer_names);
}
$note = trim((string)($body['note'] ?? ''));

$gps_lat = (isset($body['gps_lat']) && $body['gps_lat'] !== '') ? (float)$body['gps_lat'] : null;
$gps_lng = (isset($body['gps_lng']) && $body['gps_lng'] !== '') ? (float)$body['gps_lng'] : null;

/* helpers by ID (modern + legacy) */
$helper_ids = array_values(array_filter(array_map('intval', (array)($body['helper_ids'] ?? []))));
$logDir = __DIR__ . '/logs';
if (!is_dir($logDir)) {
    @mkdir($logDir, 0775, true);
}
$logFile = $logDir . '/trips_create.log';
$logPayload = [
    'timestamp' => gmdate('c'),
    'helper_ids_raw' => $body['helper_ids'] ?? [],
    'helper_ids_normalized' => $helper_ids,
    'vehicle_id' => $body['vehicle_id'] ?? null,
    'driver_ids' => $body['driver_ids'] ?? [],
];
@file_put_contents(
    $logFile,
    json_encode($logPayload, JSON_UNESCAPED_UNICODE) . PHP_EOL,
    FILE_APPEND
);
if (isset($body['helper_id']) && $body['helper_id'] !== '' && $body['helper_id'] !== null) {
    $hid = (int)$body['helper_id'];
    if ($hid > 0 && !in_array($hid, $helper_ids, true)) $helper_ids[] = $hid;
}
/* resolve by names if provided */
$helper_labels = array_merge(norm_list($body['helper_names'] ?? []), norm_list($body['helper_name'] ?? []));
if (!empty($helper_labels)) {
    $resolved = find_helpers_by_labels($db, $helper_labels);
    $helper_ids = array_merge($helper_ids, $resolved);
}
$helper_ids = array_values(array_unique(array_filter($helper_ids, fn($x)=>$x>0)));

/* ---------- validate ---------- */
if ($vehicle_id <= 0 || $start_date === '' || $start_km === null || empty($driver_ids) || empty($customer_names)) {
    m_json_out(['ok'=>false,'success'=>false,'status'=>'error','error'=>'Required fields missing','fields'=>[
        'vehicle_id'=>$vehicle_id, 'start_date'=>$start_date, 'start_km'=>$start_km,
        'driver_ids_cnt'=>count($driver_ids), 'customer_cnt'=>count($customer_names),
    ]], 400);
}

/* ---------- ongoing trip guard (avoid false "started") ---------- */
$ongo = $db->prepare("SELECT id, start_km, start_date FROM trips WHERE vehicle_id=? AND status='ongoing' ORDER BY id DESC LIMIT 1");
$ongo->bind_param('i', $vehicle_id);
$ongo->execute();
$ongoRes = $ongo->get_result();
if ($ongoRes && $ongoRes->num_rows) {
    $row = $ongoRes->fetch_assoc();
    $ongo->close();
    m_json_out([
        'ok' => true,
        'success' => true,
        'status' => 'ok',
        'duplicate' => true,
        'already_ongoing' => true,
        'trip_id' => (int)($row['id'] ?? 0),
        'existing_start_km' => isset($row['start_km']) ? (int)$row['start_km'] : null,
        'existing_start_date' => $row['start_date'] ?? null,
        'message' => 'Trip already ongoing for this vehicle',
    ], 200);
}
$ongo->close();

/* ---------- column guards ---------- */
$has_note           = m_has_col($db, 'trips', 'note');
$has_started_at     = m_has_col($db, 'trips', 'started_at');
$has_gps_lat        = m_has_col($db, 'trips', 'gps_lat');
$has_gps_lng        = m_has_col($db, 'trips', 'gps_lng');
$has_drivers_plant  = m_has_col($db, 'drivers', 'plant_id');

/* ---------- IDEMPOTENCY: duplicate check returns ok:true ---------- */
$dup = $db->prepare("SELECT id FROM trips WHERE vehicle_id=? AND start_km=? LIMIT 1");
$dup->bind_param('ii', $vehicle_id, $start_km);
$dup->execute();
$dupr = $dup->get_result();
if ($dupr && $dupr->num_rows) {
    $row = $dupr->fetch_assoc();
    $dup->close();
    m_json_out([
        'ok'=>true, 'success'=>true, 'status'=>'ok',
        'duplicate'=>true, 'trip_id'=>(int)$row['id']
    ], 200);
}
$dup->close();

/* ============================ TRANSACTION ============================ */
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

try {
    $db->begin_transaction();

    // INSERT trip
    $cols   = ['vehicle_id','start_date','start_km','status'];
    $marks  = ['?','?','?','?'];
    $types  =  'isis';
    $params = [$vehicle_id, $start_date, $start_km, 'ongoing'];

    if ($has_note)       { $cols[]='note';       $marks[]='?';     $types.='s'; $params[]=$note; }
    if ($has_started_at) { $cols[]='started_at'; $marks[]='NOW()'; }
    if ($has_gps_lat && $gps_lat !== null) { $cols[]='gps_lat'; $marks[]='?'; $types.='d'; $params[]=$gps_lat; }
    if ($has_gps_lng && $gps_lng !== null) { $cols[]='gps_lng'; $marks[]='?'; $types.='d'; $params[]=$gps_lng; }

    $sql = "INSERT INTO trips (".implode(',', $cols).") VALUES (".implode(',', $marks).")";
    $stmt = $db->prepare($sql);
    $bind = [$types]; foreach ($params as $k=>&$v) { $bind[] = &$v; }
    call_user_func_array([$stmt,'bind_param'],$bind);
    $stmt->execute();
    $trip_id = $stmt->insert_id ?: $db->insert_id;
    $stmt->close();

    // trip_drivers
    if (!empty($driver_ids) && m_table_exists($db, 'trip_drivers')) {
        $ins = $db->prepare("INSERT IGNORE INTO trip_drivers (trip_id, driver_id) VALUES (?, ?)");
        foreach ($driver_ids as $did) { $ins->bind_param('ii',$trip_id,$did); $ins->execute(); }
        $ins->close();
    }

    // trip_customers
    if (!empty($customer_names) && m_table_exists($db, 'trip_customers')) {
        $hasCustomerId = m_has_col($db, 'trip_customers', 'customer_id');
        if ($hasCustomerId) {
            $ic = $db->prepare(
                "INSERT INTO trip_customers (trip_id, customer_name, customer_id) VALUES (?, ?, ?)"
            );
            foreach ($customer_names as $idx => $nm) {
                if ($nm === '') continue;
                $cid = $customer_ids[$idx] ?? null;
                $ic->bind_param('iss', $trip_id, $nm, $cid);
                $ic->execute();
            }
        } else {
            $ic = $db->prepare("INSERT INTO trip_customers (trip_id, customer_name) VALUES (?, ?)");
            foreach ($customer_names as $nm) {
                if ($nm === '') continue;
                $ic->bind_param('is', $trip_id, $nm);
                $ic->execute();
            }
        }
        $ic->close();
    }

    // helpers (plural preferred) + legacy mirror
    $has_plural_helpers = m_table_exists($db, 'trip_helpers');
    $has_legacy_helper  = m_table_exists($db, 'trip_helper');

    if (!empty($helper_ids)) {
        if ($has_plural_helpers) {
            $ih = $db->prepare("INSERT IGNORE INTO trip_helpers (trip_id, helper_id) VALUES (?, ?)");
            foreach ($helper_ids as $hid) { $ih->bind_param('ii',$trip_id,$hid); $ih->execute(); }
            $ih->close();

            if ($has_legacy_helper) {
                $first = (int)$helper_ids[0];
                if ($first > 0) {
                    $ih2 = $db->prepare("
                      INSERT INTO trip_helper (trip_id, helper_id)
                      VALUES (?, ?)
                      ON DUPLICATE KEY UPDATE helper_id = VALUES(helper_id)
                    ");
                    $ih2->bind_param('ii',$trip_id,$first);
                    $ih2->execute();
                    $ih2->close();
                }
            }
        } elseif ($has_legacy_helper) {
            $first = (int)$helper_ids[0];
            if ($first > 0) {
                $ih = $db->prepare("
                  INSERT INTO trip_helper (trip_id, helper_id)
                  VALUES (?, ?)
                  ON DUPLICATE KEY UPDATE helper_id = VALUES(helper_id)
                ");
                $ih->bind_param('ii',$trip_id,$first);
                $ih->execute();
                $ih->close();
            }
        }
    }

    // plant mirror & assignments
    $plant_id = get_vehicle_plant($db, $vehicle_id);
    if ($plant_id === null) throw new RuntimeException('Vehicle plant not found');

    if ($has_drivers_plant) {
        if (!empty($helper_ids)) {
            $u = $db->prepare("UPDATE drivers SET plant_id=? WHERE id=?");
            foreach ($helper_ids as $hid) { $u->bind_param('ii',$plant_id,$hid); $u->execute(); }
            $u->close();
        }
        $u = $db->prepare("UPDATE drivers SET plant_id=? WHERE id=?");
        foreach ($driver_ids as $did) { $u->bind_param('ii',$plant_id,$did); $u->execute(); }
        $u->close();
    }

    if (!empty($helper_ids)) foreach ($helper_ids as $hid) upsert_assignment($db, $hid, $vehicle_id, $plant_id);
    foreach ($driver_ids as $did) upsert_assignment($db, $did, $vehicle_id, $plant_id);

    $db->commit();

} catch (mysqli_sql_exception $e) {
    @$db->rollback();
    if ((int)$e->getCode() === 1062) {
        // treat as idempotent success (double-submit)
        try {
            $q = $db->prepare("SELECT id FROM trips WHERE vehicle_id=? AND start_km=? LIMIT 1");
            $q->bind_param('ii', $vehicle_id, $start_km);
            $q->execute();
            $qr = $q->get_result();
            $row = $qr ? $qr->fetch_assoc() : null;
            $q->close();
            if ($row) m_json_out(['ok'=>true,'success'=>true,'status'=>'ok','duplicate'=>true,'trip_id'=>(int)$row['id']], 200);
        } catch (Throwable $ignore) {}
        // As a fallback, try to return current ongoing trip id (common unique constraint case).
        try {
            $q2 = $db->prepare("SELECT id FROM trips WHERE vehicle_id=? AND status='ongoing' ORDER BY id DESC LIMIT 1");
            $q2->bind_param('i', $vehicle_id);
            $q2->execute();
            $qr2 = $q2->get_result();
            $row2 = $qr2 ? $qr2->fetch_assoc() : null;
            $q2->close();
            if ($row2) {
                m_json_out([
                    'ok'=>true,'success'=>true,'status'=>'ok',
                    'duplicate'=>true,'already_ongoing'=>true,'trip_id'=>(int)$row2['id'],
                ], 200);
            }
        } catch (Throwable $ignore) {}
        m_json_out(['ok'=>true,'success'=>true,'status'=>'ok','duplicate'=>true,'trip_id'=>0], 200);
    }
    m_json_out(['ok'=>false,'success'=>false,'status'=>'error','error'=>'Insert failed','code'=>(int)$e->getCode(),'detail'=>$e->getMessage()], 500);
} catch (Throwable $e) {
    @$db->rollback();
    m_json_out(['ok'=>false,'success'=>false,'status'=>'error','error'=>'Unexpected server error','detail'=>$e->getMessage()], 500);
}

/* ---------- SUCCESS (no hydration) ---------- */
m_json_out([
    'ok'        => true,
    'success'   => true,
    'status'    => 'ok',
    'duplicate' => false,
    'trip_id'   => $trip_id,
    'helper_ids'=> $helper_ids
], 200);
