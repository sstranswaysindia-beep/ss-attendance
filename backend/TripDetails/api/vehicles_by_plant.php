<?php
//declare(strict_types=1);
header('Content-Type: application/json');

require __DIR__ . '/_auth_guard.php';
require __DIR__ . '/bootstrap.php';

$db = (isset($conn) && $conn instanceof mysqli) ? $conn : $mysqli;

$plant_id = isset($_GET['plant_id']) && is_numeric($_GET['plant_id']) ? (int)$_GET['plant_id'] : 0;
if ($plant_id<=0) { echo json_encode(['ok'=>false,'error'=>'plant_id required']); exit; }

// detect vehicles table columns
if (!table_exists($db,'vehicles')) { echo json_encode(['ok'=>true,'vehicles'=>[]]); exit; }

$idCol = has_col($db,'vehicles','id') ? 'id' : (has_col($db,'vehicles','vehicle_id') ? 'vehicle_id' : null);
$numCol = null; foreach (['vehicle_no','vehicle_number','reg_no','registration_no','plate_no','number'] as $c){ if (has_col($db,'vehicles',$c)) { $numCol=$c; break; } }
$plantCol = null; foreach (['plant_id','plant','plantid'] as $c){ if (has_col($db,'vehicles',$c)) { $plantCol=$c; break; } }

$activeWhere = '';
foreach (['active','enabled','is_active','status'] as $flag){
  if (has_col($db,'vehicles',$flag)) {
    $activeWhere = ($flag==='status') ? " AND (`$flag` IS NULL OR `$flag` NOT IN ('inactive','disabled','0'))"
                                      : " AND IFNULL(`$flag`,1)=1";
    break;
  }
}

$vehicles = [];
if ($idCol && $numCol && $plantCol) {
  $sql = "SELECT `$idCol` AS id, `$numCol` AS vehicle_no FROM vehicles WHERE `$plantCol`=? $activeWhere ORDER BY `$numCol`";
  if ($st = $db->prepare($sql)) {
    $st->bind_param('i',$plant_id); $st->execute(); $res=$st->get_result();
    while ($row=$res->fetch_assoc()){ if(isset($row['id']) && isset($row['vehicle_no']) && $row['vehicle_no']!==null){ $vehicles[]=['id'=>(int)$row['id'],'vehicle_no'=>trim((string)$row['vehicle_no'])]; } }
    $st->close();
  }
}

// fallback via assignments
if (empty($vehicles) && table_exists($db,'assignments')) {
  $aVeh = has_col($db,'assignments','vehicle_id') ? 'vehicle_id' : null;
  $aPlt = has_col($db,'assignments','plant_id') ? 'plant_id' : null;
  if ($aVeh && $aPlt && $idCol && $numCol) {
    $sql = "SELECT DISTINCT v.`$idCol` AS id, v.`$numCol` AS vehicle_no
            FROM assignments a JOIN vehicles v ON v.`$idCol`=a.`$aVeh`
            WHERE a.`$aPlt`=? ORDER BY v.`$numCol`";
    if ($st = $db->prepare($sql)) {
      $st->bind_param('i',$plant_id); $st->execute(); $res=$st->get_result();
      while ($row=$res->fetch_assoc()){ if(isset($row['id']) && isset($row['vehicle_no']) && $row['vehicle_no']!==null){ $vehicles[]=['id'=>(int)$row['id'],'vehicle_no'=>trim((string)$row['vehicle_no'])]; } }
      $st->close();
    }
  }
}

echo json_encode(['ok'=>true,'vehicles'=>$vehicles]);