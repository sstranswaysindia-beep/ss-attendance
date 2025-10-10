<?php
//declare(strict_types=1);

/* ---- Robust logging ---- */
$__logDir = __DIR__ . '/logs';
if (!is_dir($__logDir)) { @mkdir($__logDir, 0775, true); }
$__logFile = $__logDir . '/php-error.log';
@ini_set('log_errors','1');
@ini_set('display_errors','0');
if (is_dir($__logDir)) { @ini_set('error_log', $__logFile); }
error_log('[trips_end] boot');

/* ---- Load bootstrap FIRST, then auth ---- */
require __DIR__ . '/bootstrap.php';
require __DIR__ . '/_auth_guard.php';

/* ---- JSON helper ---- */
if (!function_exists('json_out') && function_exists('json')) {
  function json_out($payload, int $status = 200): void { json($payload, $status); }
}
if (!function_exists('json_out')) {
  function json_out($payload, int $status = 200): void {
    if (function_exists('ob_get_level')) { while (ob_get_level() > 0) @ob_end_clean(); }
    if (!headers_sent()) {
      http_response_code($status);
      header('Content-Type: application/json; charset=utf-8');
      header('Cache-Control: no-store, no-cache, must-revalidate, private');
    }
    echo json_encode($payload, JSON_UNESCAPED_UNICODE);
    exit;
  }
}

/* ---- Resolve mysqli ---- */
/** @var mysqli|null $mysqli */
/** @var mysqli|null $conn */
/** @var mysqli|null $con */
$db = null;
if (isset($mysqli) && $mysqli instanceof mysqli) $db = $mysqli;
elseif (isset($conn) && $conn instanceof mysqli) $db = $conn;
elseif (isset($con)  && $con  instanceof mysqli) $db = $con;
if (!$db || $db->connect_errno) { error_log('[trips_end] no db'); json_out(['ok'=>false,'error'=>'Database connection not available'], 500); }
@$db->set_charset('utf8mb4');
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

/* ---- Helper guards ---- */
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
    $r = $db->query("SHOW COLUMNS FROM `{$t}` LIKE '{$c}'");
    return $r && $r->num_rows > 0;
  }
}

/* ---- Helpers ---- */
function read_input_array(): array {
  if (!empty($_POST)) return $_POST;
  $ct  = strtolower((string)($_SERVER['CONTENT_TYPE'] ?? $_SERVER['HTTP_CONTENT_TYPE'] ?? ''));
  $raw = file_get_contents('php://input') ?: '';
  if ($raw !== '' && strpos($ct, 'application/json') !== false) {
    $arr = json_decode($raw, true);
    if (is_array($arr)) return $arr;
  }
  if ($raw !== '') {
    $arr = json_decode($raw, true);
    if (is_array($arr)) return $arr;
  }
  return [];
}
function to_ymd(?string $s): ?string {
  if (!$s) return null;
  $s = trim($s);
  if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $s)) return $s;
  if (preg_match('/^(\d{2})[-\/](\d{2})[-\/](\d{4})$/', $s, $m)) return $m[3].'-'.$m[2].'-'.$m[1];
  return $s;
}

