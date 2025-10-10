<?php
declare(strict_types=1);
header('Content-Type: application/json');

$cookiePath = '/';
$secure = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');

session_set_cookie_params(['lifetime'=>0,'path'=>$cookiePath,'httponly'=>true,'secure'=>$secure,'samesite'=>'Lax']);
if (session_status() === PHP_SESSION_NONE) session_start();

echo json_encode([
  'ok' => true,
  'session_id' => session_id(),
  'has_user' => !empty($_SESSION['user']),
  'user' => $_SESSION['user'] ?? null
]);