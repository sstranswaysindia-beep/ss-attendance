<?php
declare(strict_types=1);

/* -------- JSON-only bootstrap -------- */
@ini_set('display_errors','0');
@ini_set('log_errors','1');
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, private');
header('Pragma: no-cache');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') { http_response_code(405); echo json_encode(['ok'=>false,'error'=>'Method not allowed']); exit; }

if (session_status() === PHP_SESSION_NONE) session_start();
require __DIR__ . '/../../../conf/config.php';
$approverId = isset($_SESSION['user_id']) ? (int)$_SESSION['user_id'] : 0;

function out_ok(array $extra=[]): never { echo json_encode(['ok'=>true]+$extra, JSON_INVALID_UTF8_SUBSTITUTE); exit; }
function out_err(int $code, string $msg): never { http_response_code($code); echo json_encode(['ok'=>false,'error'=>$msg], JSON_INVALID_UTF8_SUBSTITUTE); exit; }

if (!isset($conn) || !($conn instanceof mysqli)) out_err(500,'DB connection missing');
// Optional: role guard if you have it
if (function_exists('checkRole')) { try { checkRole(['admin','supervisor']); } catch(Throwable $e){ out_err(403,'Forbidden'); } }
if ($approverId <= 0) out_err(401,'Not authenticated');

/* -------- Read JSON body -------- */
$payload = json_decode(file_get_contents('php://input') ?: '', true);
if (!is_array($payload)) out_err(400,'Invalid JSON');

$requestId = (int)($payload['request_id'] ?? 0);
$action    = strtolower(trim((string)($payload['action'] ?? '')));
$comments  = trim((string)($payload['comments'] ?? ''));

if ($requestId <= 0) out_err(400,'request_id is required');
if (!in_array($action, ['approve','reject'], true)) out_err(400,'action must be approve or reject');

$db = $conn;
$db->begin_transaction();

try {
  // Lock the request
  $sel = $db->prepare("SELECT id, status, driver_id FROM advance_requests WHERE id=? FOR UPDATE");
  $sel->bind_param('i', $requestId);
  $sel->execute();
  $req = $sel->get_result()->fetch_assoc();
  $sel->close();

  if (!$req) throw new RuntimeException('Request not found');

  // Your enum values are capitalized
  $current = (string)$req['status'];
  if ($current !== 'Pending') throw new RuntimeException('Only Pending requests can be updated');

  $newStatus = ($action === 'approve') ? 'Approved' : 'Rejected';

  // Update request (note: approval_by_id column)
  $upd = $db->prepare("
    UPDATE advance_requests
       SET status=?, approval_at=NOW(), approval_by_id=?, remarks=?
     WHERE id=?
  ");
  $upd->bind_param('sisi', $newStatus, $approverId, $comments, $requestId);
  $upd->execute();
  $upd->close();

  // Audit log
  $adminIdStr = (string)$approverId; // advance_approval_logs.admin_id is varchar(100)
  $ins = $db->prepare("
    INSERT INTO advance_approval_logs (request_id, driver_id, action, admin_id, comments, created_at)
    VALUES (?,?,?,?,?, NOW())
  ");
  $ins->bind_param('iisss', $requestId, $req['driver_id'], $action, $adminIdStr, $comments);
  $ins->execute();
  $ins->close();

  // Return updated row (join approver via approval_by_id)
  $get = $db->prepare("
    SELECT ar.id, ar.driver_id, ar.amount, ar.purpose AS reason, ar.status,
           ar.requested_at, ar.approval_at, ar.remarks AS approval_comments,
           u.full_name AS approver_name
      FROM advance_requests ar
      LEFT JOIN users u ON u.id = ar.approval_by_id
     WHERE ar.id = ?
     LIMIT 1
  ");
  $get->bind_param('i', $requestId);
  $get->execute();
  $row = $get->get_result()->fetch_assoc() ?: [];
  $get->close();

  $db->commit();

  out_ok([
    'message' => ($newStatus === 'Approved') ? 'Request approved' : 'Request rejected',
    'request' => $row,
  ]);

} catch (Throwable $e) {
  $db->rollback();
  out_err(400, $e->getMessage());
}