/* ---- Input ---- */
try {
  if (!table_exists($db,'trips')) json_out(['ok'=>false,'error'=>'trips table missing'], 500);

  $data     = read_input_array();
  $trip_id  = (int)($data['trip_id'] ?? 0);
  $end_date = to_ymd(is_string($data['end_date'] ?? null) ? $data['end_date'] : null);

  $raw_end_km = $data['end_km'] ?? null;
  $end_km = ($raw_end_km === null || $raw_end_km === '') ? null : (int)str_replace(',', '', (string)$raw_end_km);

  if ($trip_id <= 0)                    json_out(['ok'=>false,'error'=>'trip_id required'], 422);
  if (!$end_date || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $end_date))
                                        json_out(['ok'=>false,'error'=>'end_date must be YYYY-MM-DD'], 422);
  if ($end_km === null || $end_km < 0)  json_out(['ok'=>false,'error'=>'end_km required/invalid'], 422);

  /* fetch current trip */
  $cols = ['start_km'];
  if (has_col($db,'trips','status'))     $cols[] = 'status';
  if (has_col($db,'trips','end_km'))     $cols[] = 'end_km';
  if (has_col($db,'trips','end_date'))   $cols[] = 'end_date';
  if (has_col($db,'trips','start_date')) $cols[] = 'start_date';

  $sql = "SELECT ".implode(',', $cols)." FROM trips WHERE id=? LIMIT 1";
  $st  = $db->prepare($sql);
  $st->bind_param('i', $trip_id);
  $st->execute();
  $res = $st->get_result();
  if (!$res || !$res->num_rows) { $st->close(); json_out(['ok'=>false,'error'=>'Trip not found'], 404); }
  $row = $res->fetch_assoc();
  $st->close();

  $start_km    = (int)($row['start_km'] ?? 0);
  $start_date  = isset($row['start_date']) ? to_ymd((string)$row['start_date']) : null;

  $alreadyEnded = false;
  if (array_key_exists('status',$row)) {
    $status_norm = strtolower((string)($row['status'] ?? ''));
    $alreadyEnded = ($status_norm === 'ended' || $status_norm === '0' || $status_norm === 'false');
  } else {
    $alreadyEnded = (!empty($row['end_km']) || !empty($row['end_date']));
  }
  if ($alreadyEnded) json_out(['ok'=>false,'error'=>'Trip already ended'], 409);

  /* business rules */
  // 1) Strictly greater: no duplicate start/end KM allowed
  if ($end_km <= $start_km) {
    json_out([
      'ok'    => false,
      'error' => "End KM must be greater than Start KM (Start: {$start_km})"
    ], 422);
  }

  // 2) End date must be >= start date (when start_date column is present)
  if ($start_date && preg_match('/^\d{4}-\d{2}-\d{2}$/', $start_date)) {
    if (strcmp($end_date, $start_date) < 0) {
      json_out([
        'ok'    => false,
        'error' => "End date ({$end_date}) cannot be before Start date ({$start_date})"
      ], 422);
    }
  }

  /* build UPDATE based on available columns */
  $set   = [];
  $types = '';
  $vals  = [];

  if (has_col($db,'trips','end_date')) { $set[] = 'end_date=?'; $types.='s'; $vals[] = $end_date; }
  if (has_col($db,'trips','end_km'))   { $set[] = 'end_km=?';   $types.='i'; $vals[] = $end_km; }
  if (has_col($db,'trips','status'))   { $set[] = "status='ended'"; }
  if (has_col($db,'trips','ended_at')) { $set[] = 'ended_at=NOW()'; }

  if (empty($set)) json_out(['ok'=>false,'error'=>'No suitable columns to update (check schema)'], 500);

  $sqlU = "UPDATE trips SET ".implode(', ', $set)." WHERE id=?";
  $u = $db->prepare($sqlU);
  $types .= 'i'; $vals[] = $trip_id;
  $bind = [$types]; foreach ($vals as $k=>&$v) { $bind[] = &$v; }
  call_user_func_array([$u,'bind_param'], $bind);
  $u->execute(); $u->close();

  /* total_km */
  $total_km = null;
  if (has_col($db,'trips','total_km')) {
    $q = $db->prepare("SELECT total_km FROM trips WHERE id=?");
    $q->bind_param('i', $trip_id);
    $q->execute();
    $r = $q->get_result();
    if ($r && $r->num_rows) { $total_km = (int)($r->fetch_assoc()['total_km'] ?? 0); }
    $q->close();
  } else {
    $total_km = max(0, (int)$end_km - (int)$start_km);
  }

  json_out(['ok'=>true, 'trip_id'=>$trip_id, 'total_km'=>$total_km]);

} catch (mysqli_sql_exception $e) {
  error_log("[trips_end] SQL {$e->getCode()}: {$e->getMessage()}");
  json_out(['ok'=>false,'error'=>'Database error','code'=>(int)$e->getCode()], 500);
} catch (Throwable $e) {
  error_log("[trips_end] Fatal: {$e->getMessage()} @ {$e->getFile()}:{$e->getLine()}");
  json_out(['ok'=>false,'error'=>'Unexpected server error'], 500);
}