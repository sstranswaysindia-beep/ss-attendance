<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/common.php';

apiEnsurePost();

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
        $getSql = "SELECT id, driver_id, type, amount, description, created_at FROM advance_transactions WHERE id = ?";
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
        
        // Delete the transaction
        $deleteSql = "DELETE FROM advance_transactions WHERE id = ?";
        $deleteStmt = $conn->prepare($deleteSql);
        if (!$deleteStmt) {
            throw new Exception('Failed to prepare delete statement: ' . $conn->error);
        }
        
        $deleteStmt->bind_param('i', $transactionId);
        $deleteResult = $deleteStmt->execute();
        $deleteStmt->close();
        
        if (!$deleteResult) {
            throw new Exception('Failed to delete transaction');
        }
        
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
            ]
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
