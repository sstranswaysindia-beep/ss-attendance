<?php
// /TripDetails/api/logout.php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';
require_once __DIR__ . '/../includes/remember.php'; // ★ add this

/* JSON helper */
if (!function_exists('json_out')) {
  function json_out($p,int $s=200){
    while (function_exists('ob_get_level') && ob_get_level() > 0) @ob_end_clean();
    if (!headers_sent()) {
      http_response_code($s);
      header('Content-Type: application/json; charset=utf-8');
      header('Cache-Control: no-store, no-cache, must-revalidate, private');
      header('Pragma: no-cache');
      header('Expires: 0');
    }
    echo json_encode($p, JSON_UNESCAPED_UNICODE);
    exit;
  }
}

/* Ensure session is started so we can destroy it */
if (session_status() !== PHP_SESSION_ACTIVE) { @session_start(); }

/* Kill session contents and cookie */
$_SESSION = [];
if (ini_get('session.use_cookies')) {
  $p = session_get_cookie_params();
  // Expire current app cookie (TDSESSID, path=/TripDetails/)
  setcookie(session_name(), '', time()-42000, $p['path'], $p['domain'], $p['secure'], $p['httponly']);
}
// Extra: also expire legacy PHPSESSID cookie at root path
$isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') 
           || ((int)($_SERVER['SERVER_PORT'] ?? 80) === 443);
setcookie('PHPSESSID', '', time()-42000, '/', '', $isHttps, true);

/* Destroy the session on server */
@session_destroy();

/* ★ Clear persistent remember-me cookie */
td_clear_remember_cookie();

/* Optional: revoke all tokens for this user (logout from all devices) */
// if (!empty($_SESSION['user_id'])) {
//   td_revoke_all_tokens_for((int)$_SESSION['user_id']);
// }

/* Ask browser to clear caches/storage if supported */
@header('Clear-Site-Data: "cache", "cookies", "storage"');

json_out(['ok'=>true]);