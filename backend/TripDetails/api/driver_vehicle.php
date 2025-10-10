<?php
/**
 * TripDetails/api/driver_vehicle.php
 * - GET : returns the last assigned vehicle for the logged-in driver (or empty for admin/supervisor).
 * - POST: sets/clears the driver's vehicle assignment (drivers only).
 */

/* ---- Robust logging ---- */
$__logDir = __DIR__ . '/logs';
if (!is_dir($__logDir)) { @mkdir($__logDir, 0775, true); }
$__logFile = $__logDir . '/php-error.log';
@ini_set('log_errors','1');
@ini_set('display_errors','0');
if (is_dir($__logDir)) { @ini_set('error_log', $__logFile); }
error_log('[driver_vehicle] boot');

/* ---- Force JSON / no-store ---- */
@header('Content-Type: application/json; charset=utf-8');
@header('Cache-Control: no-store, no-cache, must-revalidate, private');
@header('Pragma: no-cache');

/* ---- Load bootstrap FIRST, then auth ---- */
require __DIR__ . '/bootstrap.php';
require __DIR__ . '/_auth_guard.php';

/* ---- JSON helper shim ---- */
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

if (!$db || $db->connect_errno) {
  error_log('[driver_vehicle] DB handle missing/connect error');
  json_out(['ok'=>false,'error'=>'Database connection not available','code'=>$db? $db->connect_errno : null], 500);
}
@$db->set_charset('utf8mb4');
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

/* ---- Helper guards (only define if bootstrap didn’t) ---- */
if (!function_exists('table_exists')) {
  function table_exists(mysqli $db, string $t): bool {
    $t = $db->real_escape_string($t);
    $res = $db->query("SHOW TABLES LIKE '{$t}'");
    return $res && $res->num_rows > 0;
  }
}
if (!function_exists('has_col')) {
  function has_col(mysqli $db, string $t, string $c): bool {
    $t = $db->real_escape_string($t);
    $c = $db->real_escape_string($c);
    $res = $db->query("SHOW COLUMNS FROM `{$t}` LIKE '{$c}'");
    return $res && $res->num_rows > 0;
  }
}

/* ---- Role helper ---- */
if (!function_exists('current_role')) {
  function current_role(): ?string {
    return $_SESSION['role']
        ?? ($_SESSION['user']['role'] ?? null)
        ?? ($_SESSION['user_role'] ?? null);
  }
}

/* ---- Preconditions ---- */
$method     = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$driver_id  = isset($_SESSION['driver_id']) ? (int)$_SESSION['driver_id'] : 0;
$role       = strtolower((string)current_role());
$logged_in  = $driver_id > 0 || !empty($_SESSION['user_id']) || !empty($_SESSION['id']);

error_log("[driver_vehicle] hit {$method}; session driver_id={$driver_id}; role={$role}");

if (!$logged_in) {
  json_out(['ok'=>false,'error'=>'unauthorized'], 401);
}

/* ============================== GET ============================== */
if ($method === 'GET') {
  try {
    // If assignments table is missing, return graceful nulls so UI doesn't break
    if (!table_exists($db,'assignments')) {
      json_out(['ok'=>true,'vehicle_id'=>null,'vehicle_no'=>null]);
    }

    // Admin/Supervisor can call GET; return nulls (no "personal" assignment)
    if ($driver_id <= 0 && in_array($role, ['admin','supervisor'], true)) {
      json_out(['ok'=>true,'vehicle_id'=>null,'vehicle_no'=>null]);
    }

    $plant_id = isset($_GET['plant_id']) ? (int)$_GET['plant_id'] : 0;

    if ($plant_id > 0) {
      $stmt = $db->prepare("SELECT vehicle_id FROM assignments WHERE driver_id=? AND plant_id=? ORDER BY id DESC LIMIT 1");
      $stmt->bind_param('ii',$driver_id,$plant_id);
    } else {
      $stmt = $db->prepare("SELECT vehicle_id FROM assignments WHERE driver_id=? ORDER BY id DESC LIMIT 1");
      $stmt->bind_param('i',$driver_id);
    }
    $stmt->execute();
    $stmt->bind_result($vid);
    $vehicle_id = null; if ($stmt->fetch()) $vehicle_id = $vid ? (int)$vid : null;
    $stmt->close();

    $vehicle_no = null;
    if ($vehicle_id && table_exists($db,'vehicles') && has_col($db,'vehicles','vehicle_no')) {
      $q = $db->prepare("SELECT vehicle_no FROM vehicles WHERE id=?");
      $q->bind_param('i', $vehicle_id);
      $q->execute(); $q->bind_result($vno);
      if ($q->fetch()) $vehicle_no = $vno;
      $q->close();
    }

    json_out(['ok'=>true,'vehicle_id'=>$vehicle_id,'vehicle_no'=>$vehicle_no]);

  } catch (mysqli_sql_exception $e) {
    error_log("[driver_vehicle][GET] SQL {$e->getCode()}: {$e->getMessage()}");
    json_out(['ok'=>false,'error'=>'Database error','code'=>(int)$e->getCode()], 500);
  } catch (Throwable $e) {
    error_log("[driver_vehicle][GET] Fatal: {$e->getMessage()} @ {$e->getFile()}:{$e->getLine()}");
    json_out(['ok'=>false,'error'=>'Unexpected server error'], 500);
  }
}

