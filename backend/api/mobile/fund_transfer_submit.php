<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require __DIR__ . '/common.php';

// Debug: Log that API was called
$debugMsg = "DEBUG: Fund transfer API called at " . date('Y-m-d H:i:s') . "\n";
file_put_contents(__DIR__ . '/../../debug_log.txt', $debugMsg, FILE_APPEND);

apiEnsurePost();

$data = apiRequireJson();
$driverId = apiSanitizeInt($data['driverId'] ?? null);
$amount = (float)($data['amount'] ?? 0);
$description = trim($data['description'] ?? '');
$senderId = apiSanitizeInt($data['senderId'] ?? null); // Who is sending the money

if (!$driverId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId is required']);
}

if (!$senderId) {
    apiRespond(400, ['status' => 'error', 'error' => 'senderId is required']);
}

if ($amount <= 0) {
    apiRespond(400, ['status' => 'error', 'error' => 'Amount must be greater than 0']);
}

if (empty($description)) {
    apiRespond(400, ['status' => 'error', 'error' => 'Description is required']);
}

try {
    // Debug: Log input parameters
    $debugMsg = "DEBUG: Fund transfer request - driverId: $driverId, senderId: $senderId, amount: $amount, description: $description\n";
    error_log($debugMsg);
    file_put_contents(__DIR__ . '/../../debug_log.txt', $debugMsg, FILE_APPEND);

    // Verify receiver driver exists
    $driverStmt = $conn->prepare('SELECT id, name FROM drivers WHERE id = ? LIMIT 1');
    $driverStmt->bind_param('i', $driverId);
    $driverStmt->execute();
    $driverResult = $driverStmt->get_result();
    $driverData = $driverResult->fetch_assoc();
    $driverStmt->close();

    $debugMsg = "DEBUG: Receiver driver lookup result: " . json_encode($driverData) . "\n";
    error_log($debugMsg);
    file_put_contents(__DIR__ . '/../../debug_log.txt', $debugMsg, FILE_APPEND);

    if (!$driverData) {
        apiRespond(404, ['status' => 'error', 'error' => 'Receiver driver not found']);
    }

    // Verify sender driver exists and get name
    $senderStmt = $conn->prepare('SELECT id, name FROM drivers WHERE id = ? LIMIT 1');
    $senderStmt->bind_param('i', $senderId);
    $senderStmt->execute();
    $senderResult = $senderStmt->get_result();
    $senderData = $senderResult->fetch_assoc();
    $senderStmt->close();

    $debugMsg = "DEBUG: Sender driver lookup result: " . json_encode($senderData) . "\n";
    error_log($debugMsg);
    file_put_contents(__DIR__ . '/../../debug_log.txt', $debugMsg, FILE_APPEND);

    if (!$senderData) {
        apiRespond(404, ['status' => 'error', 'error' => 'Sender driver not found']);
    }

    // Get current balance for sender (to verify they have enough funds)
    $senderBalanceStmt = $conn->prepare(
        'SELECT 
            COALESCE(SUM(CASE WHEN type = \'advance_received\' THEN amount ELSE 0 END), 0) -
            COALESCE(SUM(CASE WHEN type = \'expense\' THEN amount ELSE 0 END), 0) as balance
        FROM advance_transactions 
        WHERE driver_id = ?'
    );
    $senderBalanceStmt->bind_param('i', $senderId);
    $senderBalanceStmt->execute();
    $senderBalanceResult = $senderBalanceStmt->get_result();
    $senderBalance = $senderBalanceResult->fetch_assoc()['balance'] ?? 0;
    $senderBalanceStmt->close();

    $debugMsg = "DEBUG: Sender balance check - senderId: $senderId, current balance: $senderBalance, transfer amount: $amount\n";
    error_log($debugMsg);
    file_put_contents(__DIR__ . '/../../debug_log.txt', $debugMsg, FILE_APPEND);

    // Check if sender has sufficient balance
    if ($senderBalance < $amount) {
        apiRespond(400, ['status' => 'error', 'error' => 'Insufficient balance for transfer']);
    }

    $createdAt = date('Y-m-d H:i:s');

    // Start transaction
    $conn->begin_transaction();

    try {
        // 1. Insert transaction for RECEIVER (driver) - they receive money
        $receiverType = 'advance_received';
        $receiverDesc = "Fund transfer from {$senderData['name']} - $description";
        
        error_log("DEBUG: Receiver transaction params - driverId: " . gettype($driverId) . " = $driverId, amount: " . gettype($amount) . " = $amount");
        
        // Cast variables to proper types for bind_param
        $receiverDriverId = (int)$driverId;
        $receiverAmount = (float)$amount;
        
        $receiverStmt = $conn->prepare(
            'INSERT INTO advance_transactions (
                driver_id,
                amount,
                type,
                description,
                created_at
            ) VALUES (?, ?, ?, ?, ?)' 
        );
        $receiverStmt->bind_param('idsss', $receiverDriverId, $receiverAmount, $receiverType, $receiverDesc, $createdAt);
        $receiverStmt->execute();
        $receiverTransactionId = $receiverStmt->insert_id;
        $receiverStmt->close();
        
        $debugMsg = "DEBUG: Receiver transaction inserted with ID: $receiverTransactionId\n";
        error_log($debugMsg);
        file_put_contents(__DIR__ . '/../../debug_log.txt', $debugMsg, FILE_APPEND);

        // 2. Insert transaction for SENDER - they spend money
        $senderType = 'expense';
        $senderDesc = "Fund transfer to {$driverData['name']} - $description";
        
        error_log("DEBUG: Sender transaction params - senderId: " . gettype($senderId) . " = $senderId, amount: " . gettype($amount) . " = $amount");
        
        // Cast variables to proper types for bind_param
        $senderDriverId = (int)$senderId;
        $senderAmount = (float)$amount;
        
        $senderStmt = $conn->prepare(
            'INSERT INTO advance_transactions (
                driver_id,
                amount,
                type,
                description,
                created_at
            ) VALUES (?, ?, ?, ?, ?)' 
        );
        $senderStmt->bind_param('idsss', $senderDriverId, $senderAmount, $senderType, $senderDesc, $createdAt);
        $senderStmt->execute();
        $senderTransactionId = $senderStmt->insert_id;
        $senderStmt->close();
        
        $debugMsg = "DEBUG: Sender transaction inserted with ID: $senderTransactionId\n";
        error_log($debugMsg);
        file_put_contents(__DIR__ . '/../../debug_log.txt', $debugMsg, FILE_APPEND);

        // Commit transaction
        $conn->commit();

        apiRespond(201, [
            'status' => 'ok',
            'receiverTransactionId' => (int)$receiverTransactionId,
            'senderTransactionId' => (int)$senderTransactionId,
            'driverId' => $driverId,
            'driverName' => $driverData['name'],
            'senderId' => $senderId,
            'senderName' => $senderData['name'],
            'amount' => $amount,
            'description' => $description,
            'createdAt' => $createdAt,
        ]);

    } catch (Exception $e) {
        // Rollback on error
        $conn->rollback();
        throw $e;
    }

} catch (Throwable $error) {
    $errorMsg = "DEBUG: Fund transfer error - " . $error->getMessage() . "\n";
    $traceMsg = "DEBUG: Fund transfer error trace - " . $error->getTraceAsString() . "\n";
    error_log($errorMsg);
    error_log($traceMsg);
    file_put_contents(__DIR__ . '/../../debug_log.txt', $errorMsg . $traceMsg, FILE_APPEND);
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
?>