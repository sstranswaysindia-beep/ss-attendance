<?php
header('Content-Type: application/json');

/* ---------- Strict JSON error handling ---------- */
ini_set('display_errors', '1');
ini_set('display_startup_errors', '1');
error_reporting(E_ALL);
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

set_error_handler(function($severity,$message,$file,$line){
  http_response_code(500);
  echo json_encode(['ok'=>false,'type'=>'php_error','message'=>$message,'file'=>$file,'line'=>$line]);
  exit;
});
set_exception_handler(function($e){
  http_response_code(500);
  echo json_encode(['ok'=>false,'type'=>'exception','message'=>$e->getMessage(),'where'=>$e->getFile().':'.$e->getLine()]);
  exit;
});

/* ---------- Bootstrap ---------- */
require __DIR__ . '/../../conf/config.php'; // $conn + getSettingValue()
if (!($conn instanceof mysqli)) {
  http_response_code(500);
  echo json_encode(['ok'=>false,'error'=>'DB not available']);
  exit;
}
function h($s){ return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); }

/* helper: check if a column exists */
function column_exists(mysqli $conn, string $table, string $column): bool {
  $sql = "SELECT 1
            FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE()
             AND TABLE_NAME = ?
             AND COLUMN_NAME = ?
           LIMIT 1";
  $st = $conn->prepare($sql);
  $st->bind_param('ss', $table, $column);
  $st->execute();
  $st->store_result();
  $ok = $st->num_rows > 0;
  $st->close();
  return $ok;
}

/* choose assignee expression once (users.name vs users.username) */
$hasUserNameCol = column_exists($conn, 'users', 'name');
$hasUserUserCol = column_exists($conn, 'users', 'username');
if ($hasUserNameCol && $hasUserUserCol) {
  $assigneeExpr = "COALESCE(u.name, u.username)";
} elseif ($hasUserNameCol) {
  $assigneeExpr = "u.name";
} elseif ($hasUserUserCol) {
  $assigneeExpr = "u.username";
} else {
  $assigneeExpr = "NULL";
}

/* ---------- Auth (same header as others) ---------- */
$sharedKey = getSettingValue($conn, 'api.shared_key');
$incoming  = $_SERVER['HTTP_X_API_KEY'] ?? '';
if (!$sharedKey || !hash_equals(trim($sharedKey), trim($incoming))) {
  http_response_code(401);
  echo json_encode(['ok'=>false,'error'=>'Unauthorized']);
  exit;
}

/* ---------- Mail settings ---------- */
$sendToSafety = getSettingValue($conn,'safety.notification_recipients') ?: '';
$sendToCommon = getSettingValue($conn,'notification_recipients') ?: '';
$sendTo       = $sendToSafety ?: $sendToCommon;

$fromEmail   = getSettingValue($conn,'from_email') ?: getSettingValue($conn,'system_email') ?: 'do-not-reply@sstranswaysindia.com';
$fromName    = 'Safety Notifier';   // or whatever you want
$subjectPref = '[Auto Generated] - Safety Alerts (Outstanding Months)';
$preview     = isset($_GET['preview']) && $_GET['preview']=='1';

$smtpHost   = getSettingValue($conn,'smtp_host')   ?: 'smtp.hostinger.com';
$smtpPort   = (int)(getSettingValue($conn,'smtp_port') ?: 465);
$smtpSecure = getSettingValue($conn,'smtp_secure') ?: 'ssl'; // ssl/tls
$smtpUser   = getSettingValue($conn,'smtp_user')   ?: $fromEmail;
$smtpPass   = getSettingValue($conn,'smtp_pass')   ?: '';

$ccList     = getSettingValue($conn,'mail.cc')  ?: '';
$bccList    = getSettingValue($conn,'mail.bcc') ?: '';

/* ---------- Find months that still have pending (status != 'closed') ---------- */
/* We will only include months where at least one alert is pending. */
$sqlMonths = "
  SELECT
    DATE_FORMAT(a.alert_date, '%Y') AS y,
    DATE_FORMAT(a.alert_date, '%c') AS m,      -- 1..12
    DATE_FORMAT(a.alert_date, '%Y-%m') AS ym,
    SUM(CASE WHEN a.status <> 'closed' THEN 1 ELSE 0 END) AS pending_count
  FROM AL_EMAIL_ALERT a
  GROUP BY ym
  HAVING pending_count > 0
  ORDER BY ym ASC
";
$months = [];
$resM = $conn->query($sqlMonths);
while ($r = $resM->fetch_assoc()) {
  $months[] = ['y'=>(int)$r['y'], 'm'=>(int)$r['m'], 'ym'=>$r['ym'], 'pending_count'=>(int)$r['pending_count']];
}
$resM->close();

