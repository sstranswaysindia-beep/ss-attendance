<?php
declare(strict_types=1);

// -----------------------------------------------------------------------------
// bootstrap.php — session, JSON helpers, DB wiring (reuses conf/config.php)
// -----------------------------------------------------------------------------
// Prevent PHP from leaking warnings into JSON
@ini_set('display_errors', '0');
@ini_set('log_errors', '1');
@ini_set('output_buffering', '0');
@ini_set('zlib.output_compression', '0');
@ini_set('implicit_flush', '1');
@ini_set('auto_prepend_file', '');
if (function_exists('apache_setenv')) { @apache_setenv('no-gzip', '1'); }

// ---------- SESSION ----------
if (session_status() === PHP_SESSION_NONE) {
  $isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
             || ((int)($_SERVER['SERVER_PORT'] ?? 80) === 443);

  // Scope cookie only to /TripDetails/, avoid conflict with other apps
  $cookiePath = '/TripDetails/';

  // Unique session name for this app
  session_name('TDSESSID');

  session_set_cookie_params([
    'lifetime' => 0,
    'path'     => $cookiePath,
    'domain'   => '',                   // current host only
    'secure'   => $isHttps,
    'httponly' => true,
    'samesite' => 'Lax',
  ]);

  session_start();
}

// ---------- JSON HELPERS ----------
if (!function_exists('json')) {
  function json($payload, int $status = 200): void {
    if (function_exists('ob_get_level')) {
      while (ob_get_level() > 0) { @ob_end_clean(); }
    }
    if (!headers_sent()) {
      http_response_code($status);
      header('Content-Type: application/json; charset=utf-8');
      header('Cache-Control: no-store, no-cache, must-revalidate, private');
    }
    echo json_encode($payload, JSON_UNESCAPED_UNICODE);
    exit;
  }
}

if (!function_exists('read_json_body')) {
  function read_json_body(): array {
    $raw = file_get_contents('php://input');
    if (!is_string($raw) || $raw === '') return [];
    $j = json_decode($raw, true);
    return is_array($j) ? $j : [];
  }
}

if (!function_exists('req_get')) {
  function req_get(string $k, $d=null){ return isset($_GET[$k]) ? trim((string)$_GET[$k]) : $d; }
}
if (!function_exists('req_post')) {
  function req_post(string $k, $d=null){ return isset($_POST[$k]) ? trim((string)$_POST[$k]) : $d; }
}
if (!function_exists('to_int_or_null')) {
  function to_int_or_null($v){ if ($v===null||$v==='') return null; return is_numeric($v)?(int)$v:null; }
}

// ---------- CONFIG ----------
$configFile = __DIR__ . '/../../../conf/config.php';
if (!is_file($configFile)) json(['ok'=>false,'error'=>'Config file missing','detail'=>$configFile], 500);
require_once $configFile;

// ---------- CONNECT / REUSE ----------
mysqli_report(MYSQLI_REPORT_OFF);

$mysqli = $mysqli ?? null; // reuse if config already made it
if (!$mysqli && isset($conn) && $conn instanceof mysqli) $mysqli = $conn;
if (!$mysqli && isset($con)  && $con  instanceof mysqli) $mysqli = $con;

if (!$mysqli) {
  $host = defined('DB_HOST') ? DB_HOST : ($DB_HOST ?? 'localhost');
  $user = defined('DB_USER') ? DB_USER : ($DB_USER ?? '');
  $pass = defined('DB_PASS') ? DB_PASS : ($DB_PASS ?? '');
  $name = defined('DB_NAME') ? DB_NAME : ($DB_NAME ?? '');
  $port = (int)(defined('DB_PORT') ? DB_PORT : ($DB_PORT ?? 3306));
  $sock = defined('DB_SOCKET') ? DB_SOCKET : ($DB_SOCKET ?? null);
  $mysqli = @new mysqli($host, $user, $pass, $name, $port ?: null, $sock ?: null);
}

if (!$mysqli || $mysqli->connect_errno) {
  json([
    'ok'=>false,
    'error'=>'Database connection failed',
    'code'=>$mysqli? $mysqli->connect_errno : null,
    'detail'=>$mysqli? $mysqli->connect_error : 'No mysqli from config.php'
  ], 500);
}
$mysqli->set_charset('utf8mb4');
// --- Remember-me auto-login (after DB is ready) ---
require_once __DIR__ . '/../includes/remember.php';
td_redeem_remember_token();
// ---------- SMALL DB HELPERS ----------
if (!function_exists('db_all')) {
  function db_all(mysqli_stmt $st): array {
    if(!$st->execute()) return [];
    $r = $st->get_result();
    return $r ? $r->fetch_all(MYSQLI_ASSOC) : [];
  }
}
if (!function_exists('db_one')) {
  function db_one(mysqli_stmt $st): ?array {
    if(!$st->execute()) return null;
    $r = $st->get_result();
    $row = $r ? $r->fetch_assoc() : null;
    return $row ?: null;
  }
}

// ---------- SCHEMA HELPERS ----------
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