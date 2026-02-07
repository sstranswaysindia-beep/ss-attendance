<?php
header('Content-Type: application/json');

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

require __DIR__ . '/../../conf/config.php'; // $conn + getSettingValue()
if (!($conn instanceof mysqli)) {
  http_response_code(500);
  echo json_encode(['ok'=>false,'error'=>'DB not available']);
  exit;
}

$logDir = ($_SERVER['DOCUMENT_ROOT'] ?? '') . '/DriverDocs/logs';
$logFile = $logDir . '/leave_email.log';
if ($logDir !== '' && !is_dir($logDir)) {
  @mkdir($logDir, 0775, true);
}
function leave_email_log(string $message, string $logFile): void {
  if ($logFile === '') return;
  $stamp = date('Y-m-d H:i:s');
  @error_log("[$stamp] $message\n", 3, $logFile);
}

$sharedKey = getSettingValue($conn, 'api.shared_key');
$incoming  = $_SERVER['HTTP_X_API_KEY'] ?? '';
if (!$sharedKey || !hash_equals(trim($sharedKey), trim($incoming))) {
  http_response_code(401);
  leave_email_log('unauthorized request', $logFile);
  echo json_encode(['ok'=>false,'error'=>'Unauthorized']);
  exit;
}

$body = file_get_contents('php://input');
$payload = $body ? json_decode($body, true) : [];
$leaveId = (int)($payload['leave_id'] ?? ($_POST['leave_id'] ?? 0));
$sourceRaw = (string)($payload['source'] ?? ($_POST['source'] ?? ''));
$source = strtolower(trim($sourceRaw));
if (!in_array($source, ['driver', 'employee'], true)) {
  $source = 'employee';
}
$isDriverRequest = ($source === 'driver');
if ($leaveId <= 0) {
  http_response_code(400);
  leave_email_log('leave_id missing', $logFile);
  echo json_encode(['ok'=>false,'error'=>'leave_id required']);
  exit;
}

