<?php
/**
 * referral_upi.php
 * Save or Fetch UPI ID for a referral user.
 *
 * POST  { "user_id": "...", "action": "get" }
 *       → { "status":"ok", "upi_id": "..." }
 *
 * POST  { "user_id": "...", "action": "save", "upi_id": "abc@upi" }
 *       → { "status":"ok" }
 */
declare(strict_types=1);
require_once __DIR__ . '/common.php';

apiSendCorsHeaders();
apiEnsurePost();

$data = apiRequireJson();
$userId = trim((string) ($data['user_id'] ?? ''));
$action = trim((string) ($data['action'] ?? 'get'));

if ($userId === '') {
    apiRespond(400, ['status' => 'error', 'error' => 'user_id is required']);
}

if ($action === 'save') {
    $upiId = trim((string) ($data['upi_id'] ?? ''));
    if ($upiId === '') {
        apiRespond(400, ['status' => 'error', 'error' => 'UPI ID is required']);
    }
    $stmt = $conn->prepare("UPDATE users SET upi_id = ? WHERE id = ?");
    $stmt->bind_param('si', $upiId, $userId);
    $stmt->execute();
    $stmt->close();
    apiRespond(200, ['status' => 'ok']);
} else {
    $stmt = $conn->prepare("SELECT upi_id FROM users WHERE id = ?");
    $stmt->bind_param('i', $userId);
    $stmt->execute();
    $result = $stmt->get_result();
    $row = $result->fetch_assoc();
    $stmt->close();
    apiRespond(200, [
        'status' => 'ok',
        'upi_id' => (string) ($row['upi_id'] ?? ''),
    ]);
}
