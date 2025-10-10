<?php
//declare(strict_types=1);
header('Content-Type: application/json');

require __DIR__ . '/_auth_guard.php';
require __DIR__ . '/bootstrap.php';

$db = (isset($conn) && $conn instanceof mysqli) ? $conn : $mysqli;

$body = json_decode(file_get_contents('php://input'), true) ?? [];
$trip_id = isset($body['trip_id']) ? (int)$body['trip_id'] : 0;
if ($trip_id<=0) { echo json_encode(['ok'=>false,'error'=>'trip_id required']); exit; }

// (optional) role gate e.g. only admin
// if (($_SESSION['user']['role'] ?? '') !== 'admin') { echo json_encode(['ok'=>false,'error'=>'Forbidden']); exit; }

if ($st = $db->prepare("DELETE FROM trips WHERE id=?")) {
  $st->bind_param('i',$trip_id); $st->execute(); $st->close();
  echo json_encode(['ok'=>true]); exit;
}
echo json_encode(['ok'=>false,'error'=>'delete failed']);