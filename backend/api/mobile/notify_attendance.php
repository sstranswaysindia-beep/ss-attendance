<?php
header('Content-Type: application/json');

/* ---------- Error handling as JSON ---------- */
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
$conn->set_charset('utf8mb4');

/* ---------- Auth (Apps Script header, same key) ---------- */
$sharedKey = getSettingValue($conn, 'api.shared_key');
$incoming  = $_SERVER['HTTP_X_API_KEY'] ?? '';
if (!$sharedKey || !hash_equals(trim($sharedKey), trim($incoming))) {
  http_response_code(401);
  echo json_encode(['ok'=>false,'error'=>'Unauthorized']);
  exit;
}

/* ---------- Inputs ---------- */
$preview    = isset($_GET['preview']) && $_GET['preview'] == '1';
$scope      = $_GET['scope'] ?? 'both';          // drivers|helpers|both (applies to checkout in auto mode)
$plantId    = isset($_GET['plant_id']) ? (int)$_GET['plant_id'] : null;
$requireGeo = isset($_GET['require_geo']) && $_GET['require_geo'] == '1'; // only users.geofencing_enable='Y'
$forceSend  = isset($_GET['force']) && $_GET['force'] == '1';              // ignore dedupe
$mode       = $_GET['mode'] ?? 'auto';             // auto | checkin | checkout
$cutoff     = $_GET['cutoff'] ?? '12:00';          // HH:MM (Asia/Kolkata)
$cooldown   = isset($_GET['cooldown']) ? max(0, (int)$_GET['cooldown']) : 4; // hours; 0 disables dedupe

$tz = new DateTimeZone('Asia/Kolkata');
$dt = new DateTime('now', $tz);
if (!empty($_GET['date'])) {
  $try = DateTime::createFromFormat('Y-m-d', $_GET['date'], $tz);
  if ($try instanceof DateTime) $dt = $try;
}
$ymd = $dt->format('Y-m-d');

/* decide effective mode based on time if auto */
$effectiveMode = $mode;
if ($mode === 'auto') {
  $cut = DateTime::createFromFormat('H:i', $cutoff, $tz);
  if (!$cut) { $cut = DateTime::createFromFormat('H:i', '12:00', $tz); }
  $cutoffDt = new DateTime($ymd . ' ' . $cut->format('H:i') . ':00', $tz);
  $effectiveMode = ($dt < $cutoffDt) ? 'checkin' : 'checkout';
}

/* compute dedupe threshold */
$minCreatedAt = null;
if ($cooldown > 0) {
  $tmp = clone $dt;
  $tmp->modify("-{$cooldown} hour");
  $minCreatedAt = $tmp->format('Y-m-d H:i:s');
}

/* ---------- Role filters ---------- */
/* Checkout (default): drivers/helpers (respects ?scope=) */
$rolesCheckout = ['driver','helper'];
if ($scope === 'drivers') { $rolesCheckout = ['driver']; }
elseif ($scope === 'helpers') { $rolesCheckout = ['helper']; }

/* Check-in: ALL roles */
$rolesCheckin = ['admin','supervisor','driver','helper','other'];

/* ---------- Query helpers ---------- */
function esc_list(mysqli $conn, array $arr): string {
  return "'" . implode("','", array_map([$conn,'real_escape_string'], $arr)) . "'";
}

function map_recipient_type(string $role): string {
  $r = strtolower($role);
  if ($r === 'admin') return 'admin';
  if ($r === 'supervisor') return 'supervisor';
  if ($r === 'driver') return 'driver';
  if ($r === 'helper') return 'driver';     // enum doesn’t include helper
  return 'broadcast';
}

/* ---------- Fetch users for checkout pipeline ---------- */
$usersCheckout = [];
if ($effectiveMode === 'checkout') {
  $roleList = esc_list($conn, $rolesCheckout);
  $sql = "
    SELECT u.id AS user_id, u.role, u.username, u.phone, u.view_document, 
           ".($requireGeo ? "u.geofencing_enable," : "NULL AS geofencing_enable,")."
           d.id AS driver_id, d.name, d.plant_id
    FROM users u
    LEFT JOIN drivers d ON d.id = u.driver_id
    WHERE u.role IN ($roleList)
  ";
  if ($plantId) $sql .= " AND d.plant_id = " . (int)$plantId;
  if ($requireGeo) $sql .= " AND u.geofencing_enable = 'Y'";
  $res = $conn->query($sql);
  while ($row = $res->fetch_assoc()) $usersCheckout[] = $row;
}

