<?php
// /TripDetails/api/trips_update.php
require __DIR__ . '/bootstrap.php';
require __DIR__ . '/_auth_guard.php';

/* -------- JSON helper -------- */
if (!function_exists('json')) {
  function json($p, int $s=200){
    if(function_exists('ob_get_level')){while(ob_get_level()>0)@ob_end_clean();}
    http_response_code($s);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($p, JSON_UNESCAPED_UNICODE);
    exit;
  }
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
  $j = json_decode($raw,true); return is_array($j)?$j:[];
}

/* -------- DB handle -------- */
$db = $mysqli ?? $conn ?? $con ?? null;
if (!$db || $db->connect_errno) json(['ok'=>false,'error'=>'DB connection not available'], 500);
@$db->set_charset('utf8mb4');

/* -------- Schema helpers (used by this file) -------- */
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
  // assignments writes disabled (requested)
  return;
}

function extract_customer_code(string $value): string {
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

function resolve_customers(mysqli $db, array $inputs): array {
  $names = [];
  $ids = [];
  if (empty($inputs)) return [$names, $ids];
  if (!table_exists($db, 'customers_master') || !has_col($db, 'customers_master', 'customer_name')) {
    foreach ($inputs as $raw) {
      $names[] = $raw;
      $ids[] = null;
    }
    return [$names, $ids];
  }

  $hasShort = has_col($db, 'customers_master', 'short_code');
  $hasStatus = has_col($db, 'customers_master', 'status');

  $keys = [];
  foreach ($inputs as $raw) {
    $value = trim((string)$raw);
    if ($value === '') continue;
    $keys[] = strtolower($value);
    $code = extract_customer_code($value);
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
  foreach ($params as $k => $v) { $bind[] = &$params[$k]; }
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
    $code = extract_customer_code($value);
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

/* -------- Only POST -------- */
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') json(['ok'=>false,'error'=>'Method not allowed'], 405);

$in = read_body_array();

/* -------- Inputs -------- */
$trip_id = isset($in['trip_id']) ? (int)$in['trip_id'] : 0;

$add_customers = (isset($in['add_customer_names']) && is_array($in['add_customer_names']))
  ? array_values(array_filter(array_map(fn($c)=> trim((string)$c), $in['add_customer_names']), fn($x)=> $x !== ''))
  : [];

$set_customers = (isset($in['set_customer_names']) && is_array($in['set_customer_names']))
  ? array_values(array_filter(array_map(fn($c)=> trim((string)$c), $in['set_customer_names']), fn($x)=> $x !== ''))
  : [];
$add_customer_ids = [];
$set_customer_ids = [];
if (!empty($add_customers)) {
  [$add_customers, $add_customer_ids] = resolve_customers($db, $add_customers);
}
if (!empty($set_customers)) {
  [$set_customers, $set_customer_ids] = resolve_customers($db, $set_customers);
}

$helper_id =
  (array_key_exists('helper_id',$in))
    ? (($in['helper_id'] === '' || $in['helper_id'] === null) ? 0 : (int)$in['helper_id']) // 0 => clear
    : null; // null => do not touch

$note = array_key_exists('note',$in) ? trim((string)$in['note']) : null;

$set_driver_ids = array_values(array_unique(array_filter(
  array_map('intval', (array)($in['set_driver_ids'] ?? [])),
  fn($v)=> $v>0
)));
$doSyncDrivers = !empty($set_driver_ids);

/* -------- Basic validation -------- */
if ($trip_id <= 0) json(['ok'=>false,'error'=>'trip_id required'], 400);

/* Ensure trip exists and is ongoing */
$st = $db->prepare("SELECT status FROM trips WHERE id=? LIMIT 1");
$st->bind_param('i',$trip_id); $st->execute();
$res = $st->get_result(); $row = $res ? $res->fetch_assoc() : null; $st->close();
if (!$row) json(['ok'=>false,'error'=>'Trip not found'], 404);
$status = strtolower((string)($row['status'] ?? ''));
if ($status !== 'ongoing' && $status !== '1') json(['ok'=>false,'error'=>'Trip is not ongoing'], 400);

/* We’ll need vehicle_id/plant_id for assignments + optional driver plant mirror */
$tp = get_trip_vehicle_and_plant($db, $trip_id);
if (!$tp) json(['ok'=>false,'error'=>'Trip vehicle not found'], 500);
$vehicle_id = (int)$tp['vehicle_id'];
$plant_id   = (int)$tp['plant_id'];

$db->begin_transaction();
try {
  /* Update note */
  if ($note !== null) {
    $u = $db->prepare("UPDATE trips SET note=? WHERE id=?");
    $u->bind_param('si',$note,$trip_id); $u->execute(); $u->close();
  }

  /* Helper upsert/clear (+ assignments + optional drivers.plant_id mirror) */
  if ($helper_id !== null) {
    if (table_exists($db,'trip_helper')) {
      // clear then re-insert when >0
      $d = $db->prepare("DELETE FROM trip_helper WHERE trip_id=?");
      $d->bind_param('i',$trip_id); $d->execute(); $d->close();

      if ($helper_id > 0) {
        $i = $db->prepare("INSERT INTO trip_helper (trip_id, helper_id) VALUES (?,?)");
        $i->bind_param('ii',$trip_id,$helper_id); $i->execute(); $i->close();

        // reflect assignment
        upsert_assignment($db, $helper_id, $vehicle_id, $plant_id);

        // optional mirror to drivers.plant_id
        if (has_col($db,'drivers','plant_id')) {
          $u = $db->prepare("UPDATE drivers SET plant_id=? WHERE id=?");
          $u->bind_param('ii', $plant_id, $helper_id);
          $u->execute();
          $u->close();
        }
      }
    } elseif (has_col($db,'trips','helper_text')) {
      $val = ($helper_id > 0) ? (string)$helper_id : '';
      $u = $db->prepare("UPDATE trips SET helper_text=? WHERE id=?");
      $u->bind_param('si',$val,$trip_id); $u->execute(); $u->close();
      if ($helper_id > 0) {
        upsert_assignment($db, $helper_id, $vehicle_id, $plant_id);
        if (has_col($db,'drivers','plant_id')) {
          $u = $db->prepare("UPDATE drivers SET plant_id=? WHERE id=?");
          $u->bind_param('ii', $plant_id, $helper_id);
          $u->execute();
          $u->close();
        }
      }
    }
  }

  /* Replace customers entirely when set_customer_names present; else add-only path */
  if (!empty($set_customers) && table_exists($db,'trip_customers')) {
    $del = $db->prepare("DELETE FROM trip_customers WHERE trip_id=?");
    $del->bind_param('i',$trip_id); $del->execute(); $del->close();

    $hasCustomerId = has_col($db, 'trip_customers', 'customer_id');
    if ($hasCustomerId) {
      $ins = $db->prepare("INSERT INTO trip_customers (trip_id, customer_name, customer_id) VALUES (?, ?, ?)");
      foreach ($set_customers as $idx => $c) {
        $cid = $set_customer_ids[$idx] ?? null;
        $ins->bind_param('iss', $trip_id, $c, $cid);
        $ins->execute();
      }
      $ins->close();
    } else {
      $ins = $db->prepare("INSERT INTO trip_customers (trip_id, customer_name) VALUES (?, ?)");
      foreach ($set_customers as $c) {
        $ins->bind_param('is',$trip_id,$c); $ins->execute();
      }
      $ins->close();
    }
  } elseif (!empty($add_customers) && table_exists($db,'trip_customers')) {
    $existing = [];
    $q = $db->prepare("SELECT customer_name FROM trip_customers WHERE trip_id=?");
    $q->bind_param('i',$trip_id); $q->execute();
    $rs = $q->get_result();
    while ($r = $rs->fetch_assoc()) { $existing[strtolower(trim((string)$r['customer_name']))] = true; }
    $q->close();

    $hasCustomerId = has_col($db, 'trip_customers', 'customer_id');
    if ($hasCustomerId) {
      $ins = $db->prepare("INSERT INTO trip_customers (trip_id, customer_name, customer_id) VALUES (?, ?, ?)");
      foreach ($add_customers as $idx => $c) {
        $key = strtolower(trim($c)); if ($key==='' || isset($existing[$key])) continue;
        $cid = $add_customer_ids[$idx] ?? null;
        $ins->bind_param('iss', $trip_id, $c, $cid);
        $ins->execute();
        $existing[$key] = true;
      }
      $ins->close();
    } else {
      $ins = $db->prepare("INSERT INTO trip_customers (trip_id, customer_name) VALUES (?, ?)");
      foreach ($add_customers as $c) {
        $key = strtolower(trim($c)); if ($key==='' || isset($existing[$key])) continue;
        $ins->bind_param('is',$trip_id,$c); $ins->execute();
        $existing[$key] = true;
      }
      $ins->close();
    }
  }

  /* Driver sync (trip_drivers) + assignments + optional drivers.plant_id mirror */
  if ($doSyncDrivers && table_exists($db,'trip_drivers')) {
    // current set
    $current = [];
    $r = $db->prepare("SELECT driver_id FROM trip_drivers WHERE trip_id=?");
    $r->bind_param('i',$trip_id); $r->execute(); $g=$r->get_result();
    while($rw=$g->fetch_assoc()){ $current[(int)$rw['driver_id']] = true; }
    $r->close();
    $target = array_fill_keys($set_driver_ids, true);

    // inserts
    $ins = $db->prepare("INSERT IGNORE INTO trip_drivers (trip_id, driver_id) VALUES (?, ?)");
    foreach ($set_driver_ids as $did) {
      if (!isset($current[$did])) { $ins->bind_param('ii',$trip_id,$did); $ins->execute(); }
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
      $d->execute(); $d->close();
    }

    // upsert assignments & mirror plant for all current drivers
    foreach ($set_driver_ids as $did) {
      upsert_assignment($db, $did, $vehicle_id, $plant_id);
      if (has_col($db,'drivers','plant_id')) {
        $u = $db->prepare("UPDATE drivers SET plant_id=? WHERE id=?");
        $u->bind_param('ii', $plant_id, $did);
        $u->execute();
        $u->close();
      }
    }
  }

  $db->commit();
  json(['ok'=>true]);

} catch (Throwable $e) {
  $db->rollback();
  json(['ok'=>false,'error'=>'Failed to update ongoing trip','detail'=>$e->getMessage()], 500);
}
