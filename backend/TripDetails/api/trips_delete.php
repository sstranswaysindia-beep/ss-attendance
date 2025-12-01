<?php
//declare(strict_types=1);
header('Content-Type: application/json');

require __DIR__ . '/_auth_guard.php';
require __DIR__ . '/bootstrap.php';
require_once __DIR__ . '/trip_notifications.php';

$db = (isset($conn) && $conn instanceof mysqli) ? $conn : $mysqli;
if (!$db instanceof mysqli || $db->connect_errno) {
  echo json_encode(['ok'=>false,'error'=>'Database connection unavailable']);
  exit;
}
@$db->set_charset('utf8mb4');

$body = json_decode(file_get_contents('php://input'), true) ?? [];
$GLOBALS['TD_MOBILE_REQUEST'] = is_array($body) ? $body : [];
$trip_id = isset($body['trip_id']) ? (int)$body['trip_id'] : 0;
if ($trip_id<=0) { echo json_encode(['ok'=>false,'error'=>'trip_id required']); exit; }

$tripSnapshot = td_trip_fetch_snapshot($db, $trip_id);
if (!$tripSnapshot) {
  echo json_encode(['ok'=>false,'error'=>'Trip not found']); exit;
}

// (optional) role gate e.g. only admin
// if (($_SESSION['user']['role'] ?? '') !== 'admin') { echo json_encode(['ok'=>false,'error'=>'Forbidden']); exit; }

if ($st = $db->prepare("DELETE FROM trips WHERE id=?")) {
  $st->bind_param('i',$trip_id);
  $st->execute();
  $affected = $st->affected_rows;
  $st->close();

  if ($affected <= 0) {
    echo json_encode(['ok'=>false,'error'=>'Delete failed']); exit;
  }

  $session = (isset($_SESSION) && is_array($_SESSION)) ? $_SESSION : [];
  $sessionUser = (isset($session['user']) && is_array($session['user'])) ? $session['user'] : [];
  $sessionDriver = (isset($session['driver']) && is_array($session['driver'])) ? $session['driver'] : [];

  $deletedByUserId = isset($_SESSION['user_id']) ? (int)$_SESSION['user_id'] : null;
  $deletedByDriverId = isset($_SESSION['driver_id']) ? (int)$_SESSION['driver_id'] : null;
  $fallbackName = $_SESSION['full_name']
      ?? ($_SESSION['username']
          ?? ($_SESSION['name']
              ?? ($_SESSION['driver_name'] ?? null)));
  try {
    $deletedBy = td_trip_resolve_deleted_by($db, $deletedByUserId, $deletedByDriverId, $fallbackName);

    if (($deletedBy['user_id'] ?? null) === null) {
      $deletedBy['user_id'] = td_trip_first_valid_int([
        $deletedByUserId,
        $session['user_id'] ?? null,
        $session['id'] ?? null,
        $sessionUser['id'] ?? null,
        $sessionUser['user_id'] ?? null,
      ]);
    }
    if (($deletedBy['driver_id'] ?? null) === null) {
      $deletedBy['driver_id'] = td_trip_first_valid_int([
        $deletedByDriverId,
        $session['driver_id'] ?? null,
        $sessionDriver['id'] ?? null,
        $sessionDriver['driver_id'] ?? null,
      ]);
    }
    if (!isset($deletedBy['name']) || trim((string)$deletedBy['name']) === '') {
      $deletedBy['name'] = td_trip_first_non_empty_string([
        $fallbackName,
        $session['full_name'] ?? null,
        $session['username'] ?? null,
        $session['name'] ?? null,
        $session['display_name'] ?? null,
        $sessionUser['full_name'] ?? null,
        $sessionUser['username'] ?? null,
        $sessionUser['name'] ?? null,
        $sessionUser['display_name'] ?? null,
        $session['driver_name'] ?? null,
        $sessionDriver['name'] ?? null,
        $sessionDriver['full_name'] ?? null,
      ]) ?? 'Unknown user';
    }

    td_trip_record_notification($db, $tripSnapshot, $deletedBy);
  } catch (Throwable $notifyError) {
    error_log('[td_trips_delete] notification_log_failed: ' . $notifyError->getMessage());
  }

  echo json_encode(['ok'=>true]); exit;
}
echo json_encode(['ok'=>false,'error'=>'delete failed']);
