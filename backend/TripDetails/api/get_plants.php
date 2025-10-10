<?php
@ini_set('display_errors','0');
@ini_set('log_errors','1');
$DBG = rtrim(sys_get_temp_dir(), DIRECTORY_SEPARATOR).DIRECTORY_SEPARATOR.'td_get_plants.log';
@ini_set('error_log', $DBG);
function _p_log($m){ global $DBG; @error_log('[get_plants] '.$m); @file_put_contents($DBG,'['.date('c').'] '.$m."\n", FILE_APPEND); }
register_shutdown_function(function(){ $e=error_get_last(); if($e && in_array($e['type'],[E_ERROR,E_PARSE,E_CORE_ERROR,E_COMPILE_ERROR])){ _p_log('FATAL: '.$e['message'].' @ '.$e['file'].':'.$e['line']); if(!headers_sent()) header('Content-Type: application/json; charset=utf-8'); http_response_code(500); echo json_encode(['ok'=>false,'error'=>'Fatal: '.$e['message']]); }});

require __DIR__ . '/bootstrap.php';
require __DIR__ . '/_auth_guard.php';

header('Content-Type: application/json; charset=utf-8');

try {
  /** @var mysqli $mysqli */
  $db = $mysqli ?? ($conn ?? null) ?? ($con ?? null);
  if (!$db || ($db instanceof mysqli && $db->connect_errno)) {
    _p_log('DB unavailable');
    http_response_code(500);
    echo json_encode(['ok'=>false,'error'=>'DB unavailable']); exit;
  }
  @$db->set_charset('utf8mb4');

  if (!function_exists('table_exists') || !table_exists($db, 'plants')) {
    _p_log('plants table missing');
    echo json_encode(['ok'=>true,'plants'=>[]]); exit;
  }

  // Column detection
  $nameCol = 'plant_name';
  if (function_exists('has_col')) {
    if (!has_col($db,'plants',$nameCol)) {
      foreach (['name','title'] as $alt) { if (has_col($db,'plants',$alt)) { $nameCol=$alt; break; } }
    }
  }

  // ---- Role-based filtering ----
  $role = strtolower($_SESSION['role'] ?? '');
  $driverPlantId = (int)($_SESSION['plant_id'] ?? 0);
  $supervisedPlantIds = $_SESSION['supervised_plant_ids'] ?? [];

  $where = '';
  if ($role === 'driver' && $driverPlantId > 0) {
    $where = "WHERE id = " . (int)$driverPlantId;
  } elseif ($role === 'supervisor' && is_array($supervisedPlantIds) && !empty($supervisedPlantIds)) {
    $in = implode(',', array_map('intval',$supervisedPlantIds));
    $where = "WHERE id IN ($in)";
  } // admin/others → no filter (all plants)

  $sql = "SELECT id, `$nameCol` AS plant_name FROM plants $where ORDER BY `$nameCol`";
  $res = $db->query($sql);
  if (!$res) {
    _p_log('query error: '.$db->error);
    http_response_code(500);
    echo json_encode(['ok'=>false,'error'=>'Query failed']); exit;
  }
  $plants = [];
  while ($row = $res->fetch_assoc()) {
    $plants[] = ['id'=>(int)$row['id'], 'plant_name'=> (string)$row['plant_name']];
  }

  echo json_encode(['ok'=>true,'plants'=>$plants], JSON_UNESCAPED_UNICODE);

} catch (Throwable $e) {
  _p_log('EXC: '.$e->getMessage());
  http_response_code(500);
  echo json_encode(['ok'=>false,'error'=>'Server exception: '.$e->getMessage()]);
}
