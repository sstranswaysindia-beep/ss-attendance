<?php
// /TripDetails/api/get_helpers.php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';
require __DIR__ . '/_auth_guard.php';

/** @var mysqli $mysqli */
$db = (isset($conn) && $conn instanceof mysqli) ? $conn
     : ((isset($mysqli) && $mysqli instanceof mysqli) ? $mysqli : null);
if (!$db) json(['ok'=>false,'error'=>'No DB connection'], 500);
@$db->set_charset('utf8mb4');

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

/* --- inputs --- */
$plant_id = isset($_GET['plant_id']) && ctype_digit((string)$_GET['plant_id'])
  ? (int)$_GET['plant_id'] : 0;

/* --- hard requirement: plant_id --- */
if ($plant_id <= 0) {
  json(['ok'=>true,'helpers'=>[]]); // silently empty; frontend already passes plant_id
}

/* --- schema guard --- */
if (!table_exists($db,'drivers')) {
  json(['ok'=>true,'helpers'=>[]]);
}

/* --- build query: only helpers in this plant and Active --- */
$cols = ['id'];
$nameExpr =
  has_col($db,'drivers','name') ? 'name' :
  (has_col($db,'drivers','first_name') && has_col($db,'drivers','last_name')
    ? "TRIM(CONCAT(COALESCE(first_name,''),' ',COALESCE(last_name,'')))"
    : (has_col($db,'drivers','first_name') ? 'first_name' : "CONCAT('Helper #',id)")
  );

$cols[] = "$nameExpr AS name";

$sql = "SELECT ".implode(',', $cols)." FROM drivers
        WHERE 1
          AND ".(has_col($db,'drivers','role')   ? "LOWER(role)='helper'" : "1")."
          AND ".(has_col($db,'drivers','status') ? "status='Active'"      : "1")."
          AND ".(has_col($db,'drivers','plant_id') ? "plant_id=?" : "0"); // require plant filter

$helpers = [];
if ($st = $db->prepare($sql)) {
  $st->bind_param('i', $plant_id);
  $st->execute();
  $res = $st->get_result();
  while ($r = $res->fetch_assoc()) {
    $nm = trim((string)($r['name'] ?? '')); if ($nm==='') continue;
    $helpers[] = ['id'=>(int)$r['id'], 'name'=>$nm, 'plant_id'=>$plant_id];
  }
  $st->close();
}

json(['ok'=>true,'helpers'=>$helpers]);