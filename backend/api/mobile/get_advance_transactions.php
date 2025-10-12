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
$limit = apiSanitizeInt($data['limit'] ?? 50);

if (!$driverId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId is required']);
}

try {
    // Get transactions with running balance
    $transactionsStmt = $conn->prepare("
        SELECT 
            id,
            type,
            amount,
            description,
            created_at,
            (
                SELECT COALESCE(SUM(
                    CASE WHEN type = 'advance_received' THEN amount ELSE 0 END -
                    CASE WHEN type = 'expense' THEN amount ELSE 0 END
                ), 0)
                FROM advance_transactions t2 
                WHERE t2.driver_id = t1.driver_id 
                AND t2.created_at <= t1.created_at
            ) as running_balance
        FROM advance_transactions t1
        WHERE driver_id = ?
        ORDER BY created_at DESC
        LIMIT ?
    ");
    $transactionsStmt->bind_param('ii', $driverId, $limit);
    $transactionsStmt->execute();
    $transactions = $transactionsStmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $transactionsStmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'transactions' => $transactions,
        'driverId' => (int)$driverId,
        'count' => count($transactions)
    ]);

} catch (Exception $e) {
    error_log("Error getting advance transactions: " . $e->getMessage());
    apiRespond(500, ['status' => 'error', 'error' => 'Failed to get transactions']);
}
?>