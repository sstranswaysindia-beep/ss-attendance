<?php
declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';
require_once __DIR__ . '/_auth_guard.php';

/** pick mysqli */
$db = (isset($mysqli) && $mysqli instanceof mysqli) ? $mysqli
    : ((isset($conn) && $conn instanceof mysqli) ? $conn
    : ((isset($con)  && $con  instanceof mysqli) ? $con : null));

if (!$db || $db->connect_errno) {
  json(['ok'=>false,'error'=>'DB unavailable'], 500);
}
@$db->set_charset('utf8mb4');

/** Helpers to probe columns */
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

/* ---------- DRIVERS (for picker & name chips) ---------- */
/* ---------- DRIVERS + SUPERVISORS (for picker & name chips) ---------- */
$drivers = [];
if (table_exists($db,'drivers') && has_col($db,'drivers','id')) {
  $nameCol = null;
  foreach (['name','driver_name','full_name'] as $c) {
    if (has_col($db,'drivers',$c)) { $nameCol = $c; break; }
  }
  if ($nameCol) {
    $where = [];
    if (has_col($db,'drivers','active'))    $where[] = "d.active=1";
    if (has_col($db,'drivers','is_active')) $where[] = "d.is_active=1";
    if (has_col($db,'drivers','status'))    $where[] = "(LOWER(d.status)='active' OR d.status='1')";
    // instead of filtering only role='driver', allow both driver and supervisor
    if (has_col($db,'drivers','role'))      $where[] = "(LOWER(d.role)='driver' OR LOWER(d.role)='supervisor')";

    $sql = "
      SELECT
        d.id,
        d.`$nameCol` AS name,
        d.plant_id,
        d.role,
        COALESCE(sd.name, su.full_name, su.username) AS supervisor_name
      FROM drivers d
      LEFT JOIN plants   p  ON p.id = d.plant_id
      LEFT JOIN drivers  sd ON sd.id = p.supervisor_driver_id
      LEFT JOIN users    su ON su.id = p.supervisor_user_id
    ";
    if (!empty($where)) {
      $sql .= " WHERE " . implode(' AND ', $where);
    }
    $sql .= " ORDER BY d.`$nameCol`";

    if ($rs = $db->query($sql)) {
      while ($row = $rs->fetch_assoc()) {
        $drivers[] = [
          'id'              => (int)$row['id'],
          'name'            => (string)$row['name'],
          'plant_id'        => array_key_exists('plant_id',$row) ? (int)$row['plant_id'] : null,
          'role'            => $row['role'] ?? null,
          'supervisor_name' => !empty($row['supervisor_name']) ? (string)$row['supervisor_name'] : null,
        ];
      }
      $rs->close();
    }
  }
}
/* ---------- HELPERS (active only, include plant_id if present) ---------- */
$helpers = [];
$helpersTable = table_exists($db,'helpers');
if ($helpersTable && has_col($db,'helpers','id')) {
  $nameCol = null;
  foreach (['name','helper_name','full_name'] as $c) {
    if (has_col($db,'helpers',$c)) { $nameCol = $c; break; }
  }
  if ($nameCol) {
    $cols = ["id", "`$nameCol` AS name"];
    if (has_col($db,'helpers','plant_id')) $cols[] = "plant_id";
    $where = [];

    // ACTIVE ONLY
    if (has_col($db,'helpers','active'))    $where[] = "active=1";
    if (has_col($db,'helpers','is_active')) $where[] = "is_active=1";
    if (has_col($db,'helpers','status'))    $where[] = "(status='active' OR status='1')";

    $sql = "SELECT ".implode(',', $cols)." FROM helpers";
    if (!empty($where)) $sql .= " WHERE ".implode(' AND ', $where);
    $sql .= " ORDER BY `$nameCol`";

    if ($rs = $db->query($sql)) {
      while ($row = $rs->fetch_assoc()) {
        $helpers[] = [
          'id'       => (int)$row['id'],
          'name'     => (string)$row['name'],
          'plant_id' => array_key_exists('plant_id',$row) ? (int)$row['plant_id'] : null,
        ];
      }
      $rs->close();
    }
  }
}

/* ---------- CUSTOMER suggestions ---------- */
$customers = [];
if (table_exists($db,'customers') && has_col($db,'customers','id')) {
  // primary list from a customers master table
  $custNameCol = null;
  foreach (['name','customer_name','title'] as $c) {
    if (has_col($db,'customers',$c)) { $custNameCol = $c; break; }
  }
  if ($custNameCol) {
    $sql = "SELECT DISTINCT `$custNameCol` AS name FROM customers
            WHERE `$custNameCol` IS NOT NULL AND TRIM(`$custNameCol`)!=''
            ORDER BY `$custNameCol` LIMIT 1000";
    if ($rs = $db->query($sql)) {
      while ($row = $rs->fetch_assoc()) {
        $nm = trim((string)$row['name']); if ($nm!=='') $customers[] = ['name'=>$nm];
      }
      $rs->close();
    }
  }
}
if (empty($customers) && table_exists($db,'trip_customers') && has_col($db,'trip_customers','trip_id')) {
  // fallback: distinct from prior trips
  $custNameCol = null;
  foreach (['customer_name','name','title'] as $c) {
    if (has_col($db,'trip_customers',$c)) { $custNameCol = $c; break; }
  }
  if ($custNameCol) {
    $sql = "SELECT DISTINCT `$custNameCol` AS name FROM trip_customers
            WHERE `$custNameCol` IS NOT NULL AND TRIM(`$custNameCol`)!=''
            ORDER BY `$custNameCol` LIMIT 1000";
    if ($rs = $db->query($sql)) {
      while ($row = $rs->fetch_assoc()) {
        $nm = trim((string)$row['name']); if ($nm!=='') $customers[] = ['name'=>$nm];
      }
      $rs->close();
    }
  }
}

json([
  'ok'        => true,
  'drivers'   => $drivers,
  'helpers'   => $helpers,   // include plant_id if available, ACTIVE only
  'customers' => $customers,
]);