if (!$months) {
  $msg = 'All months are fully closed. Nothing to send.';
  if ($preview) {
    echo json_encode(['ok'=>true,'preview'=>true,'months'=>[],'message'=>$msg]);
  } else {
    echo json_encode(['ok'=>true,'sent'=>false,'message'=>$msg]);
  }
  exit;
}

/* ---------- Fetch all rows for those months in one go ---------- */
$yms = array_column($months, 'ym');
$in  = implode(',', array_fill(0, count($yms), '?'));

$sqlAll = "
  SELECT 
    DATE_FORMAT(a.alert_date,'%Y-%m') AS ym,
    a.id,
    a.category,
    a.transporter_name,
    COALESCE(v.vehicle_no, a.vehicle) AS vehicle_no,
    a.alert_name,
    a.alert_date,
    a.status,
    a.assigned_to_user_id,
    a.action_taken,
    a.action_taken_at,
    $assigneeExpr AS assignee_label
  FROM AL_EMAIL_ALERT a
  LEFT JOIN vehicles v ON v.id = a.vehicle_id
  LEFT JOIN users u    ON u.id = a.assigned_to_user_id
 WHERE DATE_FORMAT(a.alert_date,'%Y-%m') IN ($in)
 ORDER BY a.alert_date ASC, a.id ASC
";
$types = str_repeat('s', count($yms));
$stmt = $conn->prepare($sqlAll);
$stmt->bind_param($types, ...$yms);
$stmt->execute();
$res = $stmt->get_result();
$rows = $res->fetch_all(MYSQLI_ASSOC);
$stmt->close();

/* ---------- Build: group by month -> category, compute totals & pending list ---------- */
$baseUrl = rtrim((isset($_SERVER['HTTPS']) && $_SERVER['HTTPS']!=='off'?'https':'http').'://'.($_SERVER['HTTP_HOST'] ?? 'www.sstranswaysindia.com'),'/');

$outMonths = []; // ym => ['label'=> 'Sep 2025', 'totals'=>.., 'byCategory'=>.., 'pendingByAssignee'=>..]

foreach ($months as $mrow) {
  $ym = $mrow['ym'];
  $p = DateTime::createFromFormat('Y-m-d', $ym.'-01');
  $label = $p ? $p->format('M Y') : $ym;
  $outMonths[$ym] = [
    'label' => $label,
    'totals' => ['total'=>0,'completed'=>0,'pending'=>0],
    'byCategory' => [],               // cat => ['total','completed','pending','pendings'=>[]]
    'pendingByAssignee' => []         // name => count
  ];
}

foreach ($rows as $r) {
  $ym = $r['ym'];
  if (!isset($outMonths[$ym])) continue;

  $month = &$outMonths[$ym];
  $cat = $r['category'] ?: 'Uncategorized';
  if (!isset($month['byCategory'][$cat])) {
    $month['byCategory'][$cat] = ['total'=>0,'completed'=>0,'pending'=>0,'pendings'=>[]];
  }

  $month['totals']['total']++;
  $month['byCategory'][$cat]['total']++;

  $isClosed = (strtolower((string)$r['status']) === 'closed');
  if ($isClosed) {
    $month['totals']['completed']++;  $month['byCategory'][$cat]['completed']++;
  } else {
    $month['totals']['pending']++;    $month['byCategory'][$cat]['pending']++;

    // normalize assignee
    $assignee = trim((string)($r['assignee_label'] ?? ''));
    if ($assignee === '') $assignee = 'Unassigned';

    // days open
    $daysOpen = 0;
    if (!empty($r['alert_date'])) {
      $daysOpen = (int) floor( (time() - strtotime($r['alert_date'])) / 86400 );
      if ($daysOpen < 0) $daysOpen = 0;
    }

    $p = DateTime::createFromFormat('Y-m-d', $ym.'-01');
    $mm = $p ? (int)$p->format('n') : (int)substr($ym,5,2);
    $yy = $p ? (int)$p->format('Y') : (int)substr($ym,0,4);

    $viewUrl = $baseUrl . '/DriverDocs/safety/safetyalert.php?month=' . $mm . '&year=' . $yy . '&status=open&category=' . urlencode($cat);

    $month['byCategory'][$cat]['pendings'][] = [
      'id'          => (int)$r['id'],
      'date'        => $r['alert_date'] ? date('d-M-Y H:i', strtotime($r['alert_date'])) : '',
      'vehicle'     => $r['vehicle_no'] ?: '—',
      'alert'       => $r['alert_name'] ?: '—',
      'transporter' => $r['transporter_name'] ?: '—',
      'assignee'    => $assignee,
      'days_open'   => $daysOpen,
      'view_url'    => $viewUrl
    ];

    $month['pendingByAssignee'][$assignee] = ($month['pendingByAssignee'][$assignee] ?? 0) + 1;
  }
  unset($month);
}

