<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/common.php';

apiEnsurePost();

$data = apiRequireJson();
$driverId = apiSanitizeInt($data['driverId'] ?? null);
$type = trim($data['type'] ?? '');
$amount = apiSanitizeFloat($data['amount'] ?? null);
$description = trim($data['description'] ?? '');
$timestamp = trim($data['timestamp'] ?? '');

if (!$driverId || !$type || !$amount) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId, type, and amount are required']);
}

if (!in_array($type, ['advance_received', 'expense'], true)) {
    apiRespond(400, ['status' => 'error', 'error' => 'type must be advance_received or expense']);
}

if ($amount <= 0) {
    apiRespond(400, ['status' => 'error', 'error' => 'amount must be positive']);
}

// Handle custom timestamp
$createdAt = 'NOW()';
if (!empty($timestamp)) {
    $timestampTime = strtotime($timestamp);
    if ($timestampTime !== false) {
        $createdAt = "'" . date('Y-m-d H:i:s', $timestampTime) . "'";
    }
}

try {
    // Insert transaction with custom timestamp
    $insertStmt = $conn->prepare("
        INSERT INTO advance_transactions (driver_id, type, amount, description, created_at)
        VALUES (?, ?, ?, ?, $createdAt)
    ");
    $insertStmt->bind_param('isds', $driverId, $type, $amount, $description);
    $insertStmt->execute();
    $transactionId = $insertStmt->insert_id;
    $insertStmt->close();

    // Get updated balance
    $balanceStmt = $conn->prepare("
        SELECT 
            COALESCE(SUM(CASE WHEN type = 'advance_received' THEN amount ELSE 0 END), 0) -
            COALESCE(SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END), 0) as balance
        FROM advance_transactions 
        WHERE driver_id = ?
    ");
    $balanceStmt->bind_param('i', $driverId);
    $balanceStmt->execute();
    $balance = $balanceStmt->get_result()->fetch_assoc()['balance'] ?? 0;
    $balanceStmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'transactionId' => (int)$transactionId,
        'balance' => (float)$balance,
        'message' => 'Transaction added successfully'
    ]);

} catch (Exception $e) {
    error_log("Error adding advance transaction: " . $e->getMessage());
    apiRespond(500, ['status' => 'error', 'error' => 'Failed to add transaction']);
}
?>
