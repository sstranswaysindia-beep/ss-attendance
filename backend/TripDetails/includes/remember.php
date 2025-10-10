<?php
// /TripDetails/includes/remember.php

if (!defined('TD_REM_COOKIE')) define('TD_REM_COOKIE', 'TDREM');
if (!defined('TD_REM_DAYS'))   define('TD_REM_DAYS', 45); // persistence window

function td_db() {
  // Reuse mysqli created by bootstrap.php
  global $mysqli, $conn, $con;
  return $mysqli ?? ($conn ?? $con ?? null);
}

function td_cookie_args(int $expTs): array {
  $p = session_get_cookie_params(); // inherits path=/TripDetails/ from your bootstrap
  return [
    'expires'  => $expTs,
    'path'     => $p['path'] ?? '/',
    'domain'   => $p['domain'] ?? '',
    'secure'   => !empty($_SERVER['HTTPS']),
    'httponly' => true,
    'samesite' => 'Lax',
  ];
}

function td_mint_remember_token(int $user_id, int $days = TD_REM_DAYS): void {
  $db = td_db(); if (!$db) return;

  $raw   = random_bytes(32);
  $token = bin2hex($raw);          // 64 chars
  $hash  = hash('sha256', $token);

  $expTs  = time() + ($days * 86400);
  $expiry = date('Y-m-d H:i:s', $expTs);

  if ($st = $db->prepare("INSERT INTO user_tokens (user_id, token_hash, expires_at) VALUES (?,?,?)")) {
    $st->bind_param('iss', $user_id, $hash, $expiry);
    $st->execute();
    $st->close();
  }

  setcookie(TD_REM_COOKIE, $token, td_cookie_args($expTs));
}

function td_clear_remember_cookie(): void {
  setcookie(TD_REM_COOKIE, '', td_cookie_args(time() - 3600));
}

function td_redeem_remember_token(): bool {
  if (!empty($_SESSION['user_id'])) return true;
  if (empty($_COOKIE[TD_REM_COOKIE])) return false;

  $token = $_COOKIE[TD_REM_COOKIE];
  if (!is_string($token) || strlen($token) < 40) { td_clear_remember_cookie(); return false; }

  $db = td_db(); if (!$db) return false;
  $hash = hash('sha256', $token);

  $sql = "SELECT ut.id, ut.user_id, u.username, u.role, u.driver_id
          FROM user_tokens ut
          JOIN users u ON u.id = ut.user_id
          WHERE ut.token_hash=? AND ut.expires_at > NOW()
          LIMIT 1";
  if (!($st = $db->prepare($sql))) { td_clear_remember_cookie(); return false; }
  $st->bind_param('s', $hash);
  $st->execute();
  $res = $st->get_result();
  $row = ($res && $res->num_rows) ? $res->fetch_assoc() : null;
  $st->close();

  if (!$row) { td_clear_remember_cookie(); return false; }

  // One-time use: rotate token
  if ($del = $db->prepare("DELETE FROM user_tokens WHERE id=?")) {
    $del->bind_param('i', $row['id']);
    $del->execute();
    $del->close();
  }

  session_regenerate_id(true);
  $_SESSION['user_id']   = (int)$row['user_id'];
  $_SESSION['role']      = (string)$row['role'];
  $_SESSION['driver_id'] = (int)($row['driver_id'] ?? 0);

  // optional: touch last_login_at
  if ($upd = $db->prepare("UPDATE users SET last_login_at=NOW() WHERE id=?")) {
    $upd->bind_param('i', $_SESSION['user_id']);
    $upd->execute();
    $upd->close();
  }

  // Extend persistence window
  td_mint_remember_token($_SESSION['user_id']);

  return true;
}

function td_revoke_all_tokens_for(int $user_id): void {
  $db = td_db(); if (!$db) return;
  if ($st = $db->prepare("DELETE FROM user_tokens WHERE user_id=?")) {
    $st->bind_param('i', $user_id);
    $st->execute();
    $st->close();
  }
  td_clear_remember_cookie();
}