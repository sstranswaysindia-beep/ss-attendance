<?php
declare(strict_types=1);

/**
 * /TripDetails/api/meta.php
 * Emits: {
 *   ok: true,
 *   drivers:  [{id:int, name:string, plant_id:int|null, role:?string, supervisor_name:?string}],
 *   helpers:  [{id:int, name:string, plant_id:int|null}],
 *   customers:[{name:string}]              // optional ([] if not found)
 * }
 */

/* ---------- Make output JSON-only (no stray bytes) ---------- */
if (function_exists('ob_get_level')) {
  while (ob_get_level() > 0) { @ob_end_clean(); }
}
ob_start();
ini_set('display_errors', '0');                         // never display notices/warnings to client
error_reporting(E_ALL & ~E_NOTICE & ~E_WARNING);
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, private');

$__respond = function (array $payload, int $status = 200): void {
  http_response_code($status);
  if (function_exists('ob_get_length') && ob_get_length() !== false) { @ob_clean(); }
  echo json_encode($payload, JSON_UNESCAPED_UNICODE);
  exit;
};

/* ---------- Bootstrap / DB handle ---------- */
require __DIR__ . '/bootstrap.php'; // keep your existing bootstrap

/** @var mysqli|null $db */
$db = null;
try {
  global $conn, $mysqli, $con;
  $db = ($conn instanceof mysqli) ? $conn
      : (($mysqli instanceof mysqli) ? $mysqli
      : (($con instanceof mysqli) ? $con : null));
} catch (Throwable $e) {
  // ignore; will be handled below
}

if (!$db || @$db->connect_errno) {
  $__respond(['ok' => false, 'error' => 'DB unavailable'], 500);
}

@$db->set_charset('utf8mb4');

/* ---------- Helpers: schema introspection ---------- */
$hasTable = function (string $table) use ($db): bool {
  $t = $db->real_escape_string($table);
  $res = $db->query("SHOW TABLES LIKE '{$t}'");
  return ($res && $res->num_rows > 0);
};
$hasCol = function (string $table, string $col) use ($db): bool {
  $t = $db->real_escape_string($table);
  $c = $db->real_escape_string($col);
  $sql = "SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
          WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '{$t}' AND COLUMN_NAME = '{$c}' LIMIT 1";
  $res = $db->query($sql);
  return ($res && $res->num_rows > 0);
};

/* ---------- DRIVERS ---------- */
$drivers = [];
if ($hasTable('drivers') && $hasCol('drivers', 'id')) {
  $nameCol = null;
  foreach (['name','driver_name','full_name','first_name'] as $cand) {
    if ($hasCol('drivers', $cand)) { $nameCol = $cand; break; }
  }

  if ($nameCol) {
    $conds = [];

    if ($hasCol('drivers','active'))    $conds[] = 'd.active = 1';
    if ($hasCol('drivers','is_active')) $conds[] = 'd.is_active = 1';
    if ($hasCol('drivers','status'))    $conds[] = "(LOWER(d.status)='active' OR d.status='1')";
    if ($hasCol('drivers','role'))      $conds[] = "(LOWER(d.role)='driver' OR LOWER(d.role)='supervisor')";

    $sql = "
      SELECT
        d.id,
        d.`{$nameCol}` AS name,
        " . ($hasCol('drivers','plant_id') ? 'd.plant_id,' : 'NULL AS plant_id,') . "
        " . ($hasCol('drivers','role')     ? 'd.role,'     : 'NULL AS role,') . "
        COALESCE(sd.name, su.full_name, su.username) AS supervisor_name
      FROM drivers d
      LEFT JOIN plants p ON p.id = " . ($hasCol('drivers','plant_id') ? 'd.plant_id' : 'NULL') . "
      LEFT JOIN drivers sd ON sd.id = p.supervisor_driver_id
      LEFT JOIN users   su ON su.id = p.supervisor_user_id
    ";

    if (!empty($conds)) { $sql .= ' WHERE ' . implode(' AND ', $conds); }
    $sql .= " ORDER BY d.`{$nameCol}`";

    if ($rs = $db->query($sql)) {
      while ($row = $rs->fetch_assoc()) {
        $nm = trim((string)($row['name'] ?? ''));
        if ($nm === '') continue;
        $drivers[] = [
          'id'              => (int)$row['id'],
          'name'            => $nm,
          'plant_id'        => array_key_exists('plant_id', $row) ? (int)$row['plant_id'] : null,
          'role'            => $row['role'] ?? null,
          'supervisor_name' => !empty($row['supervisor_name']) ? (string)$row['supervisor_name'] : null,
        ];
      }
      $rs->close();
    }
  }
}

