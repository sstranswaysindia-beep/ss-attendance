<?php
// /TripDetails/api/auth_login.php

// ---- Hardened fatal catcher + logging ----
@ini_set('display_errors','0');
@ini_set('log_errors','1');

$DEBUG_FILE = rtrim(sys_get_temp_dir(), DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . 'td_auth_login.log';
@ini_set('error_log', $DEBUG_FILE);

function _log($m){
  global $DEBUG_FILE;
  @error_log('[auth_login] '.$m);
  @file_put_contents($DEBUG_FILE, '['.date('c').'] '.$m."\n", FILE_APPEND);
}
function _json($payload, int $status=200){
  if (function_exists('ob_get_level')) { while (ob_get_level() > 0) @ob_end_clean(); }
  http_response_code($status);
  header('Content-Type: application/json; charset=utf-8');
  echo json_encode($payload, JSON_UNESCAPED_UNICODE);
  exit;
}

$__fatal_already_sent = false;
register_shutdown_function(function() use (&$__fatal_already_sent){
  if ($__fatal_already_sent) return;
  $e = error_get_last();
  if ($e && in_array($e['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR])) {
    _log('FATAL: '.$e['message'].' in '.$e['file'].':'.$e['line']);
    $__fatal_already_sent = true;
    if (!headers_sent()) header('Content-Type: application/json; charset=utf-8');
    http_response_code(500);
    echo json_encode(['ok'=>false,'error'=>'Fatal: '.$e['message']], JSON_UNESCAPED_UNICODE);
  }
});

// ---- bring bootstrap (session + db) ----
require __DIR__ . '/bootstrap.php';

// ---- optional self-test: /auth_login.php?selftest=1
if (isset($_GET['selftest'])) {
  _log('selftest ping');
  _json(['ok'=>true,'php'=>PHP_VERSION,'sid'=>session_id(),'sess_name'=>session_name()]);
}

// ---- parse input (form or json) ----
try {
  $in = $_POST;
  $ct = strtolower($_SERVER['CONTENT_TYPE'] ?? '');
  if (strpos($ct,'json') !== false) {
    $raw = file_get_contents('php://input') ?: '';
    $j = json_decode($raw, true);
    if (is_array($j)) $in = $j;
  }

  $username = trim((string)($in['username'] ?? ''));
  $password = (string)($in['password'] ?? '');
  $remember = filter_var($in['remember'] ?? false, FILTER_VALIDATE_BOOLEAN); // ★ parse remember
  _log("boot; received user='{$username}' pass_len=".strlen($password)." remember=".($remember?'1':'0'));

  if ($username === '' || $password === '') {
    _log('missing username/password');
    _json(['ok'=>false,'error'=>'Username and password required'], 422);
  }

  // ---- DB connection from bootstrap ----
  /** @var mysqli|null $mysqli */
  $db = $mysqli ?? ($conn ?? null) ?? ($con ?? null);
  if (!$db || ($db instanceof mysqli && $db->connect_errno)) {
    _log('DB unavailable');
    _json(['ok'=>false,'error'=>'DB unavailable'], 500);
  }
  @$db->set_charset('utf8mb4');

  // ---- query user
  $sql = "SELECT id, driver_id, username, password, role, must_change_password
          FROM users WHERE username=? LIMIT 1";
  $st = $db->prepare($sql);
  if (!$st) {
    _log('prepare failed: '.$db->error);
    _json(['ok'=>false,'error'=>'DB prepare failed: '.$db->error], 500);
  }
  $st->bind_param('s', $username);
  $st->execute();
  $res  = $st->get_result();
  $user = ($res && $res->num_rows) ? $res->fetch_assoc() : null;
  $st->close();

  if (!$user) {
    _log("no such user '{$username}'");
    _json(['ok'=>false,'error'=>'Invalid username or password'], 401);
  }

  // ---- verify hash
  if (!password_verify($password, (string)$user['password'])) {
    _log('bad password for '.$username);
    _json(['ok'=>false,'error'=>'Invalid username or password'], 401);
  }

  // ---- success -> session (force under TDSESSID)
  session_regenerate_id(true);  // keep same session_name from bootstrap.php (TDSESSID)
  $_SESSION['user_id']   = (int)$user['id'];
  $_SESSION['role']      = (string)$user['role'];
  $_SESSION['driver_id'] = (int)($user['driver_id'] ?? 0);
  _log('SUCCESS uid='.$_SESSION['user_id'].' role='.$_SESSION['role'].' drv='.$_SESSION['driver_id'].' sess='.session_name());

  // ★ Remember-me: mint token & cookie if requested
  if ($remember) {
    require_once __DIR__ . '/../includes/remember.php'; // safe if already loaded
    td_mint_remember_token($_SESSION['user_id']);
  }

  // stamp last_login_at (best-effort)
  if ($upd = $db->prepare("UPDATE users SET last_login_at=NOW() WHERE id=?")) {
    $upd->bind_param('i', $_SESSION['user_id']);
    $upd->execute();
    $upd->close();
  }

  $__fatal_already_sent = true;
  _json([
    'ok'=>true,
    'user'=>[
      'id'        => $_SESSION['user_id'],
      'username'  => (string)$user['username'],
      'role'      => (string)$user['role'],
      'driver_id' => $user['driver_id'] ? (int)$user['driver_id'] : null,
      'must_change_password' => (int)$user['must_change_password'],
    ],
    'sid'      => session_id(),
    'sess'     => session_name(),
    'remember' => $remember // ★ optional: tell client we set remember
  ]);

} catch (Throwable $e) {
  _log('EXCEPTION: '.$e->getMessage().' @ '.$e->getFile().':'.$e->getLine());
  $__fatal_already_sent = true;
  _json(['ok'=>false,'error'=>'Server exception: '.$e->getMessage()], 500);
}