<?php
// /TripDetails/api/trips_update.php
declare(strict_types=1);

/* ---------- HARDEN OUTPUT ---------- */
@ob_start();
ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

/* Turn PHP errors into exceptions so we can JSON them */
set_error_handler(function($severity, $message, $file, $line) {
  if (!(error_reporting() & $severity)) return false;
  throw new ErrorException($message, 0, $severity, $file, $line);
});

require __DIR__ . '/bootstrap.php';
require __DIR__ . '/_auth_guard.php';

/* ---------- JSON helper ---------- */
function json_out(array $p, int $s=200): void {
  while (ob_get_level() > 0) { @ob_end_clean(); }
  http_response_code($s);
  header('Content-Type: application/json; charset=utf-8');
  header('Cache-Control: no-store, no-cache, must-revalidate, private');
  echo json_encode($p, JSON_UNESCAPED_UNICODE);
  exit;
}

/* ---------- Body parsing ---------- */
function read_body_array(): array {
  $ct = strtolower($_SERVER['CONTENT_TYPE'] ?? '');
  $raw = file_get_contents('php://input') ?: '';
  if (strpos($ct,'json') !== false) {
    $j = json_decode($raw, true);
    if (is_array($j)) return $j;
  }
  if (!empty($_POST)) return $_POST;
  $j = json_decode($raw, true);
  return is_array($j) ? $j : [];
}

/* ---------- Schema helpers ---------- */
function table_exists(mysqli $db, string $t): bool {
  $t = $db->real_escape_string($t);
  $r = $db->query("SHOW TABLES LIKE '{$t}'");
  return $r && $r->num_rows > 0;
}
function has_col(mysqli $db, string $t, string $c): bool {
  $t = $db->real_escape_string($t);
  $c = $db->real_escape_string($c);
  $r = $db->query(
    "SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='{$t}' AND COLUMN_NAME='{$c}' LIMIT 1"
  );
  return $r && $r->num_rows > 0;
}

/* ---------- Small helpers ---------- */
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
/* Helper name resolver */
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
    // use strtolower to avoid mbstring dependency issues
    $like = '%'.strtolower($lab).'%';
    $st->bind_param('ssi', $like, $lab, $limitPer);
    $st->execute();
    $rs = $st->get_result();
    while ($r = $rs->fetch_assoc()) $out[(int)$r['id']] = true;
  }
  $st->close();
  return array_map('intval', array_keys($out));
}

/* ---------- Method guard ---------- */
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') json_out(['ok'=>false,'error'=>'Method not allowed'], 405);

