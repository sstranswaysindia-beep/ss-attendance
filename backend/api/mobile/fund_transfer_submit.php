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
$requestSenderName = '';
if (isset($data['senderName'])) {
    $requestSenderName = trim((string) $data['senderName']);
    $requestSenderName = strip_tags($requestSenderName);
    if ($requestSenderName !== '') {
        $requestSenderName = preg_replace('/\s+/', ' ', $requestSenderName);
    }
}

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
    // Helper function to detect name column
    function getDriverNameColumn($conn) {
        $columns = ['name', 'driver_name', 'full_name', 'first_name'];
        foreach ($columns as $col) {
            $result = $conn->query("SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'drivers' AND COLUMN_NAME = '$col' LIMIT 1");
            if ($result && $result->num_rows > 0) {
                return $col;
            }
        }
        return 'name'; // fallback
    }

    $nameColumn = getDriverNameColumn($conn);
    $debugMsg = "[" . date('Y-m-d H:i:s') . "] NAME_COLUMN_DETECTED: Using column '$nameColumn'\n";
    error_log($debugMsg);
    file_put_contents(__DIR__ . '/../../debug_fund_transfer.log', $debugMsg, FILE_APPEND);

    // Debug: Log input parameters
    $debugMsg = "\n=== NEW FUND TRANSFER ===\n";
    file_put_contents(__DIR__ . '/../../debug_fund_transfer.log', $debugMsg, FILE_APPEND);
    
    $debugMsg = "[" . date('Y-m-d H:i:s') . "] FUND_TRANSFER_START: driverId=$driverId, senderId=$senderId, amount=$amount, description='$description'\n";
    error_log($debugMsg);
    file_put_contents(__DIR__ . '/../../debug_fund_transfer.log', $debugMsg, FILE_APPEND);
    
    // Also log to error log for debugging
    error_log("DEBUG: Fund transfer API called - driverId: $driverId, senderId: $senderId, amount: $amount, description: $description");

    // Verify receiver driver exists
    $driverStmt = $conn->prepare("SELECT * FROM drivers WHERE id = ? LIMIT 1");
    $driverStmt->bind_param('i', $driverId);
    $driverStmt->execute();
    $driverResult = $driverStmt->get_result();
    $driverData = $driverResult->fetch_assoc();
    $driverStmt->close();

    $debugMsg = "[" . date('Y-m-d H:i:s') . "] RECEIVER_LOOKUP: " . json_encode($driverData) . "\n";
    error_log($debugMsg);
    file_put_contents(__DIR__ . '/../../debug_fund_transfer.log', $debugMsg, FILE_APPEND);

    if (!$driverData) {
        apiRespond(404, ['status' => 'error', 'error' => 'Receiver driver not found']);
    }

    // Verify sender driver exists and get name - try multiple columns
    $senderStmt = $conn->prepare("SELECT * FROM drivers WHERE id = ? LIMIT 1");
    $senderStmt->bind_param('i', $senderId);
    $senderStmt->execute();
    $senderResult = $senderStmt->get_result();
    $senderData = $senderResult->fetch_assoc();
    $senderStmt->close();

    $debugMsg = "[" . date('Y-m-d H:i:s') . "] SENDER_LOOKUP: " . json_encode($senderData) . "\n";
    error_log($debugMsg);
    file_put_contents(__DIR__ . '/../../debug_fund_transfer.log', $debugMsg, FILE_APPEND);
    
    // Additional debug: Check what columns were actually returned
    if ($senderData) {
        $debugMsg = "[" . date('Y-m-d H:i:s') . "] SENDER_COLUMNS: name='" . ($senderData['name'] ?? 'NULL') . "', driver_name='" . ($senderData['driver_name'] ?? 'NULL') . "', full_name='" . ($senderData['full_name'] ?? 'NULL') . "', first_name='" . ($senderData['first_name'] ?? 'NULL') . "', last_name='" . ($senderData['last_name'] ?? 'NULL') . "'\n";
        error_log($debugMsg);
        file_put_contents(__DIR__ . '/../../debug_fund_transfer.log', $debugMsg, FILE_APPEND);
    }

    if (!$senderData) {
        apiRespond(404, ['status' => 'error', 'error' => 'Sender driver not found']);
    }

    // Debug: Check if sender name exists and provide fallback
    $senderName = null;
    $senderNameCandidates = [
        $senderData[$nameColumn] ?? null,
        $senderData['name'] ?? null,
        $senderData['driver_name'] ?? null,
        $senderData['full_name'] ?? null,
        isset($senderData['first_name']) || isset($senderData['last_name'])
            ? trim(
                ($senderData['first_name'] ?? '') .
                ' ' .
                ($senderData['last_name'] ?? ''),
            )
            : null,
        $requestSenderName !== '' ? $requestSenderName : null,
        "Driver ID $senderId"
    ];
    $debugMsg = "[" . date('Y-m-d H:i:s') . "] SENDER_NAME_CANDIDATES: " . json_encode($senderNameCandidates) . "\n";
    error_log($debugMsg);
    file_put_contents(__DIR__ . '/../../debug_fund_transfer.log', $debugMsg, FILE_APPEND);
    foreach ($senderNameCandidates as $candidate) {
        if ($candidate === null) {
            continue;
        }
        $candidate = trim((string) $candidate);
        if ($candidate === '') {
            continue;
        }
        $normalized = strtolower($candidate);
        if (
            $normalized === 'null' ||
            $normalized === 'sender' ||
            $normalized === 'receiver' ||
            $normalized === 'na' ||
            $normalized === 'n/a' ||
            $normalized === 'driver'
        ) {
            $debugMsg = "[" . date('Y-m-d H:i:s') . "] SENDER_NAME_SKIPPED_PLACEHOLDER: '$candidate'\n";
            error_log($debugMsg);
            file_put_contents(__DIR__ . '/../../debug_fund_transfer.log', $debugMsg, FILE_APPEND);
            continue;
        }
        $senderName = $candidate;
        break;
    }
    if ($senderName === null) {
        $senderName = "Driver ID $senderId";
    }

    $debugMsg = "[" . date('Y-m-d H:i:s') . "] SENDER_NAME_EXTRACTED: '$senderName'\n";
    error_log($debugMsg);
    file_put_contents(__DIR__ . '/../../debug_fund_transfer.log', $debugMsg, FILE_APPEND);

    // Debug: Log the final description that will be used
    $receiverName = trim((string)($driverData[$nameColumn] ?? $driverData['name'] ?? "Driver ID $driverId"));
    if ($receiverName === '') {
        $receiverName = "Driver ID $driverId";
    }
    $finalReceiverDesc = "Fund transfer from {$senderName} - $description";
    $debugMsg = "[" . date('Y-m-d H:i:s') . "] RECEIVER_DESCRIPTION: '$finalReceiverDesc'\n";
    error_log($debugMsg);
    file_put_contents(__DIR__ . '/../../debug_fund_transfer.log', $debugMsg, FILE_APPEND);

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
        $receiverDesc = $finalReceiverDesc;
        
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
        
        $debugMsg = "[" . date('Y-m-d H:i:s') . "] RECEIVER_TRANSACTION_INSERTED: ID=$receiverTransactionId, Description='$receiverDesc'\n";
        error_log($debugMsg);
        file_put_contents(__DIR__ . '/../../debug_fund_transfer.log', $debugMsg, FILE_APPEND);
        
        // Additional debug: Verify what was actually inserted
        $verifyStmt = $conn->prepare("SELECT description FROM advance_transactions WHERE id = ?");
        $verifyStmt->bind_param('i', $receiverTransactionId);
        $verifyStmt->execute();
        $verifyResult = $verifyStmt->get_result();
        $verifyData = $verifyResult->fetch_assoc();
        $verifyStmt->close();
        
        $debugMsg = "[" . date('Y-m-d H:i:s') . "] VERIFIED_IN_DB: '" . ($verifyData['description'] ?? 'NOT_FOUND') . "'\n";
        error_log($debugMsg);
        file_put_contents(__DIR__ . '/../../debug_fund_transfer.log', $debugMsg, FILE_APPEND);

        // 2. Insert transaction for SENDER - they spend money
        $senderType = 'expense';
        $senderDesc = "Fund transfer to {$receiverName} - $description";
        
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
            'driverName' => $receiverName,
            'senderId' => $senderId,
            'senderName' => $senderName,
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
