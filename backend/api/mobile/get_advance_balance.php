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

if (!$driverId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId is required']);
}

try {
    // Get current advance balance
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
        'balance' => (float)$balance,
        'currency' => 'INR',
        'driverId' => (int)$driverId
    ]);

} catch (Exception $e) {
    error_log("Error getting advance balance: " . $e->getMessage());
    apiRespond(500, ['status' => 'error', 'error' => 'Failed to get advance balance']);
}
?>
