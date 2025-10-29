<?php
// TripDetails/api/trip_details.php
// Returns a single trip with driver_ids, helper_ids (multi), helper_id (legacy first), helpers[] names, and customers[]

require_once __DIR__ . '/bootstrap.php';     // sets up session, $mysqli, json(), helpers
require_once __DIR__ . '/_auth_guard.php';   // 401 if not logged in

header('Content-Type: application/json; charset=utf-8');
@ini_set('display_errors','0');
@ini_set('log_errors','1');
error_log('[trip_details] boot');

// Safe fallbacks if helpers not present
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

try {
  // --- choose mysqli handle ---
  /** @var mysqli|null $mysqli */
  /** @var mysqli|null $conn */
  /** @var mysqli|null $con */
  $db = null;
  if (isset($mysqli) && $mysqli instanceof mysqli) $db = $mysqli;
  elseif (isset($conn) && $conn instanceof mysqli) $db = $conn;
  elseif (isset($con)  && $con  instanceof mysqli) $db = $con;

  if (!$db || $db->connect_errno) {
    error_log('[trip_details] DB handle missing or connect error');
    json(['ok'=>false,'error'=>'Database connection not available'], 500);
  }
  @$db->set_charset('utf8mb4');
  mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

  // --- input ---
  $trip_id = isset($_GET['trip_id']) && is_numeric($_GET['trip_id']) ? (int)$_GET['trip_id'] : 0;
  if ($trip_id <= 0) {
    json(['ok'=>false,'error'=>'trip_id required'], 400);
  }

  // --- detect schema ---
  $hasTrips         = table_exists($db,'trips');
  $hasTripDrivers   = table_exists($db,'trip_drivers');
  $hasTripHelper    = table_exists($db,'trip_helper');   // legacy
  $hasTripHelpers   = table_exists($db,'trip_helpers');  // plural
  $hasTripCustomers = table_exists($db,'trip_customers');
  $hasDrivers       = table_exists($db,'drivers');
  $hasHelpers       = table_exists($db,'helpers');

  if (!$hasTrips) {
    json(['ok'=>false,'error'=>'trips table missing'], 500);
  }

  $helperNameCol = 'name';
  if ($hasHelpers) {
    foreach (['name','helper_name','full_name','display_name'] as $c) {
      if (has_col($db,'helpers',$c)) { $helperNameCol = $c; break; }
    }
  } else {
    $helperNameCol = null;
  }

  // columns to fetch from trips
  $fields = ['id','vehicle_id','start_date','start_km','end_date','end_km','note'];
  if (has_col($db,'trips','customers_text')) $fields[] = 'customers_text';
  if (has_col($db,'trips','drivers_text'))   $fields[] = 'drivers_text';

  // base row
  $sql = 'SELECT '.implode(',', $fields).' FROM trips WHERE id=? LIMIT 1';
  $st  = $db->prepare($sql);
  $st->bind_param('i', $trip_id);
  $st->execute();
  $res  = $st->get_result();
  $base = $res ? $res->fetch_assoc() : null;
  $st->close();

  if (!$base) {
    json(['ok'=>false,'error'=>'Trip not found'], 404);
  }

  // driver_ids (from junction if available)
  $driver_ids = [];
  if ($hasTripDrivers && has_col($db,'trip_drivers','trip_id') && has_col($db,'trip_drivers','driver_id')) {
    $s = $db->prepare('SELECT driver_id FROM trip_drivers WHERE trip_id=?');
    $s->bind_param('i', $trip_id);
    $s->execute();
    $r = $s->get_result();
    while ($row = $r->fetch_assoc()) {
      $driver_ids[] = (int)$row['driver_id'];
    }
    $s->close();
  }

  // helpers (multi-aware)
  $helper_ids = [];
  $helpers    = []; // names
  if ($hasTripHelpers) {
    $h = $db->prepare('SELECT helper_id FROM trip_helpers WHERE trip_id=? ORDER BY helper_id');
    $h->bind_param('i', $trip_id);
    $h->execute();
    $hr = $h->get_result();
    while ($row = $hr->fetch_assoc()) { $helper_ids[] = (int)$row['helper_id']; }
    $h->close();

    if (!empty($helper_ids)) {
      $nameMap = [];
      if ($hasDrivers) {
        $nameCol = 'name';
        foreach (['name','driver_name','full_name'] as $c) { if (has_col($db,'drivers',$c)) { $nameCol=$c; break; } }
        $marks = implode(',', array_fill(0, count($helper_ids), '?'));
        $types = str_repeat('i', count($helper_ids));
        $q = $db->prepare("SELECT id, `$nameCol` AS nm FROM drivers WHERE id IN ($marks)");
        $q->bind_param($types, ...$helper_ids);
        $q->execute();
        $qr = $q->get_result();
        while ($row = $qr->fetch_assoc()) { $nameMap[(int)$row['id']] = (string)$row['nm']; }
        $q->close();
      }
      if ($hasHelpers && $helperNameCol) {
        $missing = array_values(array_filter($helper_ids, fn($hid) => !isset($nameMap[$hid])));
        if (!empty($missing)) {
          $marks = implode(',', array_fill(0, count($missing), '?'));
          $types = str_repeat('i', count($missing));
          $sql = "SELECT id, `$helperNameCol` AS nm FROM helpers WHERE id IN ($marks)";
          $q = $db->prepare($sql);
          $q->bind_param($types, ...$missing);
          $q->execute();
          $qr = $q->get_result();
          while ($row = $qr->fetch_assoc()) { $nameMap[(int)$row['id']] = (string)$row['nm']; }
          $q->close();
        }
      }
      foreach ($helper_ids as $hid) {
        $helpers[] = isset($nameMap[$hid]) ? $nameMap[$hid] : ("Helper #".$hid);
      }
    }
  } elseif ($hasTripHelper) {
    // legacy single helper -> present as array(1) for ids + names
    $h = $db->prepare('SELECT helper_id FROM trip_helper WHERE trip_id=? LIMIT 1');
    $h->bind_param('i', $trip_id);
    $h->execute();
    $h->bind_result($hid);
    if ($h->fetch()) {
      $hid = $hid !== null ? (int)$hid : null;
      if ($hid) $helper_ids = [$hid];
    }
    $h->close();

    if (!empty($helper_ids)) {
      $hid = $helper_ids[0];
      $name = null;
      if ($hasDrivers) {
        $nameCol = 'name';
        foreach (['name','driver_name','full_name'] as $c) { if (has_col($db,'drivers',$c)) { $nameCol=$c; break; } }
        $q = $db->prepare("SELECT `$nameCol` FROM drivers WHERE id=? LIMIT 1");
        $q->bind_param('i', $hid);
        $q->execute();
        $q->bind_result($nm);
        if ($q->fetch()) $name = (string)$nm;
        $q->close();
      }
      if ($name === null && $hasHelpers && $helperNameCol) {
        $q = $db->prepare("SELECT `$helperNameCol` FROM helpers WHERE id=? LIMIT 1");
        $q->bind_param('i', $hid);
        $q->execute();
        $q->bind_result($nm);
        if ($q->fetch()) $name = (string)$nm;
        $q->close();
      }
      if ($name !== null) {
        $helpers = [ $name ];
      }
    }
  }

  // customers list
  $customers = [];
  if ($hasTripCustomers) {
    $custCol = 'customer_name';
    foreach (['customer_name','name','title'] as $c) { if (has_col($db,'trip_customers',$c)) { $custCol=$c; break; } }
    $c = $db->prepare("SELECT `$custCol` AS name FROM trip_customers WHERE trip_id=? ORDER BY id");
    $c->bind_param('i', $trip_id);
    $c->execute();
    $cr = $c->get_result();
    while ($row = $cr->fetch_assoc()) {
      $nm = trim((string)($row['name'] ?? ''));
      if ($nm !== '') $customers[] = $nm;
    }
    $c->close();
  } elseif (!empty($base['customers_text'])) {
    foreach (explode(',', (string)$base['customers_text']) as $nm) {
      $nm = trim($nm);
      if ($nm !== '') $customers[] = $nm;
    }
  }

  // legacy single helper_id for compatibility
  $legacy_helper_id = !empty($helper_ids) ? $helper_ids[0] : null;

  // output
  json([
    'ok'           => true,
    'trip_id'      => (int)$base['id'],
    'vehicle_id'   => (int)$base['vehicle_id'],
    'start_date'   => $base['start_date'],
    'start_km'     => isset($base['start_km']) ? (int)$base['start_km'] : null,
    'end_date'     => $base['end_date'],
    'end_km'       => isset($base['end_km']) ? (int)$base['end_km'] : null,
    'note'         => (string)($base['note'] ?? ''),
    'driver_ids'   => $driver_ids,
    'helper_id'    => $legacy_helper_id, // legacy
    'helper_ids'   => $helper_ids,       // new, multi
    'helpers'      => $helpers,          // helper names (parallel order to helper_ids)
    'customers'    => $customers,
  ]);

} catch (mysqli_sql_exception $e) {
  error_log('[trip_details] SQL '.$e->getCode().': '.$e->getMessage());
  json(['ok'=>false,'error'=>'Database error','code'=>(int)$e->getCode()], 500);
} catch (Throwable $e) {
  error_log('[trip_details] Fatal: '.$e->getMessage().' @ '.$e->getFile().':'.$e->getLine());
  json(['ok'=>false,'error'=>'Unexpected server error'], 500);
}