try {
  /* ---------- DB handle ---------- */
  $db = $GLOBALS['mysqli'] ?? $GLOBALS['conn'] ?? $GLOBALS['con'] ?? null;
  if (!$db || $db->connect_errno) json_out(['ok'=>false,'error'=>'DB connection not available'], 500);
  @$db->set_charset('utf8mb4');
  mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

  /* ---------- Inputs ---------- */
  $in = read_body_array();

  $trip_id = isset($in['trip_id']) ? (int)$in['trip_id'] : 0;
  if ($trip_id <= 0) json_out(['ok'=>false,'error'=>'trip_id required'], 400);

  $note = array_key_exists('note',$in) ? trim((string)$in['note']) : null;

  $add_customers = (isset($in['add_customer_names']) && is_array($in['add_customer_names']))
    ? array_values(array_filter(array_map(fn($c)=> trim((string)$c), $in['add_customer_names']), fn($x)=> $x !== ''))
    : [];

  $set_customers = (isset($in['set_customer_names']) && is_array($in['set_customer_names']))
    ? array_values(array_filter(array_map(fn($c)=> trim((string)$c), $in['set_customer_names']), fn($x)=> $x !== ''))
    : [];

  // helpers: ids and/or names
  $helper_id = (array_key_exists('helper_id',$in))
    ? (($in['helper_id'] === '' || $in['helper_id'] === null) ? 0 : (int)$in['helper_id'])
    : null;

  $helper_ids_to_apply = null;
  if (array_key_exists('helper_ids', $in)) {
    $helper_ids_to_apply = array_values(array_unique(array_filter(
      array_map('intval', (array)$in['helper_ids']), fn($v)=> $v>0
    )));
  }
  if ($helper_ids_to_apply === null && $helper_id !== null) {
    $helper_ids_to_apply = $helper_id > 0 ? [$helper_id] : []; // 0 => clear
  }

  $helper_labels = array_merge(
    norm_list($in['helper_names'] ?? []),
    norm_list($in['helper_name']  ?? [])
  );
  if (!empty($helper_labels)) {
    $resolved = find_helpers_by_labels($db, $helper_labels);
    $helper_ids_to_apply = array_values(array_unique(array_merge($helper_ids_to_apply ?? [], $resolved)));
  }

  // driver sync
  $set_driver_ids = array_values(array_unique(array_filter(
    array_map('intval', (array)($in['set_driver_ids'] ?? [])), fn($v)=> $v>0
  )));
  $doSyncDrivers = !empty($set_driver_ids);

  /* ---------- Validate trip state ---------- */
  $st = $db->prepare("SELECT status FROM trips WHERE id=? LIMIT 1");
  $st->bind_param('i',$trip_id);
  $st->execute();
  $res = $st->get_result();
  $row = $res ? $res->fetch_assoc() : null;
  $st->close();

  if (!$row) json_out(['ok'=>false,'error'=>'Trip not found'], 404);
  $status = strtolower((string)($row['status'] ?? ''));
  if ($status !== 'ongoing' && $status !== '1') json_out(['ok'=>false,'error'=>'Trip is not ongoing'], 400);

  /* vehicle/plant for assignments + optional drivers.plant_id mirror */
  $tp = get_trip_vehicle_and_plant($db, $trip_id);
  if (!$tp) json_out(['ok'=>false,'error'=>'Trip vehicle not found'], 500);
  $vehicle_id = (int)$tp['vehicle_id'];
  $plant_id   = (int)$tp['plant_id'];

  $has_trip_helpers_table = table_exists($db,'trip_helpers');
  $has_trip_helper_legacy = table_exists($db,'trip_helper');
  $drivers_have_plant_col = has_col($db,'drivers','plant_id');
  $has_helper_text_col    = has_col($db,'trips','helper_text');

  /* ---------- TRANSACTION ---------- */
  $db->begin_transaction();

  // Update note
  if ($note !== null) {
    $u = $db->prepare("UPDATE trips SET note=? WHERE id=?");
    $u->bind_param('si',$note,$trip_id);
    $u->execute();
    $u->close();
  }

  // Helpers upsert/clear
  if ($helper_ids_to_apply !== null) {
    if ($has_trip_helpers_table) {
      $del = $db->prepare("DELETE FROM trip_helpers WHERE trip_id=?");
      $del->bind_param('i',$trip_id);
      $del->execute(); $del->close();

      if (!empty($helper_ids_to_apply)) {
        $ins = $db->prepare("INSERT IGNORE INTO trip_helpers (trip_id, helper_id) VALUES (?, ?)");
        foreach ($helper_ids_to_apply as $hid) {
          $ins->bind_param('ii',$trip_id,$hid);
          $ins->execute();
        }
        $ins->close();
      }
    } elseif ($has_helper_text_col) {
      $val = !empty($helper_ids_to_apply) ? implode(',', array_map('strval', $helper_ids_to_apply)) : '';
      $u = $db->prepare("UPDATE trips SET helper_text=? WHERE id=?");
      $u->bind_param('si',$val,$trip_id);
      $u->execute(); $u->close();
    }

    if ($has_trip_helper_legacy) {
      $d = $db->prepare("DELETE FROM trip_helper WHERE trip_id=?");
      $d->bind_param('i',$trip_id);
      $d->execute(); $d->close();

      if (!empty($helper_ids_to_apply)) {
        $primary = (int)$helper_ids_to_apply[0];
        if ($primary > 0) {
          $i = $db->prepare("INSERT INTO trip_helper (trip_id, helper_id) VALUES (?, ?)");
          $i->bind_param('ii',$trip_id,$primary);
          $i->execute(); $i->close();
        }
      }
    } elseif ($has_helper_text_col && empty($helper_ids_to_apply)) {
      $u = $db->prepare("UPDATE trips SET helper_text = NULL WHERE id=?");
      $u->bind_param('i',$trip_id);
      $u->execute(); $u->close();
    }

    if (!empty($helper_ids_to_apply)) {
      foreach ($helper_ids_to_apply as $hid) {
        upsert_assignment($db, $hid, $vehicle_id, $plant_id);
        if ($drivers_have_plant_col) {
          $u = $db->prepare("UPDATE drivers SET plant_id=? WHERE id=?");
          $u->bind_param('ii', $plant_id, $hid);
          $u->execute(); $u->close();
        }
      }
    }
  }

  // Customers (replace or add)
  if (!empty($set_customers) && table_exists($db,'trip_customers')) {
    $del = $db->prepare("DELETE FROM trip_customers WHERE trip_id=?");
    $del->bind_param('i',$trip_id);
    $del->execute(); $del->close();

    $ins = $db->prepare("INSERT INTO trip_customers (trip_id, customer_name) VALUES (?, ?)");
    foreach ($set_customers as $c) {
      $ins->bind_param('is',$trip_id,$c);
      $ins->execute();
    }
    $ins->close();
  } elseif (!empty($add_customers) && table_exists($db,'trip_customers')) {
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
      $key = strtolower(trim($c)); if ($key==='' || isset($existing[$key])) continue;
      $ins->bind_param('is',$trip_id,$c);
      $ins->execute();
      $existing[$key] = true;
    }
    $ins->close();
  }

  // Driver sync
  if ($doSyncDrivers && table_exists($db,'trip_drivers')) {
    $current = [];
    $r = $db->prepare("SELECT driver_id FROM trip_drivers WHERE trip_id=?");
    $r->bind_param('i',$trip_id);
    $r->execute();
    $g = $r->get_result();
    while ($rw = $g->fetch_assoc()) { $current[(int)$rw['driver_id']] = true; }
    $r->close();
    $target = array_fill_keys($set_driver_ids, true);

    $ins = $db->prepare("INSERT IGNORE INTO trip_drivers (trip_id, driver_id) VALUES (?, ?)");
    foreach ($set_driver_ids as $did) {
      if (!isset($current[$did])) { $ins->bind_param('ii',$trip_id,$did); $ins->execute(); }
    }
    $ins->close();

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

    foreach ($set_driver_ids as $did) {
      upsert_assignment($db, $did, $vehicle_id, $plant_id);
      if ($drivers_have_plant_col) {
        $u = $db->prepare("UPDATE drivers SET plant_id=? WHERE id=?");
        $u->bind_param('ii', $plant_id, $did);
        $u->execute(); $u->close();
      }
    }
  }

  $db->commit();

  /* ---------- SUCCESS (best-effort helper hydration) ---------- */
  $response = ['ok'=>true, 'status'=>'ok', 'trip_id'=>$trip_id];

  try {
    $hasPlural = table_exists($db,'trip_helpers');
    $hasLegacy = table_exists($db,'trip_helper');

    if ($hasPlural || $hasLegacy) {
      $sql = ($hasPlural && $hasLegacy)
        ? "SELECT d.id, d.name, COALESCE(d.contact,'') contact
             FROM (
               SELECT trip_id, helper_id FROM trip_helpers
               UNION
               SELECT trip_id, helper_id FROM trip_helper
             ) th
             JOIN drivers d ON d.id=th.helper_id
            WHERE th.trip_id=? ORDER BY d.name"
        : ($hasPlural
          ? "SELECT d.id, d.name, COALESCE(d.contact,'') contact
               FROM trip_helpers th JOIN drivers d ON d.id=th.helper_id
              WHERE th.trip_id=? ORDER BY d.name"
          : "SELECT d.id, d.name, COALESCE(d.contact,'') contact
               FROM trip_helper th JOIN drivers d ON d.id=th.helper_id
              WHERE th.trip_id=? ORDER BY d.name");

      $qh = $db->prepare($sql);
      $qh->bind_param('i', $trip_id);
      $qh->execute();
      $rs = $qh->get_result();
      $helpers=[]; $names=[];
      while ($h=$rs->fetch_assoc()){
        $helpers[]=['id'=>(int)$h['id'],'name'=>(string)$h['name'],'contact'=>(string)$h['contact']];
        if ($h['name']!=='') $names[]=(string)$h['name'];
      }
      $qh->close();

      $response['helpers'] = $helpers;
      if (!empty($names)) {
        sort($names, SORT_NATURAL|SORT_FLAG_CASE);
        $response['helper_names'] = implode(', ', $names);
      } else {
        $response['helper_names'] = '';
      }
    }
  } catch (Throwable $e) {
    // ignore hydration errors; keep success
  }

  json_out($response, 200);

} catch (Throwable $e) {
  json_out(['ok'=>false,'error'=>'Failed to update ongoing trip','detail'=>$e->getMessage()], 500);
}

// no closing tag
