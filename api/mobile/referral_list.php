<?php
/**
 * referral_list.php
 * Fetch all referrals belonging to a given user (referrer).
 * POST body: { "user_id": "..." }
 * Returns:  { "status": "ok", "referrals": [ ... ] }
 */
declare(strict_types=1);
require_once __DIR__ . '/common.php';

apiSendCorsHeaders();
apiEnsurePost();

$data = apiRequireJson();
$userId = trim((string) ($data['user_id'] ?? ''));

if ($userId === '') {
    apiRespond(400, ['status' => 'error', 'error' => 'user_id is required']);
}

$stmt = $conn->prepare(
    'SELECT 
        id,
        referrer_user_id,
        referral_code,
        referred_user_id,
        referred_username,
        referred_name,
        referred_mobile,
        referred_type,
        aadhar_no,
        dl_no,
        aadhar_photo_url,
        dl_photo_url,
        status,
        amount,
        created_at,
        verified_at
     FROM user_referrals 
     WHERE referrer_user_id = ? 
     ORDER BY created_at DESC'
);
$stmt->bind_param('s', $userId);
$stmt->execute();
$result = $stmt->get_result();

$referrals = [];
while ($row = $result->fetch_assoc()) {
    // Build full URL for photos
    if (!empty($row['aadhar_photo_url'])) {
        $row['aadhar_photo_url'] = 'https://sstranswaysindia.com' . $row['aadhar_photo_url'];
    }
    if (!empty($row['dl_photo_url'])) {
        $row['dl_photo_url'] = 'https://sstranswaysindia.com' . $row['dl_photo_url'];
    }

    $referrals[] = [
        'id' => (string) $row['id'],
        'referrer_user_id' => (string) $row['referrer_user_id'],
        'referral_code' => (string) $row['referral_code'],
        'referred_name' => (string) ($row['referred_name'] ?? $row['referred_username'] ?? 'Unknown'),
        'referred_mobile' => (string) ($row['referred_mobile'] ?? ''),
        'referred_type' => (string) ($row['referred_type'] ?? 'driver'),
        'aadhar_no' => $row['aadhar_no'],
        'dl_no' => $row['dl_no'],
        'aadhar_photo_url' => $row['aadhar_photo_url'],
        'dl_photo_url' => $row['dl_photo_url'],
        'status' => (string) ($row['status'] ?? 'pending'),
        'amount' => (float) ($row['amount'] ?? 0),
        'created_at' => (string) ($row['created_at'] ?? ''),
        'verified_at' => $row['verified_at'],
    ];
}
$stmt->close();

apiRespond(200, [
    'status' => 'ok',
    'referrals' => $referrals,
    'total' => count($referrals),
]);
