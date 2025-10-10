<?php
// TripDetails/api/trips_list.php
// Lists trips for a vehicle with optional driver filter + pagination
// Safe JSON responses + lightweight logging

@ini_set('display_errors', '0');
@ini_set('log_errors', '1');
$__LOG = rtrim(sys_get_temp_dir(), DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . 'td_trips_list.log';
@ini_set('error_log', $__LOG);

function _tl_log(string $m): void {
  global $__LOG;
  @error_log('[trips_list] '.$m);
  @file_put_contents($__LOG, '['.date('c').'] '.$m."\n", FILE_APPEND);
}
function _json($payload, int $status = 200): void {
  if (function_exists('ob_get_level')) { while (ob_get_level() > 0) @ob_end_clean(); }
  if (!headers_sent()) {
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, private');
  }
  echo json_encode($payload, JSON_UNESCAPED_UNICODE);
  exit;
}
register_shutdown_function(function(){
  $e = error_get_last();
  if ($e && in_array($e['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR], true)) {
    _tl_log('FATAL: '.$e['message'].' @ '.$e['file'].':'.$e['line']);
    if (!headers_sent()) header('Content-Type: application/json; charset=utf-8');
    http_response_code(500);
    echo json_encode(['ok'=>false,'error'=>'Fatal: '.$e['message']]);
  }
});

require_once __DIR__ . '/_auth_guard.php'; // also loads bootstrap/json helpers if present

// Fallback helpers if bootstrap didn't define them
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
  // DB handle
  /** @var mysqli $mysqli */
  $db = (isset($conn) && $conn instanceof mysqli) ? $conn
       : ((isset($mysqli) && $mysqli instanceof mysqli) ? $mysqli
       : ((isset($con) && $con instanceof mysqli) ? $con : null));
  if (!$db) _json(['ok'=>false,'error'=>'No DB connection'], 500);
  @$db->set_charset('utf8mb4');

  // Inputs
  $vehicle_id = isset($_GET['vehicle_id']) && ctype_digit((string)$_GET['vehicle_id']) ? (int)$_GET['vehicle_id'] : 0;
  if ($vehicle_id <= 0) _json(['ok'=>true,'rows'=>[], 'has_more'=>false]);

  $driver_ids_csv = trim((string)($_GET['driver_ids'] ?? ''));
  $driver_ids = [];
  if ($driver_ids_csv !== '') {
    foreach (explode(',', $driver_ids_csv) as $x) {
      $x = trim($x);
      if ($x !== '' && ctype_digit($x)) $driver_ids[] = (int)$x;
    }
  }

  // Pagination
  $limit  = isset($_GET['limit'])  && ctype_digit((string)$_GET['limit'])  ? (int)$_GET['limit']  : 15;
  $offset = isset($_GET['offset']) && ctype_digit((string)$_GET['offset']) ? (int)$_GET['offset'] : 0;
  if ($limit <= 0)  $limit = 15;
  if ($limit > 100) $limit = 100;
  if ($offset < 0)  $offset = 0;

  // Schema flags
  $hasTrips         = table_exists($db,'trips');
  if (!$hasTrips) _json(['ok'=>true,'rows'=>[], 'has_more'=>false]);

  $hasTripDrivers   = table_exists($db,'trip_drivers');
  $hasTripHelperTbl = table_exists($db,'trip_helper');   // legacy single helper
  $hasTripHelpers   = table_exists($db,'trip_helpers');  // future multi-helper
  $hasTripCustomers = table_exists($db,'trip_customers');
  $hasDrivers       = table_exists($db,'drivers');

  $hasTripsStatus   = has_col($db,'trips','status');
  $hasTripsDriversTx= has_col($db,'trips','drivers_text');
  $hasTripsHelperTx = has_col($db,'trips','helper_text');
  $hasTripsCustTx   = has_col($db,'trips','customers_text');

  // Driver display column
  $drvNameCol = 'name';
  if ($hasDrivers) {
    foreach (['name','driver_name','full_name'] as $c) { if (has_col($db,'drivers',$c)) { $drvNameCol = $c; break; } }
  }

  // Build field list
  $F = [];
  $F[] = "t.id";
  $F[] = "t.vehicle_id";
  $F[] = "t.start_date";
  $F[] = "t.start_km";
  $F[] = "DATE_FORMAT(t.start_date,'%d-%m-%Y') AS start_date_fmt";
  $F[] = "t.end_date";
  $F[] = "t.end_km";
  $F[] = "IF(t.end_date IS NULL, NULL, DATE_FORMAT(t.end_date,'%d-%m-%Y')) AS end_date_fmt";
  $F[] = has_col($db,'trips','total_km')
        ? "t.total_km"
        : "(CASE WHEN t.end_km IS NULL OR t.start_km IS NULL THEN NULL ELSE (t.end_km - t.start_km) END) AS total_km";
  $F[] = $hasTripsStatus
        ? "t.status"
        : "(CASE WHEN t.end_km IS NULL THEN 'ongoing' ELSE 'ended' END) AS status";

  // Drivers string
// ------ Drivers string (robust fallbacks) ------
// 1) trip_drivers → drivers.name
// 2) trips.drivers_text
// 3) trips.driver_name / trips.drivers (common ad-hoc columns)
// 4) trips.driver_id → drivers.name
$hasTripsDriverId   = has_col($db,'trips','driver_id');
$hasTripsDriverName = has_col($db,'trips','driver_name');
$hasTripsDriversCol = has_col($db,'trips','drivers'); // sometimes people store comma text here

if ($hasTripDrivers && $hasDrivers) {
  $F[] = "COALESCE((
            SELECT GROUP_CONCAT(DISTINCT d.`$drvNameCol` ORDER BY d.`$drvNameCol` SEPARATOR ', ')
            FROM trip_drivers td
            JOIN drivers d ON d.id = td.driver_id
            WHERE td.trip_id = t.id
          ),
          " . ($hasTripsDriversTx ? "NULLIF(t.drivers_text,'')" : "NULL") . ",
          " . ($hasTripsDriverName ? "NULLIF(t.driver_name,'')" : "NULL") . ",
          " . ($hasTripsDriversCol ? "NULLIF(t.drivers,'')" : "NULL") . ",
          " . ($hasTripsDriverId && $hasDrivers
                ? "(SELECT d2.`$drvNameCol` FROM drivers d2 WHERE d2.id=t.driver_id LIMIT 1)"
                : "NULL") . ",
          ''
         ) AS drivers";
} elseif ($hasTripsDriversTx || $hasTripsDriverName || $hasTripsDriversCol || ($hasTripsDriverId && $hasDrivers)) {
  $pieces = [];
  if ($hasTripsDriversTx)  $pieces[] = "NULLIF(t.drivers_text,'')";
  if ($hasTripsDriverName) $pieces[] = "NULLIF(t.driver_name,'')";
  if ($hasTripsDriversCol) $pieces[] = "NULLIF(t.drivers,'')";
  if ($hasTripsDriverId && $hasDrivers) {
    $pieces[] = "(SELECT d2.`$drvNameCol` FROM drivers d2 WHERE d2.id=t.driver_id LIMIT 1)";
  }
  $F[] = "COALESCE(" . implode(',', $pieces) . ", '') AS drivers";
} else {
  $F[] = "'' AS drivers";
}

  // Helpers string + ids csv (works with either trip_helpers or legacy trip_helper)
  if ($hasTripHelpers && $hasDrivers) {
    $F[] = "COALESCE((SELECT GROUP_CONCAT(DISTINCT d3.`$drvNameCol` ORDER BY d3.`$drvNameCol` SEPARATOR ', ')
                      FROM trip_helpers th3 JOIN drivers d3 ON d3.id=th3.helper_id
                      WHERE th3.trip_id=t.id), '') AS helpers_csv";
    $F[] = "COALESCE((SELECT GROUP_CONCAT(DISTINCT th4.helper_id ORDER BY th4.helper_id SEPARATOR ',')
                      FROM trip_helpers th4 WHERE th4.trip_id=t.id), '') AS helper_ids_csv";
  } elseif ($hasTripHelperTbl && $hasDrivers) {
    $F[] = "COALESCE((SELECT d2.`$drvNameCol`
                      FROM trip_helper th JOIN drivers d2 ON d2.id=th.helper_id
                      WHERE th.trip_id=t.id LIMIT 1), '') AS helpers_csv";
    $F[] = "COALESCE((SELECT th2.helper_id FROM trip_helper th2 WHERE th2.trip_id=t.id LIMIT 1), '') AS helper_ids_csv";
  } elseif ($hasTripsHelperTx) {
    $F[] = "COALESCE(t.helper_text,'') AS helpers_csv";
    $F[] = "'' AS helper_ids_csv";
  } else {
    $F[] = "'' AS helpers_csv";
    $F[] = "'' AS helper_ids_csv";
  }

  // Customers string
  if ($hasTripCustomers) {
    $custNameCol = 'customer_name';
    foreach (['customer_name','name','title'] as $c) { if (has_col($db,'trip_customers',$c)) { $custNameCol = $c; break; } }
    $F[] = "COALESCE((SELECT GROUP_CONCAT(tc.`$custNameCol` ORDER BY tc.id SEPARATOR ', ')
                      FROM trip_customers tc WHERE tc.trip_id=t.id), '') AS customers";
  } elseif ($hasTripsCustTx) {
    $F[] = "COALESCE(t.customers_text,'') AS customers";
  } else {
    $F[] = "'' AS customers";
  }

  // Base SQL
  $sql   = "SELECT ".implode(", ", $F)." FROM trips t WHERE t.vehicle_id=?";
  $types = "i"; $params = [$vehicle_id];

  if (!empty($driver_ids) && $hasTripDrivers) {
    $in = implode(',', array_fill(0, count($driver_ids), '?'));
    $sql .= " AND EXISTS (SELECT 1 FROM trip_drivers td2 WHERE td2.trip_id=t.id AND td2.driver_id IN ($in))";
    $types .= str_repeat('i', count($driver_ids));
    $params = array_merge($params, $driver_ids);
  }

  // Order + pagination (ongoing first, then newest id)
  $sql .= " ORDER BY (CASE WHEN t.end_km IS NULL THEN 1 ELSE 0 END) DESC, t.id DESC LIMIT ? OFFSET ?";

  // Bind limit/offset
  $types .= "ii";
  $params[] = $limit + 1; // fetch one extra to know has_more
  $params[] = $offset;

  $st = $db->prepare($sql);
  if (!$st) { _tl_log('prepare failed: '.$db->error); _json(['ok'=>false,'error'=>'Query prepare failed'], 500); }

  // bind_param requires refs when done dynamically
  $bind = array_merge([$types], $params);
  $refs = [];
  foreach ($bind as $k => &$v) $refs[$k] = &$v;
  if (!@call_user_func_array([$st,'bind_param'], $refs)) {
    _tl_log('bind_param failed (types='.$types.', count='.count($params).')');
    _json(['ok'=>false,'error'=>'Bind failed'], 500);
  }

  if (!$st->execute()) {
    $err = $st->error; $st->close();
    _tl_log('execute failed: '.$err);
    _json(['ok'=>false,'error'=>'Query execute failed'], 500);
  }

  $res = $st->get_result();

  $rowsOut = [];
  $count   = 0;
  $hasMore = false;

  while ($r = $res->fetch_assoc()) {
    $count++;
    if ($count > $limit) { $hasMore = true; break; }

    // Parse helper_ids array from CSV
    $helper_ids = [];
    $csv = (string)($r['helper_ids_csv'] ?? '');
    if ($csv !== '') {
      foreach (explode(',', $csv) as $hx) {
        $hx = trim($hx);
        if ($hx !== '' && ctype_digit($hx)) $helper_ids[] = (int)$hx;
      }
    }

    $helpersString = $r['helpers_csv'] ?? '';

    $rowsOut[] = [
      'id'             => isset($r['id']) ? (int)$r['id'] : null,
      'vehicle_id'     => isset($r['vehicle_id']) ? (int)$r['vehicle_id'] : null,
      'start_date'     => $r['start_date'] ?? null,
      'start_km'       => isset($r['start_km']) ? (int)$r['start_km'] : null,
      'status'         => $r['status'] ?? null,
      'end_date'       => $r['end_date'] ?? null,
      'end_km'         => isset($r['end_km']) ? (int)$r['end_km'] : null,
      'total_km'       => isset($r['total_km']) ? (int)$r['total_km'] : null,
      'start_date_fmt' => $r['start_date_fmt'] ?? null,
      'end_date_fmt'   => $r['end_date_fmt'] ?? null,
      'drivers'        => $r['drivers'] ?? '',
      // Preferred & legacy keys for your UI:
      'helpers'        => $helpersString,
      'helper'         => $helpersString,
      'helper_ids'     => $helper_ids,
      'customers'      => $r['customers'] ?? '',
    ];
  }
  $st->close();

  // Your frontend accepts either an array OR {rows, has_more}
  _json(['ok'=>true, 'rows'=>$rowsOut, 'has_more'=>$hasMore]);

} catch (Throwable $e) {
  _tl_log('EXC: '.$e->getMessage().' @ '.$e->getFile().':'.$e->getLine());
  _json(['ok'=>false,'error'=>'Server exception: '.$e->getMessage()], 500);
}