/* ---------- Remove months that ended up with 0 pending (safety) ---------- */
foreach (array_keys($outMonths) as $ym) {
  if ($outMonths[$ym]['totals']['pending'] <= 0) unset($outMonths[$ym]);
}
if (!$outMonths) {
  $msg = 'All months are fully closed. Nothing to send.';
  if ($preview) echo json_encode(['ok'=>true,'preview'=>true,'months'=>[],'message'=>$msg]);
  else          echo json_encode(['ok'=>true,'sent'=>false,'message'=>$msg]);
  exit;
}

/* ---------- Build Email ---------- */
$theadBg = '#f5fbff';
$badge   = 'padding:2px 8px;border-radius:999px;background:#eef5ff;border:1px solid #cfe3ff;';

ob_start();
?>
<div style="font-family:system-ui,Segoe UI,Roboto,Arial,sans-serif">
  <h3 style="margin:0 0 8px"><?= h($subjectPref) ?></h3>
  <div style="margin:0 0 10px;color:#333">
    This report includes <strong>only those months that still have pending Safety Alerts</strong>.
    Fully closed months are excluded automatically.
  </div>
  <?php foreach ($outMonths as $ym => $mdata): ?>
    <hr style="border:none;border-top:1px solid #e8eef6;margin:14px 0">
    <h3 style="margin:0 0 6px"><?= h($mdata['label']) ?></h3>
    <?php
      $t = $mdata['totals'];
      $totalsLine = sprintf(
        'Total: %d &nbsp; <span style="%s">Completed: %d</span> &nbsp; <span style="%s">Pending: %d</span>',
        (int)$t['total'], $badge, (int)$t['completed'], $badge, (int)$t['pending']
      );
    ?>
    <div style="margin:4px 0 10px;"><?= $totalsLine ?></div>

    <?php if (!empty($mdata['pendingByAssignee'])): ?>
      <table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;width:420px;max-width:100%;margin:4px 0 12px">
        <thead style="background:<?= $theadBg ?>">
          <tr><th align="left">Assignee</th><th align="right">Pending</th></tr>
        </thead>
        <tbody>
          <?php ksort($mdata['pendingByAssignee'], SORT_NATURAL|SORT_FLAG_CASE);
          foreach ($mdata['pendingByAssignee'] as $name=>$cnt): ?>
            <tr><td><?= h($name) ?></td><td align="right"><?= (int)$cnt ?></td></tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    <?php endif; ?>

    <?php ksort($mdata['byCategory'], SORT_NATURAL|SORT_FLAG_CASE);
    foreach ($mdata['byCategory'] as $cat=>$catd): ?>
      <h4 style="margin:12px 0 4px"><?= h($cat) ?></h4>
      <div style="margin:2px 0 6px">
        <span style="<?= $badge ?>">Total: <?= (int)$catd['total'] ?></span>
        &nbsp; <span style="<?= $badge ?>">Completed: <?= (int)$catd['completed'] ?></span>
        &nbsp; <span style="<?= $badge ?>">Pending: <?= (int)$catd['pending'] ?></span>
      </div>
      <table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;width:100%;max-width:980px;margin:6px 0 12px">
        <thead style="background:<?= $theadBg ?>">
          <tr>
            <th align="left">Date</th>
            <th align="left">Vehicle</th>
            <th align="left">Alert</th>
            <th align="left">Transporter</th>
            <th align="left">Assigned To</th>
            <th align="right">Days Open</th>
            <th align="left">Link</th>
          </tr>
        </thead>
        <tbody>
          <?php if ($catd['pendings']):
            foreach ($catd['pendings'] as $p): ?>
              <tr>
                <td><?= h($p['date']) ?></td>
                <td><?= h($p['vehicle']) ?></td>
                <td><?= h($p['alert']) ?></td>
                <td><?= h($p['transporter']) ?></td>
                <td><?= h($p['assignee']) ?></td>
                <td align="right"><?= (int)$p['days_open'] ?></td>
                <td><a href="<?= h($p['view_url']) ?>" target="_blank" rel="noopener">Open</a></td>
              </tr>
            <?php endforeach; else: ?>
              <tr><td colspan="7" style="color:#777">No pending in this category.</td></tr>
          <?php endif; ?>
        </tbody>
      </table>
    <?php endforeach; ?>
  <?php endforeach; ?>

  <p style="margin:16px 0 0">Thanks &amp; Regards<br><?= h($fromName) ?></p>
