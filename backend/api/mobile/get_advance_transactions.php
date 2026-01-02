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
$limitRaw = apiSanitizeInt($data['limit'] ?? null);
$limit = ($limitRaw !== null && $limitRaw > 0 && $limitRaw <= 20000) ? $limitRaw : 5000;

if (!$driverId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId is required']);
}

if (!function_exists('column_exists')) {
    function column_exists(mysqli $db, string $table, string $column): bool
    {
        $tableEsc = $db->real_escape_string($table);
        $columnEsc = $db->real_escape_string($column);
        $sql = "SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = '{$tableEsc}'
                  AND COLUMN_NAME = '{$columnEsc}'
                LIMIT 1";
        $res = $db->query($sql);
        $exists = $res && $res->num_rows > 0;
        if ($res instanceof mysqli_result) {
            $res->free();
        }
        return $exists;
    }
}

try {
    $extraSelect = [];
    if (column_exists($conn, 'advance_transactions', 'vehicle_id')) {
        $extraSelect[] = 'vehicle_id';
    }
    if (column_exists($conn, 'advance_transactions', 'vehicle_plant_id')) {
        $extraSelect[] = 'vehicle_plant_id';
    }
    if (column_exists($conn, 'advance_transactions', 'counterparty_driver_id')) {
        $extraSelect[] = 'counterparty_driver_id';
    }
    if (column_exists($conn, 'advance_transactions', 'counterparty_plant_id')) {
        $extraSelect[] = 'counterparty_plant_id';
    }
    if (column_exists($conn, 'advance_transactions', 'category')) {
        $extraSelect[] = 'category';
    }

    $extraSql = '';
    if (!empty($extraSelect)) {
        $extraSql = ",\n            " . implode(",\n            ", $extraSelect);
    }

    // Get transactions with running balance
    $transactionsStmt = $conn->prepare("
        SELECT
            id,
            driver_id,
            type,
            amount,
            description,
            receipt_path,
            created_at{$extraSql},
            (
                SELECT COALESCE(SUM(
                    CASE
                        WHEN t2.type = 'advance_received' THEN t2.amount
                        WHEN t2.type = 'expense' THEN -t2.amount
                        ELSE 0
                    END
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
