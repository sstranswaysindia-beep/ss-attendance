<?php
/**
 * referral_profile_submit.php
 * Submit profile details for a referred user (name, mobile, Aadhar, DL, photos).
 * Accepts multipart form data with optional file uploads.
 *
 * Fields: user_id, name, mobile, type (driver/helper), aadhar_no, dl_no
 * Files:  aadhar_photo, dl_photo
 *
 * Returns: { "status": "ok" }
 */
declare(strict_types=1);
require_once __DIR__ . '/common.php';

apiSendCorsHeaders();
apiEnsurePost();

// For multipart, read from $_POST
$userId = trim((string) ($_POST['user_id'] ?? ''));
$name = trim((string) ($_POST['name'] ?? ''));
$mobile = trim((string) ($_POST['mobile'] ?? ''));
$type = strtolower(trim((string) ($_POST['type'] ?? 'driver')));
$aadharNo = trim((string) ($_POST['aadhar_no'] ?? ''));
$dlNo = trim((string) ($_POST['dl_no'] ?? ''));

if ($userId === '' || $name === '' || $mobile === '') {
    apiRespond(400, [
        'status' => 'error',
        'error' => 'user_id, name, and mobile are required',
    ]);
}

if (!in_array($type, ['driver', 'helper'], true)) {
    $type = 'driver';
}

// Resolve username for filename pattern
$username = '';
$userStmt = $conn->prepare('SELECT username FROM users WHERE id = ? LIMIT 1');
if ($userStmt) {
    $userStmt->bind_param('s', $userId);
    $userStmt->execute();
    $userRow = $userStmt->get_result()->fetch_assoc();
    $username = trim((string)($userRow['username'] ?? ''));
    $userStmt->close();
}
if ($username === '') {
    $username = 'user_' . $userId;
}
$safeUsername = preg_replace('/[^a-zA-Z0-9_]+/', '_', strtolower($username)) ?: ('user_' . $userId);
$timestampToken = date('Ymd_His');

// ── Handle file uploads ──────────────────────────────────────────────────
$uploadBase = realpath(__DIR__ . '/../../../public_html/uploads/referral');
if ($uploadBase === false) {
    $uploadBase = __DIR__ . '/../../../public_html/uploads/referral';
}
$referralDir = rtrim($uploadBase, '/\\') . '/' . $userId;

if (!is_dir($referralDir)) {
    @mkdir($referralDir, 0755, true);
}

$aadharPhotoUrl = null;
if (!empty($_FILES['aadhar_photo']) && $_FILES['aadhar_photo']['error'] === UPLOAD_ERR_OK) {
    $extRaw = strtolower((string)(pathinfo($_FILES['aadhar_photo']['name'], PATHINFO_EXTENSION) ?: 'jpg'));
    $ext = preg_replace('/[^a-z0-9]/', '', $extRaw) ?: 'jpg';
    $filename = 'aadhar_' . $safeUsername . '_' . $timestampToken . '.' . $ext;
    $targetPath = $referralDir . '/' . $filename;
    if (move_uploaded_file($_FILES['aadhar_photo']['tmp_name'], $targetPath)) {
        $aadharPhotoUrl = '/uploads/referral/' . $userId . '/' . $filename;
    }
}

$dlPhotoUrl = null;
if (!empty($_FILES['dl_photo']) && $_FILES['dl_photo']['error'] === UPLOAD_ERR_OK) {
    $extRaw = strtolower((string)(pathinfo($_FILES['dl_photo']['name'], PATHINFO_EXTENSION) ?: 'jpg'));
    $ext = preg_replace('/[^a-z0-9]/', '', $extRaw) ?: 'jpg';
    $filename = 'dl_' . $safeUsername . '_' . $timestampToken . '.' . $ext;
    $targetPath = $referralDir . '/' . $filename;
    if (move_uploaded_file($_FILES['dl_photo']['tmp_name'], $targetPath)) {
        $dlPhotoUrl = '/uploads/referral/' . $userId . '/' . $filename;
    }
}

// ── Update the referral record ───────────────────────────────────────────
$amount = ($type === 'driver') ? 50.00 : 30.00;
$now = date('Y-m-d H:i:s');

$updateStmt = $conn->prepare(
    'UPDATE user_referrals SET 
        referred_name   = ?,
        referred_mobile = ?,
        referred_type   = ?,
        aadhar_no       = ?,
        dl_no           = ?,
        aadhar_photo_url = ?,
        dl_photo_url    = ?,
        amount          = ?,
        profile_submitted_at = ?
     WHERE referred_user_id = ?'
);

$updateStmt->bind_param(
    'sssssssdss',
    $name,
    $mobile,
    $type,
    $aadharNo,
    $dlNo,
    $aadharPhotoUrl,
    $dlPhotoUrl,
    $amount,
    $now,
    $userId
);

if (!$updateStmt->execute()) {
    apiRespond(500, ['status' => 'error', 'error' => 'Failed to update profile: ' . $conn->error]);
}
$updateStmt->close();

// ── Also update user's full_name in users table ──────────────────────────
$nameStmt = $conn->prepare('UPDATE users SET full_name = ? WHERE id = ?');
$nameStmt->bind_param('si', $name, $userId);
$nameStmt->execute();
$nameStmt->close();

apiRespond(200, [
    'status' => 'ok',
    'message' => 'Profile submitted for verification',
]);
