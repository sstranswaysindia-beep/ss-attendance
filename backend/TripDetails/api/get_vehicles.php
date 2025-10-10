<?php
@ini_set('display_errors','0');
@ini_set('log_errors','1');
$__LOG = rtrim(sys_get_temp_dir(), DIRECTORY_SEPARATOR).DIRECTORY_SEPARATOR.'td_get_vehicles.log';
@ini_set('error_log', $__LOG);

function _gv_log(string $m): void {
  global $__LOG;
  @error_log('[get_vehicles] '.$m);
  @file_put_contents($__LOG, '['.date('c').'] '.$m."\n", FILE_APPEND);
}
function _json($payload, int $status=200): void {
  if (function_exists('ob_get_level')) { while (ob_get_level() > 0) @ob_end_clean(); }
  http_response_code($status);
  header('Content-Type: application/json; charset=utf-8');
  echo json_encode($payload, JSON_UNESCAPED_UNICODE);
  exit;
}
register_shutdown_function(function(){
  $e = error_get_last();
  if ($e && in_array($e['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR])) {
    _gv_log('FATAL: '.$e['message'].' @ '.$e['file'].':'.$e['line']);
    if (!headers_sent()) header('Content-Type: application/json; charset=utf-8');
    http_response_code(500);
    echo json_encode(['ok'=>false,'error'=>'Fatal: '.$e['message']]);
  }
});

require __DIR__ . '/bootstrap.php';
require __DIR__ . '/_auth_guard.php';  // ensure user is logged in

header('Content-Type: application/json; charset=utf-8');

try {
  /** @var mysqli|null $mysqli */
  $db = $mysqli ?? ($conn ?? null) ?? ($con ?? null);
  if (!$db || ($db instanceof mysqli && $db->connect_errno)) {
    _gv_log('DB unavailable');
    _json(['ok'=>false,'error'=>'DB unavailable'], 500);
  }
  @$db->set_charset('utf8mb4');

  // ---- Input & Role-based check ----
  $reqPlantId = isset($_GET['plant_id']) && is_numeric($_GET['plant_id']) ? (int)$_GET['plant_id'] : 0;
  $role = strtolower($_SESSION['role'] ?? '');
  $driverPlantId = (int)($_SESSION['plant_id'] ?? 0);
  $supervisedPlantIds = $_SESSION['supervised_plant_ids'] ?? [];

  if ($role === 'driver') {
    if ($driverPlantId <= 0) {
      _json(['ok'=>false,'error'=>'Driver has no plant assigned'], 403);
    }
    if ($reqPlantId !== $driverPlantId) {
      _json(['ok'=>false,'error'=>'Access denied for this plant'], 403);
    }
  } elseif ($role === 'supervisor') {
    if (!is_array($supervisedPlantIds) || empty($supervisedPlantIds)) {
      _json(['ok'=>false,'error'=>'Supervisor has no plants assigned'], 403);
    }
    if (!in_array($reqPlantId, $supervisedPlantIds, true)) {
      _json(['ok'=>false,'error'=>'Access denied for this plant'], 403);
    }
  } else {
    // admin or other roles → allow any plant
  }

  if ($reqPlantId <= 0) {
    _gv_log('bad plant_id = '.$reqPlantId);
    _json(['ok'=>false,'error'=>'plant_id required'], 400);
  }

  // ---- Detect schema safely ----
  $vehNoCol = 'vehicle_no';
  if (function_exists('has_col') && !has_col($db,'vehicles',$vehNoCol)) {
    foreach (['number','reg_no','registration_no'] as $alt) {
      if (has_col($db,'vehicles',$alt)) { $vehNoCol=$alt; break; }
    }
  }

  $plantCol = 'plant_id';
  if (function_exists('has_col') && !has_col($db,'vehicles',$plantCol)) {
    $plantCol = null; // cannot filter
  }

  $vehicles = [];

  if ($plantCol) {
    $sql = "SELECT id, `$vehNoCol` AS vno FROM vehicles WHERE `$plantCol`=? ORDER BY `$vehNoCol`";
    $st  = $db->prepare($sql);
    if (!$st) { _gv_log('prepare1 failed: '.$db->error); _json(['ok'=>false,'error'=>'DB prepare failed'],500); }
    $st->bind_param('i', $reqPlantId);
  } else {
    $sql = "SELECT id, `$vehNoCol` AS vno FROM vehicles ORDER BY `$vehNoCol`";
    $st  = $db->prepare($sql);
    if (!$st) { _gv_log('prepare2 failed: '.$db->error); _json(['ok'=>false,'error'=>'DB prepare failed'],500); }
  }

  if (!$st->execute()) {
    $err = $st->error; $st->close();
    _gv_log('execute failed: '.$err);
    _json(['ok'=>false,'error'=>'DB execute failed'],500);
  }
  $res = $st->get_result();
  while ($row = $res->fetch_assoc()) {
    $no = trim((string)($row['vno'] ?? ''));
    if ($no !== '') $vehicles[] = ['id'=>(int)$row['id'], 'vehicle_no'=>$no];
  }
  $st->close();

  _json(['ok'=>true,'vehicles'=>$vehicles]);

} catch (Throwable $e) {
  _gv_log('EXC: '.$e->getMessage().' @ '.$e->getFile().':'.$e->getLine());
  _json(['ok'=>false,'error'=>'Server exception: '.$e->getMessage()], 500);
}