<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/common.php';

apiEnsurePost();

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

$data = apiRequireJson();
$transactionId = apiSanitizeInt($data['transactionId'] ?? null);

if (!$transactionId) {
    apiRespond(400, ['status' => 'error', 'error' => 'Transaction ID is required']);
}

try {
    // Start transaction
    $conn->autocommit(false);
    
    try {
        // First, get the transaction details to check if it exists and get the driver_id
        $hasCpDriverCol = column_exists($conn, 'advance_transactions', 'counterparty_driver_id');
        $hasCpPlantCol = column_exists($conn, 'advance_transactions', 'counterparty_plant_id');
        $extraCols = [];
        if ($hasCpDriverCol) $extraCols[] = 'counterparty_driver_id';
        if ($hasCpPlantCol) $extraCols[] = 'counterparty_plant_id';
        $extraSql = $extraCols ? (', ' . implode(', ', $extraCols)) : '';

        $getSql = "SELECT id, driver_id, type, amount, description, created_at{$extraSql} FROM advance_transactions WHERE id = ?";
        $getStmt = $conn->prepare($getSql);
        if (!$getStmt) {
            throw new Exception('Failed to prepare get statement: ' . $conn->error);
        }
        
        $getStmt->bind_param('i', $transactionId);
        $getStmt->execute();
        $result = $getStmt->get_result();
        $transaction = $result->fetch_assoc();
        $getStmt->close();
        
        if (!$transaction) {
            throw new Exception('Transaction not found');
        }
        
        $description = strtolower(trim((string)($transaction['description'] ?? '')));
        $isFundTransfer = strpos($description, 'fund transfer') !== false;
        $counterpartyDriverId = $hasCpDriverCol
            ? (int)($transaction['counterparty_driver_id'] ?? 0)
            : 0;
        $counterTransactionId = 0;

        if ($isFundTransfer && $counterpartyDriverId > 0) {
            $counterType = ($transaction['type'] ?? '') === 'expense'
                ? 'advance_received'
                : 'expense';
            $counterSql = "
                SELECT id
                FROM advance_transactions
                WHERE driver_id = ?
                  AND type = ?
                  AND amount = ?
                  AND ABS(TIMESTAMPDIFF(SECOND, created_at, ?)) <= 5
            ";
            if ($hasCpDriverCol) {
                $counterSql .= " AND counterparty_driver_id = ?";
            }
            $counterSql .= " ORDER BY id DESC LIMIT 1";

            $counterStmt = $conn->prepare($counterSql);
            if ($counterStmt) {
                $counterDriverId = $counterpartyDriverId;
                $counterAmount = (float)($transaction['amount'] ?? 0);
                $counterCreatedAt = (string)($transaction['created_at'] ?? '');
                if ($hasCpDriverCol) {
                    $counterCpDriverId = (int)($transaction['driver_id'] ?? 0);
                    $counterStmt->bind_param(
                        'isdsi',
                        $counterDriverId,
                        $counterType,
                        $counterAmount,
                        $counterCreatedAt,
                        $counterCpDriverId
                    );
                } else {
                    $counterStmt->bind_param(
                        'isds',
                        $counterDriverId,
                        $counterType,
                        $counterAmount,
                        $counterCreatedAt
                    );
                }
                $counterStmt->execute();
                $counterResult = $counterStmt->get_result();
                $counterRow = $counterResult ? $counterResult->fetch_assoc() : null;
                $counterStmt->close();
                if ($counterRow && !empty($counterRow['id'])) {
                    $counterTransactionId = (int)$counterRow['id'];
                }
            }
        }

        $deleteIds = [$transactionId];
        if ($counterTransactionId > 0 && $counterTransactionId !== $transactionId) {
            $deleteIds[] = $counterTransactionId;
        }

        $deleteSql = "DELETE FROM advance_transactions WHERE id = ?";
        $deleteStmt = $conn->prepare($deleteSql);
        if (!$deleteStmt) {
            throw new Exception('Failed to prepare delete statement: ' . $conn->error);
        }
        foreach ($deleteIds as $deleteId) {
            $deleteStmt->bind_param('i', $deleteId);
            $deleteResult = $deleteStmt->execute();
            if (!$deleteResult) {
                $deleteStmt->close();
                throw new Exception('Failed to delete transaction');
            }
        }
        $deleteStmt->close();
        
        // Commit transaction
        $conn->commit();
        
        // Return success response
        apiRespond(200, [
            'status' => 'ok',
            'message' => 'Transaction deleted successfully',
            'deletedTransaction' => [
                'id' => $transaction['id'],
                'type' => $transaction['type'],
                'amount' => $transaction['amount'],
                'description' => $transaction['description']
            ],
            'deletedCounterTransactionId' => $counterTransactionId ?: null
        ]);
        
    } catch (Exception $e) {
        // Rollback transaction
        $conn->rollback();
        throw $e;
    }
    
} catch (Exception $e) {
    apiRespond(400, [
        'status' => 'error',
        'error' => $e->getMessage()
    ]);
}
?>
