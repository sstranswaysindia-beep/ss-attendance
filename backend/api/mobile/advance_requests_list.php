<?php
declare(strict_types=1);

@ini_set('display_errors','0');
@ini_set('log_errors','1');
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, private');
header('Pragma: no-cache');

if (session_status() === PHP_SESSION_NONE) session_start();
require __DIR__ . '/../../../conf/config.php';

function out_ok(array $data, int $code=200): void {
  http_response_code($code);
  echo json_encode(['ok'=>true,'data'=>$data], JSON_INVALID_UTF8_SUBSTITUTE);
  exit;
}
function out_err(string $msg, int $code=500): void {
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

try {
  if (!isset($conn) || !($conn instanceof mysqli)) out_err('DB connection missing', 500);
  $db = $conn;

  // Inputs
  $qStatus = strtolower(trim($_GET['status'] ?? 'all'));
  $allowed = ['all','pending','approved','rejected','disbursed'];
  if (!in_array($qStatus, $allowed, true)) $qStatus = 'all';

  $page  = max(1, (int)($_GET['page']  ?? 1));
  $limit = min(50, max(1, (int)($_GET['limit'] ?? 20)));
  $offset = ($page - 1) * $limit;

  // Counts (map to enum-case in DB)
  $caps = ['pending'=>'Pending','approved'=>'Approved','rejected'=>'Rejected','disbursed'=>'Disbursed'];
  $counts = ['total'=>0,'pending'=>0,'approved'=>0,'rejected'=>0,'disbursed'=>0];

  foreach ($caps as $k=>$val) {
    $st = $db->prepare("SELECT COUNT(*) FROM advance_requests WHERE status=?");
    $st->bind_param('s',$val);
    $st->execute();
    $res = $st->get_result()->fetch_row();
    $counts[$k] = (int)($res[0] ?? 0);
    $st->close();
  }
  $res = $db->query("SELECT COUNT(*) FROM advance_requests")->fetch_row();
  $counts['total'] = (int)($res[0] ?? 0);

  // WHERE
  $where = '';
  $types = '';
  $params = [];
  if ($qStatus !== 'all') {
    $where = "WHERE ar.status = ?";
    $types .= 's';
    $params[] = $caps[$qStatus];
  }

  // Total for pagination
  $sqlTot = "SELECT COUNT(*) FROM advance_requests ar $where";
  $st = $db->prepare($sqlTot);
  if ($types) $st->bind_param($types, ...$params);
  $st->execute();
  $row = $st->get_result()->fetch_row();
  $totalCount = (int)($row[0] ?? 0);
  $st->close();

  // Main list
  // vehicle via current assignment (assignments has uq_driver), plant from drivers or assignment
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
      ar.remarks                 AS admin_comments,
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
    LEFT JOIN drivers d        ON d.id = ar.driver_id
    LEFT JOIN users u          ON u.id = ar.approval_by_id
    LEFT JOIN assignments a    ON a.driver_id = d.id
    LEFT JOIN vehicles v       ON v.id = a.vehicle_id
    LEFT JOIN plants  p1       ON p1.id = d.plant_id
    LEFT JOIN plants  p2       ON p2.id = a.plant_id
    $where
    ORDER BY ar.requested_at DESC, ar.id DESC
    LIMIT ? OFFSET ?
  ";

  $types2  = $types . 'ii';
  $params2 = $params; $params2[] = $limit; $params2[] = $offset;

  $st = $db->prepare($sql);
  $st->bind_param($types2, ...$params2);
  $st->execute();
  $rs = $st->get_result();

  $rows = [];
  while ($r = $rs->fetch_assoc()) {
    $rows[] = [
      'id'                       => (int)$r['id'],
      'driver_id'                => (int)$r['driver_id'],
      'amount'                   => (float)$r['amount'],
      'reason'                   => (string)($r['reason'] ?? ''),
      'status'                   => (string)$r['status'],
      'status_label'             => status_label($r['status']),
      'created_at'               => (string)$r['created_at'],
      'formatted_date'           => date_fmt($r['created_at']),
      'approved_at'              => (string)($r['approved_at'] ?? ''),
      'formatted_approved_date'  => date_fmt($r['approved_at'] ?? ''),
      'disbursed_at'             => (string)($r['disbursed_at'] ?? ''),
      'formatted_disbursed_date' => date_fmt($r['disbursed_at'] ?? ''),
      'admin_comments'           => (string)($r['admin_comments'] ?? ''),
      'approver_name'            => (string)($r['approver_name'] ?? ''),
      'employee_id'              => (string)($r['employee_id'] ?? ''),
      'driver_name'              => (string)($r['driver_name'] ?? ''),
      'vehicle_number'           => (string)($r['vehicle_number'] ?? ''),
      'plant_name'               => (string)($r['plant_name'] ?? ''),
      'formatted_amount'         => money_fmt($r['amount']),
    ];
  }
  $st->close();

  $totalPages = max(1, (int)ceil($totalCount / $limit));

  out_ok([
    'requests'       => $rows,
    'status_counts'  => $counts,
    'pagination'     => [
      'current_page' => $page,
      'total_pages'  => $totalPages,
      'limit'        => $limit,
      'has_prev'     => $page > 1,
      'has_next'     => $page < $totalPages,
    ],
    'filters'        => ['status'=>$qStatus],
  ]);

} catch (Throwable $e) {
  error_log("advance_requests_list error: ".$e->getMessage().' @ '.$e->getFile().':'.$e->getLine());
  out_err('Internal error', 500);
}