<?php
/**
 * referral_withdraw.php
 * Request withdrawal of referral earnings.
 *
 * POST  { "user_id": "...", "amount": 500, "upi_id": "abc@upi" }
 *       → { "status":"ok", "withdrawal_id": 123 }
 */
declare(strict_types=1);
require_once __DIR__ . '/common.php';

apiSendCorsHeaders();
apiEnsurePost();

$data = apiRequireJson();
$userId = trim((string) ($data['user_id'] ?? ''));
$amount = (float) ($data['amount'] ?? 0);
$upiId = trim((string) ($data['upi_id'] ?? ''));

if ($userId === '') {
    apiRespond(400, ['status' => 'error', 'error' => 'user_id is required']);
}
if ($amount < 500) {
    apiRespond(400, ['status' => 'error', 'error' => 'Minimum withdrawal amount is ₹500']);
}
if ($upiId === '') {
    apiRespond(400, ['status' => 'error', 'error' => 'UPI ID is required for withdrawal']);
}

// Verify user has enough verified earnings
$stmt = $conn->prepare(
    "SELECT COALESCE(SUM(amount), 0) as total_earnings
     FROM user_referrals
     WHERE referrer_user_id = ? AND status = 'verified'"
);
$stmt->bind_param('i', $userId);
$stmt->execute();
$result = $stmt->get_result();
$row = $result->fetch_assoc();
$totalEarnings = (float) ($row['total_earnings'] ?? 0);
$stmt->close();

// Get already withdrawn (pending + approved)
$stmt2 = $conn->prepare(
    "SELECT COALESCE(SUM(amount), 0) as withdrawn
     FROM referral_withdrawals
     WHERE user_id = ? AND status IN ('pending', 'approved')"
);
$stmt2->bind_param('i', $userId);
$stmt2->execute();
$result2 = $stmt2->get_result();
$row2 = $result2->fetch_assoc();
$withdrawn = (float) ($row2['withdrawn'] ?? 0);
$stmt2->close();

$available = $totalEarnings - $withdrawn;
if ($amount > $available) {
    apiRespond(400, [
        'status' => 'error',
        'error' => "Insufficient balance. Available: ₹" . number_format($available, 0),
    ]);
}

// Insert withdrawal request
$stmt3 = $conn->prepare(
    "INSERT INTO referral_withdrawals (user_id, amount, upi_id) VALUES (?, ?, ?)"
);
$stmt3->bind_param('ids', $userId, $amount, $upiId);
$stmt3->execute();
$withdrawalId = $stmt3->insert_id;
$stmt3->close();

apiRespond(200, [
    'status' => 'ok',
    'withdrawal_id' => $withdrawalId,
]);
