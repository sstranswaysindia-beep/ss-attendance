<?php
// /TripDetails/api/me.php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

/* ---------- Always JSON + no-cache ---------- */
@header('Content-Type: application/json; charset=utf-8');
@header('Cache-Control: no-store, no-cache, must-revalidate, private');
@header('Pragma: no-cache');
@header('Expires: 0');
@header('Vary: Cookie'); // help proxies split by session cookie

$SID  = session_id();
$SNAME= session_name();
@error_log("[me] sess={$SNAME} sid={$SID}");

function json_with_session(array $payload, int $status = 200): void {
  global $SID, $SNAME;
  $payload['_session'] = ['sid' => $SID, 'sess' => $SNAME];
  if (function_exists('ob_get_level')) { while (ob_get_level() > 0) @ob_end_clean(); }
  if (!headers_sent()) {
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, private');
  }
  echo json_encode($payload, JSON_UNESCAPED_UNICODE);
  exit;
}

/* ---------- Auth guard ---------- */
$uid = isset($_SESSION['user_id']) ? (int)$_SESSION['user_id'] : 0;
if ($uid <= 0) {
  json_with_session(['ok' => false, 'error' => 'Unauthorized'], 401);
}

/* ---------- Resolve mysqli ---------- */
$db = null;
/** @var mysqli|null $mysqli */
/** @var mysqli|null $conn */
/** @var mysqli|null $con */
if (isset($mysqli) && $mysqli instanceof mysqli) $db = $mysqli;
elseif (isset($conn) && $conn instanceof mysqli) $db = $conn;
elseif (isset($con)  && $con  instanceof mysqli) $db = $con;

if (!$db || $db->connect_errno) {
  json_with_session(['ok'=>false,'error'=>'DB unavailable'], 500);
}

@$db->set_charset('utf8mb4');
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

try {
  /* ---------- Query: users + drivers ---------- */
  $sql = "
    SELECT
      u.id        AS uid,
      u.username  AS username,
      u.role      AS role,
      u.driver_id AS driver_id,
      d.name      AS driver_name,
      d.plant_id  AS plant_id
    FROM users u
    LEFT JOIN drivers d ON d.id = u.driver_id
    WHERE u.id = ?
    LIMIT 1
  ";
  $st = $db->prepare($sql);
  $st->bind_param('i', $uid);
  $st->execute();
  $res = $st->get_result();
  $row = $res ? $res->fetch_assoc() : null;
  $st->close();

  if (!$row) {
    json_with_session(['ok'=>false,'error'=>'User not found'], 404);
  }

  $role        = (string)($row['role'] ?? '');
  $driver_id   = isset($row['driver_id']) ? (int)$row['driver_id'] : 0;
  $driver_id   = $driver_id > 0 ? $driver_id : null;
  $driver_name = isset($row['driver_name']) && $row['driver_name'] !== '' ? (string)$row['driver_name'] : null;
  $plant_id    = isset($row['plant_id']) ? (int)$row['plant_id'] : null;

  /* ---------- Resolve supervised plants if supervisor ---------- */
  $supervisedPlants = [];
  $supervisedPlantIds = [];
  if (strcasecmp($role, 'supervisor') === 0) {
    $sqlSup = "
      SELECT DISTINCT p.id, p.plant_name
      FROM plants p
      LEFT JOIN supervisor_plants sp ON sp.plant_id = p.id
      WHERE p.supervisor_user_id = ? OR sp.user_id = ?
      ORDER BY p.plant_name
    ";
    if ($st2 = $db->prepare($sqlSup)) {
      $st2->bind_param('ii', $uid, $uid);
      $st2->execute();
      $r2 = $st2->get_result();
      while ($r = $r2->fetch_assoc()) {
        $pid = (int)$r['id'];
        $supervisedPlants[] = ['id'=>$pid, 'plant_name'=>(string)$r['plant_name']];
        $supervisedPlantIds[] = $pid;
      }
      $st2->close();
    }
  }

  /* ---------- Build payload ---------- */
  $user = [
    'id'                 => (int)$row['uid'],
    'username'           => (string)$row['username'],
    'role'               => $role,
    'driver_id'          => $driver_id,
    'driver_name'        => $driver_name,
    'plant_id'           => $plant_id,
    'plant_locked'       => !empty($plant_id),
    'supervised_plants'  => $supervisedPlants,
    'supervised_plant_ids' => $supervisedPlantIds,
  ];

  $isAdmin      = strcasecmp($role, 'admin') === 0;
  $isSupervisor = strcasecmp($role, 'supervisor') === 0;
  $isDriver     = strcasecmp($role, 'driver') === 0;

  $caps = [
    'can_assign_vehicle' => $isDriver || $isSupervisor,
    'can_end_trip'       => $isDriver || $isSupervisor || $isAdmin,
    'can_delete_trip'    => $isSupervisor || $isAdmin,
    'can_manage_meta'    => $isSupervisor || $isAdmin,
  ];

  /* ---------- Mirror into session ---------- */
  $_SESSION['driver_id']            = $driver_id ? (int)$driver_id : 0;
  $_SESSION['role']                 = $role ?: ($_SESSION['role'] ?? '');
  $_SESSION['plant_id']             = $plant_id; // may be null
  $_SESSION['supervised_plant_ids'] = $supervisedPlantIds;

  /* ---------- OK ---------- */
  $payload = [
    'ok'           => true,
    'is_logged_in' => true,
    'user'         => $user,
    'caps'         => $caps,
    'sid'          => $SID,
    'sess'         => $SNAME,
  ];
  json_with_session($payload, 200);

} catch (mysqli_sql_exception $e) {
  json_with_session([
    'ok'=>false,
    'error'=>'Database error',
    'code'=>$e->getCode(),
    'detail'=>$e->getMessage()
  ], 500);
} catch (Throwable $e) {
  json_with_session([
    'ok'=>false,
    'error'=>'Unexpected server error',
    'detail'=>$e->getMessage()
  ], 500);
}