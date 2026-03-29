<?php
/**
 * referral_profile_status.php
 * Returns profile-submission state for a referral user.
 * POST body: { "user_id": "..." }
 */
declare(strict_types=1);
require_once __DIR__ . '/common.php';

apiSendCorsHeaders();
apiEnsurePost();

$data = apiRequireJson();
$userId = trim((string)($data['user_id'] ?? ''));

if ($userId === '') {
    apiRespond(400, ['status' => 'error', 'error' => 'user_id is required']);
}

$stmt = $conn->prepare(
    'SELECT
        u.id,
        u.username,
        u.full_name,
        u.role,
        u.referred_by,
        ur.id AS referral_entry_id,
        ur.referred_name,
        ur.referred_mobile,
        ur.referred_type,
        ur.aadhar_no,
        ur.dl_no,
        ur.amount,
        ur.profile_submitted_at,
        ur.created_at,
        ur.verified_at,
        ur.status AS referral_status
     FROM users u
     LEFT JOIN user_referrals ur ON ur.referred_user_id = u.id
     WHERE u.id = ?
     ORDER BY ur.id DESC
     LIMIT 1'
);
$stmt->bind_param('s', $userId);
$stmt->execute();
$row = $stmt->get_result()->fetch_assoc();
$stmt->close();

if (!$row) {
    apiRespond(404, ['status' => 'error', 'error' => 'User not found']);
}

$profileSubmitted = !empty($row['profile_submitted_at'])
    || (!empty($row['referred_name']) && !empty($row['referred_mobile']));

apiRespond(200, [
    'status' => 'ok',
    'is_referral_user' => !empty($row['referred_by']),
    'username' => $row['username'] ?? null,
    'full_name' => $row['full_name'] ?? null,
    'referred_name' => $row['referred_name'] ?? null,
    'referred_mobile' => $row['referred_mobile'] ?? null,
    'profile_submitted' => $profileSubmitted,
    'profile_submitted_at' => $row['profile_submitted_at'],
    'referred_type' => $row['referred_type'] ?? null,
    'aadhar_no' => $row['aadhar_no'] ?? null,
    'dl_no' => $row['dl_no'] ?? null,
    'amount' => isset($row['amount']) ? (float)$row['amount'] : null,
    'referral_created_at' => $row['created_at'] ?? null,
    'verified_at' => $row['verified_at'] ?? null,
    'referral_status' => $row['referral_status'] ?? null,
]);