/* ---------- Fetch users for checkin pipeline ---------- */
$usersCheckin = [];
if ($effectiveMode === 'checkin') {
  $roleList = esc_list($conn, $rolesCheckin);
  $sql = "
    SELECT u.id AS user_id, u.role, u.username, u.phone, u.view_document, 
           ".($requireGeo ? "u.geofencing_enable," : "NULL AS geofencing_enable,")."
           d.id AS driver_id, d.name, d.plant_id
    FROM users u
    LEFT JOIN drivers d ON d.id = u.driver_id
    WHERE u.role IN ($roleList)
  ";
  if ($plantId) $sql .= " AND (d.plant_id = " . (int)$plantId . " OR d.plant_id IS NULL)";
  if ($requireGeo) $sql .= " AND u.geofencing_enable = 'Y'";
  $res = $conn->query($sql);
  while ($row = $res->fetch_assoc()) $usersCheckin[] = $row;
}

/* ---------- Attendance map for those linked to drivers ---------- */
function build_attendance_map(mysqli $conn, array $driverIds, string $ymd): array {
  $map = [];
  if (!$driverIds) return $map;
  $in = implode(',', array_map('intval', $driverIds));
  $sql = "
    SELECT driver_id,
           MAX(CASE WHEN DATE(in_time) = '{$ymd}' THEN 1 ELSE 0 END) AS has_in,
           MAX(CASE WHEN DATE(in_time) = '{$ymd}' AND out_time IS NULL THEN 1 ELSE 0 END) AS has_open
    FROM attendance
    WHERE driver_id IN ($in)
    GROUP BY driver_id
  ";
  $ra = $conn->query($sql);
  while ($r = $ra->fetch_assoc()) {
    $map[(int)$r['driver_id']] = ['has_in'=>(int)$r['has_in']===1, 'has_open'=>(int)$r['has_open']===1];
  }
  return $map;
}

function unique_users_by_id(array $rows): array {
  $seen = [];
  $out = [];
  foreach ($rows as $row) {
    $uid = (int)($row['user_id'] ?? 0);
    if ($uid <= 0 || isset($seen[$uid])) continue;
    $seen[$uid] = true;
    $out[] = $row;
  }
  return $out;
}

/* ---------- Build target lists ---------- */
$toCheckin  = [];
$toCheckout = [];

if ($effectiveMode === 'checkout') {
  $driverIds = array_values(array_filter(array_map(function($r){ return (int)($r['driver_id'] ?? 0); }, $usersCheckout)));
  $att = build_attendance_map($conn, $driverIds, $ymd);
  foreach ($usersCheckout as $u) {
    $did = (int)($u['driver_id'] ?? 0);
    if (!$did) continue; // checkout requires a driver link
    $st = $att[$did] ?? ['has_in'=>false,'has_open'=>false];
    if ($st['has_in'] && $st['has_open']) $toCheckout[] = $u;
  }
}

if ($effectiveMode === 'checkin') {
  $driverIds = array_values(array_filter(array_map(function($r){ return (int)($r['driver_id'] ?? 0); }, $usersCheckin)));
  $att = build_attendance_map($conn, $driverIds, $ymd);
  foreach ($usersCheckin as $u) {
    $did = (int)($u['driver_id'] ?? 0);
    if ($did > 0) {
      $st = $att[$did] ?? ['has_in'=>false,'has_open'=>false];
      if (!$st['has_in']) $toCheckin[] = $u;
    }
  }
}

$toCheckin = unique_users_by_id($toCheckin);
$toCheckout = unique_users_by_id($toCheckout);

/* ---------- Messages (English + Hindi) ---------- */
$titleIn  = "Attendance Reminder: Check-In Pending";
$bodyIn   = "You haven't checked in today. Please open the app and check in at your plant. | आपने आज अभी तक चेक-इन नहीं किया है। कृपया ऐप खोलकर प्लांट पर चेक-इन करें।";

$titleOut = "Attendance Reminder: Check-Out Pending";
$bodyOut  = "Your attendance is still open. Please complete your check-out. | आपकी अटेंडेंस अभी खुली है। कृपया चेक-आउट पूरा करें।";

/* ---------- Helpers: DB insert + push ---------- */
function insert_notification(mysqli $conn, string $recipientType, int $userId, string $title, string $body, ?int $linkRefId=null): int {
  $rt = in_array($recipientType, ['driver','supervisor','admin','broadcast'], true) ? $recipientType : 'broadcast';
  $titleEsc = $conn->real_escape_string($title);
  $bodyEsc  = $conn->real_escape_string($body);
  $linkRef  = $linkRefId ? (int)$linkRefId : 'NULL';
  $sql = "
    INSERT INTO notifications (recipient_type, recipient_id, title, body, link_type, link_ref_id, created_at)
    VALUES ('{$rt}', {$userId}, '{$titleEsc}', '{$bodyEsc}', 'attendance', {$linkRef}, NOW())
  ";
  $ok = $conn->query($sql);
  return $ok ? (int)$conn->insert_id : 0;
}