$stmt = $conn->prepare("
  SELECT
    lr.*,
    d.name AS driver_name,
    d.empid AS driver_empid,
    COALESCE(p.plant_name,'Unassigned') AS plant_name,
    u.full_name AS requested_by_name,
    u.username AS requested_by_username
  FROM leave_requests lr
  JOIN drivers d ON d.id = lr.driver_id
  LEFT JOIN plants p ON p.id = d.plant_id
  LEFT JOIN users u ON u.id = lr.requested_by_id
  WHERE lr.id = ?
  LIMIT 1
");
$stmt->bind_param("i", $leaveId);
$stmt->execute();
$row = $stmt->get_result()->fetch_assoc();
$stmt->close();

if (!$row) {
  http_response_code(404);
  leave_email_log("leave_id={$leaveId} not found", $logFile);
  echo json_encode(['ok'=>false,'error'=>'Leave request not found']);
  exit;
}

$toList = ['vikassachan@sstranswaysindia.com', 'neerajsachan1990@gmail.com'];
$fromEmail = getSettingValue($conn,'from_email') ?: getSettingValue($conn,'system_email') ?: 'do-not-reply@sstranswaysindia.com';
$fromName  = 'Leave Notifier';

$smtpHost   = getSettingValue($conn,'smtp_host')   ?: 'smtp.hostinger.com';
$smtpPort   = (int)(getSettingValue($conn,'smtp_port') ?: 465);
$smtpSecure = getSettingValue($conn,'smtp_secure') ?: 'ssl';
$smtpUser   = getSettingValue($conn,'smtp_user')   ?: $fromEmail;
$smtpPass   = getSettingValue($conn,'smtp_pass')   ?: '';

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

$requester = $row['requested_by_name'] ?: $row['requested_by_username'] ?: 'User';
$dateRange = $row['leave_start_date'] . ' to ' . $row['leave_end_date'];
$driverName = trim((string)$row['driver_name']);
$driverName = preg_replace('/[^\x20-\x7E]/', '', $driverName);
$subjectPrefix = $isDriverRequest ? '[Driver Leave Request]' : '[Leave Request]';
$subject = $subjectPrefix . ' ' . $driverName . ' • ' . $dateRange;

$headerTitle = $isDriverRequest ? 'Driver Leave Request' : 'Leave Request Notification';
$introLine = $isDriverRequest
  ? 'Driver submitted leave request (mobile app)'
  : 'New Leave Request Submitted';

$requesterLabel = $isDriverRequest ? 'Request Source' : 'Requested By';
$requesterValue = $isDriverRequest ? 'Driver App' : $requester;
$approvalUrl = $isDriverRequest
  ? 'https://sstranswaysindia.com/DriverDocs/leave_dashboard.php?tab=drivers'
  : 'https://sstranswaysindia.com/DriverDocs/leave_dashboard.php?tab=approval';

$html = '<div style="background:#0b2a5b;color:#ffffff;padding:12px 16px;font-weight:700;border-radius:6px 6px 0 0;">' . $headerTitle . '</div>'
  . '<div style="border:1px solid #e3e8ef;border-top:0;border-radius:0 0 6px 6px;padding:14px;">'
  . '<div style="font-weight:600;margin-bottom:10px;">' . $introLine . '</div>'
  . '<table cellpadding="0" cellspacing="0" border="0" style="width:100%;border-collapse:collapse;font-size:14px;">'
  . '<tr><th style="text-align:left;border:1px solid #e3e8ef;padding:8px;background:#f2f4f7;width:32%;">Employee</th><td style="border:1px solid #e3e8ef;padding:8px;">' . htmlspecialchars($driverName) . '</td></tr>'
  . '<tr><th style="text-align:left;border:1px solid #e3e8ef;padding:8px;background:#f2f4f7;">EmpID</th><td style="border:1px solid #e3e8ef;padding:8px;">' . htmlspecialchars((string)$row['driver_empid']) . '</td></tr>'
  . '<tr><th style="text-align:left;border:1px solid #e3e8ef;padding:8px;background:#f2f4f7;">Plant</th><td style="border:1px solid #e3e8ef;padding:8px;">' . htmlspecialchars((string)$row['plant_name']) . '</td></tr>'
  . '<tr><th style="text-align:left;border:1px solid #e3e8ef;padding:8px;background:#f2f4f7;">Leave Type</th><td style="border:1px solid #e3e8ef;padding:8px;">' . htmlspecialchars((string)$row['leave_type']) . '</td></tr>'
  . '<tr><th style="text-align:left;border:1px solid #e3e8ef;padding:8px;background:#f2f4f7;">Dates</th><td style="border:1px solid #e3e8ef;padding:8px;">' . htmlspecialchars($dateRange) . '</td></tr>'
  . '<tr><th style="text-align:left;border:1px solid #e3e8ef;padding:8px;background:#f2f4f7;">Days</th><td style="border:1px solid #e3e8ef;padding:8px;">' . htmlspecialchars((string)$row['total_days']) . '</td></tr>'
  . '<tr><th style="text-align:left;border:1px solid #e3e8ef;padding:8px;background:#f2f4f7;">Reason</th><td style="border:1px solid #e3e8ef;padding:8px;">' . htmlspecialchars((string)$row['reason']) . '</td></tr>'
  . '<tr><th style="text-align:left;border:1px solid #e3e8ef;padding:8px;background:#f2f4f7;">Status</th><td style="border:1px solid #e3e8ef;padding:8px;">' . htmlspecialchars((string)$row['status']) . '</td></tr>'
  . '<tr><th style="text-align:left;border:1px solid #e3e8ef;padding:8px;background:#f2f4f7;">' . htmlspecialchars($requesterLabel) . '</th><td style="border:1px solid #e3e8ef;padding:8px;">' . htmlspecialchars($requesterValue) . '</td></tr>'
  . '</table>'
  . '<div style="margin-top:12px;"><a href="' . htmlspecialchars($approvalUrl) . '" style="background:#1f6f44;color:#ffffff;text-decoration:none;padding:10px 14px;border-radius:6px;display:inline-block;">Open Approval Dashboard</a></div>'
  . '<div style="margin-top:12px;">Thanks and Regards,<br>Leave Management System<br>SS Transways India</div>'
  . '</div>';

$plainIntro = $isDriverRequest ? 'Driver submitted leave request (mobile app)' : 'New Leave Request Submitted';
$plain = $plainIntro . "\n"
  . "Employee: {$driverName}\n"
  . "EmpID: {$row['driver_empid']}\n"
  . "Plant: {$row['plant_name']}\n"
  . "Leave Type: {$row['leave_type']}\n"
  . "Dates: {$dateRange}\n"
  . "Days: {$row['total_days']}\n"
  . "Reason: {$row['reason']}\n"
  . "Status: {$row['status']}\n"
  . "{$requesterLabel}: {$requesterValue}\n\n"
  . "Approval Link: {$approvalUrl}\n\n"
  . "Thanks and Regards,\n"
  . "Leave Management System\n"
  . "SS Transways India\n";

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
  foreach ($toList as $addr) $mail->addAddress($addr);
  $mail->CharSet = 'UTF-8';
  $mail->isHTML(true);
  $mail->Subject = $subject;
  $mail->Body    = $html;
  $mail->AltBody = $plain;
  $mail->send();
} catch (Exception $e) {
  http_response_code(500);
  leave_email_log("leave_id={$leaveId} mailer error=" . $mail->ErrorInfo, $logFile);
  echo json_encode(['ok'=>false,'type'=>'mailer','error'=>$mail->ErrorInfo]);
  exit;
}

leave_email_log("leave_id={$leaveId} sent to=" . implode(',', $toList), $logFile);
echo json_encode(['ok'=>true,'sent'=>true,'leave_id'=>$leaveId]);
