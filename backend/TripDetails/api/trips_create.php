<?php
// /TripDetails/api/trips_create.php

require_once __DIR__ . '/bootstrap.php';
require_once __DIR__ . '/_auth_guard.php';

/* ---------- json_out helper ---------- */
if (!function_exists('json_out') && function_exists('json')) {
  function json_out($payload, int $status = 200){ json($payload, $status); }
}
if (!function_exists('json_out')) {
  function json_out($payload, int $status = 200): void {
    if (function_exists('ob_get_level')) { while (ob_get_level() > 0) { @ob_end_clean(); } }
    if (!headers_sent()) {
      http_response_code($status);
      header('Content-Type: application/json; charset=utf-8');
      header('Cache-Control: no-store, no-cache, must-revalidate, private');
    }
    echo json_encode($payload, JSON_UNESCAPED_UNICODE);
    exit;
  }
}

/* ---------- DB handle ---------- */
$db = $mysqli ?? $conn ?? $con ?? null;
if (!$db || $db->connect_errno) {
  json_out(['ok'=>false,'error'=>'Database connection not available'], 500);
}
@$db->set_charset('utf8mb4');

/* ---------- schema helpers (local) ---------- */
if (!function_exists('table_exists')) {
  function table_exists(mysqli $db, string $t): bool {
    $t = $db->real_escape_string($t);
    $r = $db->query("SHOW TABLES LIKE '{$t}'");
    return $r && $r->num_rows > 0;
  }
}
if (!function_exists('has_col')) {
  function has_col(mysqli $db, string $t, string $c): bool {
    $t = $db->real_escape_string($t);
    $c = $db->real_escape_string($c);
    $r = $db->query(
      "SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
       WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='{$t}' AND COLUMN_NAME='{$c}' LIMIT 1"
    );
    return $r && $r->num_rows > 0;
  }
}

/* ---------- small helpers ---------- */
function get_vehicle_plant(mysqli $db, int $vehicle_id): ?int {
  $st = $db->prepare("SELECT plant_id FROM vehicles WHERE id=? LIMIT 1");
  $st->bind_param('i', $vehicle_id);
  $st->execute();
  $st->bind_result($pid);
  $ok = $st->fetch();
  $st->close();
  return $ok ? (int)$pid : null;
}