/* ---------- HELPERS ---------- */
$helpers = [];
if ($hasTable('helpers') && $hasCol('helpers','id')) {
  $nameCol = null;
  foreach (['name','helper_name','full_name','first_name'] as $cand) {
    if ($hasCol('helpers', $cand)) { $nameCol = $cand; break; }
  }
  if ($nameCol) {
    $cols = ["id", "`{$nameCol}` AS name"];
    $conds = [];
    $hasPlant = $hasCol('helpers','plant_id');
    if ($hasPlant) $cols[] = 'plant_id';

    if ($hasCol('helpers','active'))    $conds[] = 'active=1';
    if ($hasCol('helpers','is_active')) $conds[] = 'is_active=1';
    if ($hasCol('helpers','status'))    $conds[] = "(LOWER(status)='active' OR status='1')";

    $sql = 'SELECT ' . implode(',', $cols) . ' FROM helpers';
    if (!empty($conds)) $sql .= ' WHERE ' . implode(' AND ', $conds);
    $sql .= " ORDER BY `{$nameCol}`";

    if ($rs = $db->query($sql)) {
      while ($row = $rs->fetch_assoc()) {
        $nm = trim((string)($row['name'] ?? ''));
        if ($nm === '') continue;
        $helpers[] = [
          'id'       => (int)$row['id'],
          'name'     => $nm,
          'plant_id' => ($hasPlant && array_key_exists('plant_id',$row)) ? (int)$row['plant_id'] : null,
        ];
      }
      $rs->close();
    }
  }
}

/* Fallback: helpers from drivers with role=helper */
if (empty($helpers) && $hasTable('drivers') && $hasCol('drivers','id')) {
  $nameExpr = $hasCol('drivers','name') ? 'name'
            : ($hasCol('drivers','first_name') && $hasCol('drivers','last_name')
                ? "TRIM(CONCAT(COALESCE(first_name,''),' ',COALESCE(last_name,'')))"
                : ($hasCol('drivers','first_name') ? 'first_name' : 'CONCAT(\"Helper #\", id)'));

  $conds = [];
  if ($hasCol('drivers','role'))   $conds[] = "LOWER(role)='helper'";
  if ($hasCol('drivers','status')) $conds[] = "(LOWER(status)='active' OR status='1')";
  if ($hasCol('drivers','active')) $conds[] = 'active=1';

  $sql = "SELECT id, " . ($hasCol('drivers','plant_id') ? "plant_id," : "NULL AS plant_id,") . " {$nameExpr} AS name FROM drivers";
  if (!empty($conds)) $sql .= ' WHERE ' . implode(' AND ', $conds);
  $sql .= ' ORDER BY name';

  if ($rs = $db->query($sql)) {
    while ($row = $rs->fetch_assoc()) {
      $nm = trim((string)($row['name'] ?? ''));
      if ($nm === '') continue;
      $helpers[] = [
        'id'       => (int)$row['id'],
        'name'     => $nm,
        'plant_id' => array_key_exists('plant_id',$row) ? (int)$row['plant_id'] : null,
      ];
    }
    $rs->close();
  }
}

/* ---------- CUSTOMERS (optional, used by UI datalist) ---------- */
$customers = [];
if ($hasTable('customers') && $hasCol('customers','name')) {
  if ($rs = $db->query("SELECT name FROM customers WHERE name <> '' ORDER BY name")) {
    while ($r = $rs->fetch_assoc()) {
      $nm = trim((string)($r['name'] ?? ''));
      if ($nm !== '') $customers[] = ['name' => $nm];
    }
    $rs->close();
  }
} elseif ($hasTable('trip_customers') && $hasCol('trip_customers','customer_name')) {
  if ($rs = $db->query("SELECT DISTINCT customer_name AS name FROM trip_customers WHERE customer_name <> '' ORDER BY name")) {
    while ($r = $rs->fetch_assoc()) {
      $nm = trim((string)($r['name'] ?? ''));
      if ($nm !== '') $customers[] = ['name' => $nm];
    }
    $rs->close();
  }
}

/* ---------- Emit JSON ---------- */
$__respond([
  'ok'        => true,
  'drivers'   => $drivers,
  'helpers'   => $helpers,
  'customers' => $customers,   // safe even if []
], 200);