function already_sent_in_cooldown(mysqli $conn, int $userId, string $title, ?string $minCreatedAt): bool {
  if ($minCreatedAt === null) return false; // cooldown disabled
  $sql = "
    SELECT 1
    FROM notifications
    WHERE recipient_id = ?
      AND link_type = 'attendance'
      AND created_at >= ?
      AND title = ?
    LIMIT 1
  ";
  $stmt = $conn->prepare($sql);
  $stmt->bind_param('iss', $userId, $minCreatedAt, $title);
  $stmt->execute();
  $stmt->store_result();
  $exists = $stmt->num_rows > 0;
  $stmt->close();
  return $exists;
}

function try_push_user_via_curl(int $userId, string $title, string $body, array $data=[]): bool {
  $endpoint = 'https://sstranswaysindia.com/api/mobile/send_push_notification_v1.php';
  $payload = json_encode([
    'userId' => (string)$userId,
    'title'  => $title,
    'body'   => $body,
    'data'   => $data,
  ], JSON_UNESCAPED_UNICODE);

  $ch = curl_init($endpoint);
  curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST           => true,
    CURLOPT_HTTPHEADER     => ['Content-Type: application/json'],
    CURLOPT_POSTFIELDS     => $payload,
    CURLOPT_TIMEOUT        => 10,
  ]);
  $resp = curl_exec($ch);
  $http = curl_getinfo($ch, CURLINFO_HTTP_CODE);
  curl_close($ch);

  if ($resp === false) return false;
  return ($http >= 200 && $http < 300);
}

/* ---------- Preview ---------- */
if ($preview) {
  echo json_encode([
    'ok'=>true,
    'preview'=>true,
    'date'=>$ymd,
    'mode'=>$mode,
    'effective_mode'=>$effectiveMode,
    'cutoff'=>$cutoff,
    'cooldown_hours'=>$cooldown,
    'scope'=>$scope,
    'plant_id'=>$plantId,
    'require_geo'=>$requireGeo,
    'to_checkin'=>($effectiveMode==='checkin') ? count($toCheckin) : 0,
    'to_checkout'=>($effectiveMode==='checkout') ? count($toCheckout) : 0
  ]);
  exit;
}

/* ---------- Send + Log (cooldown dedupe unless force=1) ---------- */
$sent = ['checkin'=>0, 'checkout'=>0];
$inserted = 0;
$skipped_dup = ['checkin'=>0, 'checkout'=>0];
$sent_by_role = ['admin'=>0,'supervisor'=>0,'driver'=>0,'helper'=>0,'other'=>0,'broadcast'=>0];

if ($effectiveMode === 'checkin') {
  foreach ($toCheckin as $u) {
    $uid = (int)$u['user_id'];
    if ($uid <= 0) continue;
    if (!$forceSend && already_sent_in_cooldown($conn, $uid, $titleIn, $minCreatedAt)) { $skipped_dup['checkin']++; continue; }
    $rtype = map_recipient_type((string)$u['role']);
    $nid = insert_notification($conn, $rtype, $uid, $titleIn, $bodyIn, null);
    if ($nid > 0) $inserted++;
    if (try_push_user_via_curl($uid, $titleIn, $bodyIn, ['type'=>'attendance','action'=>'checkin_pending','date'=>$ymd])) {
      $sent['checkin']++;
      if (isset($sent_by_role[$u['role']])) $sent_by_role[$u['role']]++; else $sent_by_role['broadcast']++;
    }
  }
}

if ($effectiveMode === 'checkout') {
  foreach ($toCheckout as $u) {
    $uid = (int)$u['user_id'];
    if ($uid <= 0) continue;
    if (!$forceSend && already_sent_in_cooldown($conn, $uid, $titleOut, $minCreatedAt)) { $skipped_dup['checkout']++; continue; }
    $rtype = map_recipient_type((string)$u['role']);
    $nid = insert_notification($conn, $rtype, $uid, $titleOut, $bodyOut, null);
    if ($nid > 0) $inserted++;
    if (try_push_user_via_curl($uid, $titleOut, $bodyOut, ['type'=>'attendance','action'=>'checkout_pending','date'=>$ymd])) {
      $sent['checkout']++;
      if (isset($sent_by_role[$u['role']])) $sent_by_role[$u['role']]++; else $sent_by_role['broadcast']++;
    }
  }
}

/* ---------- Done ---------- */
echo json_encode([
  'ok'=>true,
  'date'=>$ymd,
  'mode'=>$mode,
  'effective_mode'=>$effectiveMode,
  'cutoff'=>$cutoff,
  'cooldown_hours'=>$cooldown,
  'scope'=>$scope,
  'plant_id'=>$plantId,
  'require_geo'=>$requireGeo,
  'sent'=>$sent,
  'inserted_rows'=>$inserted,
  'skipped_duplicates'=>$skipped_dup,
  'to_checkin'=>($effectiveMode==='checkin') ? count($toCheckin) : 0,
  'to_checkout'=>($effectiveMode==='checkout') ? count($toCheckout) : 0,
  'sent_by_role'=>$sent_by_role
]);