/** Upsert per-driver assignment (unique per driver) */
function upsert_assignment(mysqli $db, int $driver_id, int $vehicle_id, int $plant_id): void {
  if (!table_exists($db,'assignments')) return;
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

/* ---------- parse body ---------- */
$ct  = strtolower($_SERVER['CONTENT_TYPE'] ?? '');
$raw = file_get_contents('php://input') ?: '';
$body = (strpos($ct,'application/json') !== false) ? json_decode($raw, true) : null;
if (!is_array($body)) { $body = $_POST ?? []; if (!is_array($body)) $body = []; }

/* ---------- inputs ---------- */
$vehicle_id     = isset($body['vehicle_id']) ? (int)$body['vehicle_id'] : 0;
$start_date     = trim((string)($body['start_date'] ?? ''));   // 'YYYY-MM-DD'
$start_km       = array_key_exists('start_km', $body) ? (int)$body['start_km'] : null;
$driver_ids     = array_values(array_filter(array_map('intval', (array)($body['driver_ids'] ?? []))));

/* multi-helper: preferred helper_ids[], legacy helper_id supported */
$helper_id_legacy = (isset($body['helper_id']) && $body['helper_id'] !== '' && $body['helper_id'] !== null)
  ? (int)$body['helper_id'] : null;
$helper_ids_in  = array_values(array_filter(array_map('intval', (array)($body['helper_ids'] ?? []))));
$helper_ids     = $helper_ids_in;
if ($helper_id_legacy && !in_array($helper_id_legacy, $helper_ids, true)) $helper_ids[] = $helper_id_legacy;
$helper_ids     = array_values(array_unique(array_filter($helper_ids, fn($x)=> (int)$x > 0)));

$customer_names = array_values(array_filter(array_map('trim', (array)($body['customer_names'] ?? [])), fn($s)=>$s!==''));
$note           = trim((string)($body['note'] ?? ''));

$gps_lat = (isset($body['gps_lat']) && $body['gps_lat'] !== '') ? (float)$body['gps_lat'] : null;
$gps_lng = (isset($body['gps_lng']) && $body['gps_lng'] !== '') ? (float)$body['gps_lng'] : null;

/* ---------- validate (presence) ---------- */
if ($vehicle_id <= 0 || $start_date === '' || $start_km === null || empty($driver_ids) || empty($customer_names)) {
  json_out(['ok'=>false,'error'=>'Required fields missing','fields'=>[
    'vehicle_id'     => $vehicle_id,
    'start_date'     => $start_date,
    'start_km'       => $start_km,
    'driver_ids_cnt' => count($driver_ids),
    'customer_cnt'   => count($customer_names),
  ]], 400);
}

/* ---------- extra validation: start_km ≥ last ended end_km (allow equality) ---------- */
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

try {
  // Make sure the last ended trip (if any) has an odometer not greater than current start
  $last_end_km = null;
  $q = $db->prepare("
      SELECT end_km
      FROM trips
      WHERE vehicle_id = ? AND end_km IS NOT NULL
      ORDER BY id DESC
      LIMIT 1
  ");
  $q->bind_param('i', $vehicle_id);
  $q->execute();
  $qr = $q->get_result();
  if ($qr && $qr->num_rows) {
    $last_end_km = (int)$qr->fetch_assoc()['end_km'];
  }
  $q->close();

  // ONLY block if start_km is LOWER; equality is allowed now
  if ($last_end_km !== null && $start_km < $last_end_km) {
    json_out([
      'ok'    => false,
      'error' => "Start KM must be ≥ last End KM (".$last_end_km.")."
    ], 422);
  }

  /* ---------- main tx ---------- */
  $db->begin_transaction();

  // Insert trip (UNIQUE (vehicle_id, ongoing_flag) will protect duplicates)
  $cols   = ['vehicle_id','start_date','start_km','status','note','started_at'];
  $marks  = ['?','?','?','?','?','NOW()'];
  $types  =  'isiss';
  $params = [$vehicle_id, $start_date, $start_km, 'ongoing', $note];

  if (!is_null($gps_lat)) { $cols[]='gps_lat'; $marks[]='?'; $types.='d'; $params[]=$gps_lat; }
  if (!is_null($gps_lng)) { $cols[]='gps_lng'; $marks[]='?'; $types.='d'; $params[]=$gps_lng; }

  $sql = "INSERT INTO trips (".implode(',',$cols).") VALUES (".implode(',',$marks).")";
  $stmt = $db->prepare($sql);
  $bind = [$types];
  foreach ($params as $k=>&$v) { $bind[] = &$v; }
  call_user_func_array([$stmt,'bind_param'], $bind);
  $stmt->execute();
  $trip_id = $stmt->insert_id ?: $db->insert_id;
  $stmt->close();

  // trip_drivers
  if (!empty($driver_ids) && table_exists($db,'trip_drivers')) {
    $ins = $db->prepare("INSERT IGNORE INTO trip_drivers (trip_id, driver_id) VALUES (?, ?)");
    foreach ($driver_ids as $did) {
      $ins->bind_param('ii', $trip_id, $did);
      $ins->execute();
    }
    $ins->close();
  }

  // trip_customers
  if (!empty($customer_names) && table_exists($db,'trip_customers')) {
    $ic = $db->prepare("INSERT INTO trip_customers (trip_id, customer_name) VALUES (?, ?)");
    foreach ($customer_names as $nm) {
      if ($nm === '') continue;
      $ic->bind_param('is', $trip_id, $nm);
      $ic->execute();
    }
    $ic->close();
  }

  // helpers (plural table preferred; fallback to legacy)
  $has_plural_helpers  = table_exists($db,'trip_helpers');
  $has_legacy_helper   = table_exists($db,'trip_helper');

  if (!empty($helper_ids)) {
    if ($has_plural_helpers) {
      $ih = $db->prepare("INSERT IGNORE INTO trip_helpers (trip_id, helper_id) VALUES (?, ?)");
      foreach ($helper_ids as $hid) {
        $ih->bind_param('ii', $trip_id, $hid);
        $ih->execute();
      }
      $ih->close();
    } elseif ($has_legacy_helper) {
      // legacy: only first helper can be stored
      $first = (int)$helper_ids[0];
      if ($first > 0) {
        $ih = $db->prepare("REPLACE INTO trip_helper (trip_id, helper_id) VALUES (?, ?)");
        $ih->bind_param('ii', $trip_id, $first);
        $ih->execute();
        $ih->close();
      }
    }
  }

  // Resolve plant_id from vehicle
  $plant_id = get_vehicle_plant($db, $vehicle_id);
  if ($plant_id === null) {
    throw new RuntimeException('Vehicle plant not found');
  }

  // Reflect plant to drivers table (optional if column exists)
  if (has_col($db,'drivers','plant_id')) {
    // helpers
    if (!empty($helper_ids)) {
      $u = $db->prepare("UPDATE drivers SET plant_id=? WHERE id=?");
      foreach ($helper_ids as $hid) {
        $u->bind_param('ii', $plant_id, $hid);
        $u->execute();
      }
      $u->close();
    }
    // drivers
    $u = $db->prepare("UPDATE drivers SET plant_id=? WHERE id=?");
    foreach ($driver_ids as $did) {
      $u->bind_param('ii', $plant_id, $did);
      $u->execute();
    }
    $u->close();
  }

  // assignments upsert for helpers + drivers (unique per driver)
  if (!empty($helper_ids)) {
    foreach ($helper_ids as $hid) {
      upsert_assignment($db, $hid, $vehicle_id, $plant_id);
    }
  }
  foreach ($driver_ids as $did) {
    upsert_assignment($db, $did, $vehicle_id, $plant_id);
  }

  $db->commit();

  // return both for compatibility
  json_out([
    'ok'         => true,
    'trip_id'    => $trip_id,
    'helper_id'  => !empty($helper_ids) ? (int)$helper_ids[0] : null, // legacy
    'helper_ids' => $helper_ids,                                       // modern
  ]);

} catch (mysqli_sql_exception $e) {
  @$db->rollback();
  if ((int)$e->getCode() === 1062) {
    // likely UNIQUE(uq_vehicle_one_ongoing) on trips
    json_out(['ok'=>false,'error'=>'An ongoing trip already exists for this vehicle. Please end it first.','code'=>1062], 409);
  }
  json_out(['ok'=>false,'error'=>'Insert failed','code'=>(int)$e->getCode(),'detail'=>$e->getMessage()], 500);
} catch (Throwable $e) {
  @$db->rollback();
  json_out(['ok'=>false,'error'=>'Unexpected server error','detail'=>$e->getMessage()], 500);
}