/* ============================== POST ============================== */
if ($method === 'POST') {
  try {
    if ($driver_id <= 0) {
      json_out(['ok'=>false,'error'=>'Only drivers can change vehicle assignment'], 403);
    }

    // If assignments table is missing, treat like "no-op" success so UI isn't blocked
    if (!table_exists($db,'assignments')) {
      json_out(['ok'=>true]);
    }

    $ct  = $_SERVER['CONTENT_TYPE'] ?? '';
    $raw = file_get_contents('php://input') ?: '';
    $j   = (stripos($ct, 'application/json') !== false) ? json_decode($raw,true) : $_POST;
    if (!is_array($j)) $j = [];
    error_log('[driver_vehicle][POST] payload: ' . json_encode($j, JSON_UNESCAPED_UNICODE));

    $vehicle_id = (isset($j['vehicle_id']) && $j['vehicle_id'] !== '' && $j['vehicle_id'] !== null)
      ? (int)$j['vehicle_id'] : null;
    $plant_id   = (isset($j['plant_id'])   && $j['plant_id']   !== '' && $j['plant_id']   !== null)
      ? (int)$j['plant_id']   : 0;

    // Treat non-positive as "clear"
    if ($vehicle_id !== null && $vehicle_id <= 0) $vehicle_id = null;

    // If clearing: delete and return
    if ($vehicle_id === null) {
      if ($plant_id > 0) {
        $stmt = $db->prepare("DELETE FROM assignments WHERE driver_id=? AND plant_id=?");
        $stmt->bind_param('ii',$driver_id,$plant_id);
      } else {
        $stmt = $db->prepare("DELETE FROM assignments WHERE driver_id=?");
        $stmt->bind_param('i',$driver_id);
      }
      $stmt->execute(); $stmt->close();
      json_out(['ok'=>true]);
    }

    // Validate vehicle (and derive plant_id if not provided)
    $sql = $plant_id>0
      ? "SELECT id, plant_id FROM vehicles WHERE id=? AND plant_id=?"
      : "SELECT id, plant_id FROM vehicles WHERE id=?";
    $stmt = $db->prepare($sql);
    if ($plant_id>0) $stmt->bind_param('ii',$vehicle_id,$plant_id);
    else             $stmt->bind_param('i',$vehicle_id);
    $stmt->execute(); $stmt->bind_result($vid,$vpid);
    $found=false; $vehPlantId=null;
    if ($stmt->fetch()) { $found=true; $vehPlantId=(int)$vpid; }
    $stmt->close();

    if (!$found) json_out(['ok'=>false,'error'=>'Invalid vehicle for plant'], 422);
    if ($plant_id <= 0) $plant_id = $vehPlantId ?? 0;
    if ($plant_id <= 0) json_out(['ok'=>false,'error'=>'plant_id required'], 422);

    // Optional: ensure the same vehicle isn't assigned to another driver

    // Upsert by (driver_id, plant_id). Ensure you have:
    //   UNIQUE KEY uq_driver_plant (driver_id, plant_id)
    // Optionally, also UNIQUE KEY uq_vehicle (vehicle_id) at schema-level to hard-enforce exclusivity.
    $ins = $db->prepare("
      INSERT INTO assignments (driver_id, plant_id, vehicle_id, assigned_date)
      VALUES (?, ?, ?, CURDATE())
      ON DUPLICATE KEY UPDATE vehicle_id=VALUES(vehicle_id), assigned_date=VALUES(assigned_date)
    ");
    $ins->bind_param('iii',$driver_id,$plant_id,$vehicle_id);
    $ins->execute(); $ins->close();

    json_out(['ok'=>true]);

  } catch (mysqli_sql_exception $e) {
    error_log("[driver_vehicle][POST] SQL {$e->getCode()}: {$e->getMessage()}");
    if ((int)$e->getCode() === 1062) {
      json_out(['ok'=>false,'error'=>'Duplicate assignment (driver/plant or vehicle already taken)'], 409);
    }
    json_out(['ok'=>false,'error'=>'Database error','code'=>(int)$e->getCode()], 500);
  } catch (Throwable $e) {
    error_log("[driver_vehicle][POST] Fatal: {$e->getMessage()} @ {$e->getFile()}:{$e->getLine()}");
    json_out(['ok'=>false,'error'=>'Unexpected server error'], 500);
  }
}

/* ---- Fallback ---- */
json_out(['ok'=>false,'error'=>'Method not allowed'], 405);