</div>
<?php
$html = ob_get_clean();

/* ---------- Plain-text quick view ---------- */
$plain = $subjectPref."\nOutstanding months only.\n\n";
foreach ($outMonths as $ym=>$m) {
  $plain .= "== ".$m['label']." ==\n";
  $plain .= sprintf("Total:%d Completed:%d Pending:%d\n", $m['totals']['total'],$m['totals']['completed'],$m['totals']['pending']);
  if (!empty($m['pendingByAssignee'])) {
    $plain .= "By Assignee:\n";
    ksort($m['pendingByAssignee'], SORT_NATURAL|SORT_FLAG_CASE);
    foreach ($m['pendingByAssignee'] as $n=>$c) $plain .= "- $n: $c\n";
  }
  foreach ($m['byCategory'] as $cat=>$cd) {
    $plain .= "  * $cat -> T:{$cd['total']} C:{$cd['completed']} P:{$cd['pending']}\n";
    foreach ($cd['pendings'] as $p) {
      $plain .= sprintf("    - %s | %s | %s | %s | %s | %dd | %s\n",
        $p['date'],$p['vehicle'],$p['alert'],$p['transporter'],$p['assignee'],$p['days_open'],$p['view_url']);
    }
  }
  $plain .= "\n";
}

/* ---------- Preview? ---------- */
if ($preview) {
  echo json_encode([
    'ok'=>true,
    'preview'=>true,
    'months'=>array_values(array_map(function($k,$v){
      return ['ym'=>$k,'label'=>$v['label'],'totals'=>$v['totals']];
    }, array_keys($outMonths), array_values($outMonths))),
  ]);
  exit;
}

/* ---------- Load PHPMailer ---------- */
$autoloads = [
  __DIR__ . '/../DriverDocs/vendor/autoload.php',
  $_SERVER['DOCUMENT_ROOT'] . '/DriverDocs/vendor/autoload.php',
  __DIR__ . '/../vendor/autoload.php',
  __DIR__ . '/vendor/autoload.php',
];
$loaded = false;
foreach ($autoloads as $p) { if (is_file($p)) { require $p; $loaded = true; break; } }
if (!$loaded) {
  http_response_code(500);
  echo json_encode(['ok'=>false,'type'=>'phpmailer_missing','message'=>'Composer autoload not found','paths_tried'=>$autoloads]);
  exit;
}
use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception;

/* ---------- Send ---------- */
$toList = array_filter(array_map('trim', explode(',', $sendTo)));
if (!$toList) {
  http_response_code(500);
  echo json_encode(['ok'=>false,'error'=>'No recipients configured (safety.notification_recipients or notification_recipients)']);
  exit;
}

$subject = $subjectPref;
$mail = new PHPMailer(true);
try {
  $mail->isSMTP();
  $mail->Host       = $smtpHost;
  $mail->Port       = $smtpPort;
  $mail->SMTPAuth   = true;
  $mail->Username   = $smtpUser;
  $mail->Password   = $smtpPass;
  $mail->SMTPSecure = $smtpSecure;

  $mail->setFrom($fromEmail, $fromName);
  if (strcasecmp($fromEmail, $smtpUser) !== 0) $mail->addReplyTo($fromEmail, $fromName);

  foreach ($toList as $addr) $mail->addAddress($addr);
  if ($ccList)  foreach (explode(',', $ccList)  as $cc)  { $cc=trim($cc);   if ($cc)  $mail->addCC($cc); }
  if ($bccList) foreach (explode(',', $bccList) as $bcc) { $bcc=trim($bcc); if ($bcc) $mail->addBCC($bcc); }

  $mail->isHTML(true);
  $mail->Subject = $subject;
  $mail->Body    = $html;
  $mail->AltBody = $plain;

  $mail->send();
} catch (Exception $e) {
  http_response_code(500);
  echo json_encode(['ok'=>false,'type'=>'mailer','error'=>$mail->ErrorInfo]);
  exit;
}

/* ---------- Done ---------- */
echo json_encode([
  'ok'=>true,
  'sent'=>true,
  'months'=>array_values(array_map(function($k,$v){
    return ['ym'=>$k,'label'=>$v['label'],'totals'=>$v['totals']];
  }, array_keys($outMonths), array_values($outMonths)))
]);