<?php
declare(strict_types=1);

@ini_set('display_errors','0');
@ini_set('log_errors','1');
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, private');
header('Pragma: no-cache');

if (session_status() === PHP_SESSION_NONE) session_start();

require __DIR__ . '/../../../conf/config.php';            // adjust if your path differs
// If you gate APIs by role, keep this; otherwise comment it.
// require __DIR__ . '/../../includes/auth.php';
// try { checkRole(['admin','supervisor']); } catch (Throwable $e) { out_err('Forbidden', 403); }

/* ---------- helpers ---------- */
function out_ok(array $data, int $code=200): never {
  http_response_code($code);
  echo json_encode(['ok'=>true,'data'=>$data], JSON_INVALID_UTF8_SUBSTITUTE);
  exit;
}
function out_err(string $msg='Internal error', int $code=500): never {
  http_response_code($code);
  echo json_encode(['ok'=>false,'error'=>$msg,'data'=>[]], JSON_INVALID_UTF8_SUBSTITUTE);
  exit;
}
function money_fmt($n): string { return '₹'.number_format((float)$n,2); }
function date_fmt(?string $d): string {
  if(!$d) return '';
  $ts = strtotime($d); return $ts ? date('M j, Y g:i A', $ts) : '';
}
function status_label(string $s): string {
  $l = strtolower($s);
  return $l==='pending'?'Pending'
       :($l==='approved'?'Approved'
       :($l==='rejected'?'Rejected'
       :($l==='disbursed'?'Disbursed':ucfirst($s))));
}

/* ---------- input ---------- */
$id = (int)($_GET['id'] ?? 0);
if ($id <= 0) out_err('Invalid id', 400);

try {
  if (!isset($conn) || !($conn instanceof mysqli)) out_err('DB connection missing', 500);
  $db = $conn;
  mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

  /* ---- main request + joins (only columns we know exist) ---- */
  $sql = "
    SELECT
      ar.id,
      ar.driver_id,
      ar.amount,
      ar.purpose                 AS reason,
      ar.status,
      ar.requested_at            AS created_at,
      ar.approval_at             AS approved_at,
      ar.disbursed_at            AS disbursed_at,
      ar.remarks                 AS approval_comments,
      ar.approval_by_id          AS approver_user_id,

      d.name                     AS driver_name,
      d.empid                    AS employee_id,
      d.plant_id                 AS driver_plant_id,

      u.full_name                AS approver_name,

      a.plant_id                 AS assign_plant_id,
      a.vehicle_id               AS assign_vehicle_id,
      v.vehicle_no               AS vehicle_number,

      COALESCE(p1.plant_name, p2.plant_name) AS plant_name

    FROM advance_requests ar
    LEFT JOIN drivers d     ON d.id = ar.driver_id
    LEFT JOIN users u       ON u.id = ar.approval_by_id
    LEFT JOIN assignments a ON a.driver_id = d.id
    LEFT JOIN vehicles v    ON v.id = a.vehicle_id
    LEFT JOIN plants  p1    ON p1.id = d.plant_id
    LEFT JOIN plants  p2    ON p2.id = a.plant_id
    WHERE ar.id = ?
    LIMIT 1
  ";
  $st = $db->prepare($sql);
  $st->bind_param('i', $id);
  $st->execute();
  $r = $st->get_result()->fetch_assoc();
  $st->close();

  if (!$r) out_err('Request not found', 404);

  /* ---- request object (matches frontend) ---- */
  $req = [
    'id'                       => (int)$r['id'],
    'driver_id'                => (int)$r['driver_id'],
    'amount'                   => (float)$r['amount'],
    'formatted_amount'         => money_fmt($r['amount']),
    'reason'                   => (string)($r['reason'] ?? ''),
    'status'                   => (string)$r['status'],
    'status_label'             => status_label($r['status']),
    'created_at'               => (string)$r['created_at'],
    'formatted_date'           => date_fmt($r['created_at']),
    'approved_at'              => (string)($r['approved_at'] ?? ''),
    'formatted_approved_date'  => date_fmt($r['approved_at'] ?? ''),
    'disbursed_at'             => (string)($r['disbursed_at'] ?? ''),
    'formatted_disbursed_date' => date_fmt($r['disbursed_at'] ?? ''),
    'approval_comments'        => (string)($r['approval_comments'] ?? ''),
    'approver_name'            => (string)($r['approver_name'] ?? ''),
  ];

  /* ---- driver object (safe minimal fields) ---- */
  $driver = [
    'id'                     => (int)$r['driver_id'],
    'name'                   => (string)($r['driver_name'] ?? ''),
    'employee_id'            => (string)($r['employee_id'] ?? ''),
    'vehicle_number'         => (string)($r['vehicle_number'] ?? ''),
    'plant_name'             => (string)($r['plant_name'] ?? ''),
    'formatted_joining_date' => '',   // not available in your schema; leave empty
    'formatted_salary'       => '',   // not available in your schema; leave empty
  ];

  /* ---- history for this driver (latest 10) ---- */
  $hist = [];
  if (!empty($r['driver_id'])) {
    $hsql = "
      SELECT id, amount, status, requested_at AS created_at, purpose AS reason
      FROM advance_requests
      WHERE driver_id = ?
      ORDER BY requested_at DESC, id DESC
      LIMIT 10
    ";
    $hs = $db->prepare($hsql);
    $hs->bind_param('i', $r['driver_id']);
    $hs->execute();
    $res = $hs->get_result();
    while ($h = $res->fetch_assoc()) {
      $hist[] = [
        'id'               => (int)$h['id'],
        'amount'           => (float)$h['amount'],
        'formatted_amount' => money_fmt($h['amount']),
        'status'           => (string)$h['status'],
        'status_label'     => status_label($h['status']),
        'created_at'       => (string)$h['created_at'],
        'formatted_date'   => date_fmt($h['created_at']),
        'reason'           => (string)($h['reason'] ?? ''),
      ];
    }
    $hs->close();
  }

  /* ---- stats: total approved for this driver ---- */
  $stats = [
    'total_amount'           => 0.0,
    'formatted_total_amount' => money_fmt(0),
    'total_requests'         => 0,
  ];
  if (!empty($r['driver_id'])) {
    $sqli = "
      SELECT COALESCE(SUM(amount),0) AS tot, COUNT(*) AS cnt
      FROM advance_requests
      WHERE driver_id = ? AND LOWER(status) = 'approved'
    ";
    $ss = $db->prepare($sqli);
    $ss->bind_param('i', $r['driver_id']);
    $ss->execute();
    [$tot, $cnt] = $ss->get_result()->fetch_row() ?: [0,0];
    $ss->close();

    $stats['total_amount']           = (float)$tot;
    $stats['formatted_total_amount'] = money_fmt($tot);
    $stats['total_requests']         = (int)$cnt;
  }

  out_ok([
    'request'         => $req,
    'driver'          => $driver,
    'advance_history' => $hist,
    'advance_stats'   => $stats,
  ]);

} catch (Throwable $e) {
  error_log("advance_request_details error: ".$e->getMessage().' @ '.$e->getFile().':'.$e->getLine());
  out_err('Internal error', 500);
}