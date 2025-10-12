<?php
declare(strict_types=1);

/* JSON bootstrap */
@ini_set('display_errors','0');
@ini_set('log_errors','1');
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, private');
header('Pragma: no-cache');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') { http_response_code(405); echo json_encode(['ok'=>false,'error'=>'Method not allowed']); exit; }

if (session_status() === PHP_SESSION_NONE) session_start();
require __DIR__ . '/../../../conf/config.php';
require __DIR__ . '/../../includes/auth.php'; // if available

function out_ok(array $extra = []){ echo json_encode(['ok'=>true]+$extra, JSON_INVALID_UTF8_SUBSTITUTE); exit; }
function out_err(int $code,string $msg){ http_response_code($code); echo json_encode(['ok'=>false,'error'=>$msg], JSON_INVALID_UTF8_SUBSTITUTE); exit; }

if (!isset($conn) || !($conn instanceof mysqli)) out_err(500,'DB connection missing');
if (function_exists('checkRole')) { try { checkRole(['admin','supervisor']); } catch(Throwable $e){ out_err(403,'Forbidden'); } }

$uid = (int)($_SESSION['user_id'] ?? 0);
if ($uid <= 0) out_err(401,'Not authenticated');

$raw = file_get_contents('php://input') ?: '';
$body = json_decode($raw, true);
if (!is_array($body)) out_err(400,'Invalid JSON');

$requestId   = (int)($body['request_id'] ?? 0);
$paidAmount  = isset($body['paid_amount']) ? (float)$body['paid_amount'] : null; // optional
$referenceNo = trim((string)($body['reference_no'] ?? ''));                     // optional
$notes       = trim((string)($body['notes'] ?? ''));                            // optional

if ($requestId <= 0) out_err(400,'request_id is required');

$db = $conn;
$db->begin_transaction();

try {
  // lock row
  $sel = $db->prepare("SELECT id, driver_id, amount, status, remarks FROM advance_requests WHERE id = ? FOR UPDATE");
  $sel->bind_param('i',$requestId);
  $sel->execute();
  $r = $sel->get_result()->fetch_assoc();
  $sel->close();

  if (!$r) throw new RuntimeException('Request not found');
  $status = strtolower((string)$r['status']);

  if ($status !== 'approved') {
    throw new RuntimeException('Only Approved requests can be disbursed');
  }

  // compose remarks (no schema change)
  $remarkAppend = [];
  if ($referenceNo !== '') $remarkAppend[] = "Ref: ".$referenceNo;
  if ($paidAmount !== null) $remarkAppend[] = "Paid: ₹".number_format($paidAmount,2);
  if ($notes !== '') $remarkAppend[] = "Notes: ".$notes;

  $newRemarks = trim(($r['remarks'] ?? '').(empty($remarkAppend) ? '' : (' | '.implode(' | ',$remarkAppend))));

  // update to Disbursed
  $upd = $db->prepare("
    UPDATE advance_requests
       SET status='Disbursed',
           disbursed_at = NOW(),
           approval_by_id = COALESCE(approval_by_id, ?),  -- keep original approver if present; else set to current
           remarks = ?
     WHERE id = ?
  ");
  $upd->bind_param('isi',$uid,$newRemarks,$requestId);
  $upd->execute();
  $upd->close();

  // audit trail (reuse action='approve' or add 'disburse' in enum if you want to extend)
  $ins = $db->prepare("
    INSERT INTO advance_approval_logs (request_id, driver_id, action, admin_id, comments, created_at)
    VALUES (?, ?, 'approve', ?, ?, NOW())
  ");
  $driverId = (int)$r['driver_id'];
  $adminIdStr = (string)$uid;
  $commentTrail = 'DISBURSED'.(empty($remarkAppend)?'':(' | '.implode(' | ',$remarkAppend)));
  $ins->bind_param('iiss',$requestId,$driverId,$adminIdStr,$commentTrail);
  $ins->execute();
  $ins->close();

  $db->commit();
  out_ok(['message'=>'Marked as Disbursed']);

} catch(Throwable $e){
  $db->rollback();
  out_err(400, $e->getMessage());
}