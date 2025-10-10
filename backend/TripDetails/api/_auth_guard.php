<?php
// /TripDetails/api/_auth_guard.php
require_once __DIR__ . '/bootstrap.php';

// consider logged-in if we have a user_id (set by auth_login.php)
if (empty($_SESSION['user_id'])) {
  if (!headers_sent()) header('Content-Type: application/json; charset=utf-8');
  echo json_encode(['ok'=>false,'error'=>'Unauthorized'], JSON_UNESCAPED_UNICODE);
  exit;
}