<?php
/**
 * referral_code.php
 * Get or generate a unique referral code for a logged-in user.
 * POST body: { "user_id": "..." }
 * Returns:  { "status": "ok", "referral_code": "SSTXYZ123" }
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

// Check if user already has a code
$stmt = $conn->prepare('SELECT referral_code FROM users WHERE id = ?');
$stmt->bind_param('s', $userId);
$stmt->execute();
$result = $stmt->get_result();
$row = $result->fetch_assoc();
$stmt->close();

if (!$row) {
    apiRespond(404, ['status' => 'error', 'error' => 'User not found']);
}

$existingCode = $row['referral_code'] ?? null;

if (!$existingCode || trim($existingCode) === '') {
    // Generate unique code: SST + first 3 chars of userId + random 4 digits
    $code = 'SST' . strtoupper(substr(md5($userId . time()), 0, 3)) . rand(1000, 9999);

    // Save to users table
    $update = $conn->prepare('UPDATE users SET referral_code = ? WHERE id = ?');
    $update->bind_param('ss', $code, $userId);
    $update->execute();
    $update->close();

    $existingCode = $code;
}

apiRespond(200, [
    'status' => 'ok',
    'referral_code' => $existingCode,
]);
