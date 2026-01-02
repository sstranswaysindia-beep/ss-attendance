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

// Debug: Log that API was called
$debugMsg = "DEBUG: Fund transfer API called at " . date('Y-m-d H:i:s') . "\n";
file_put_contents(__DIR__ . '/../../debug_log.txt', $debugMsg, FILE_APPEND);

apiEnsurePost();

$data = apiRequireJson();
$driverId = apiSanitizeInt($data['driverId'] ?? null);
$amount = (float)($data['amount'] ?? 0);
$description = trim($data['description'] ?? '');
$category = trim((string)($data['category'] ?? ''));
$senderId = apiSanitizeInt($data['senderId'] ?? null); // Who is sending the money
$timestamp = isset($data['timestamp']) ? trim((string)$data['timestamp']) : '';
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
    $senderPlant = '';
    if (isset($senderData['plant_id']) && (int)$senderData['plant_id'] > 0) {
        $senderPlantId = (int)$senderData['plant_id'];
        $senderPlantStmt = $conn->prepare("SELECT plant_name FROM plants WHERE id = ? LIMIT 1");
        if ($senderPlantStmt) {
            $senderPlantStmt->bind_param('i', $senderPlantId);
            $senderPlantStmt->execute();
            $senderPlantResult = $senderPlantStmt->get_result();
            if ($senderPlantRow = $senderPlantResult->fetch_assoc()) {
                $senderPlant = trim((string)($senderPlantRow['plant_name'] ?? ''));
            }
            $senderPlantStmt->close();
        }
    }
    $senderLabel = $senderName . ($senderPlant !== '' ? " ($senderPlant)" : '');

    $debugMsg = "[" . date('Y-m-d H:i:s') . "] SENDER_NAME_EXTRACTED: '$senderName'\n";
    error_log($debugMsg);
    file_put_contents(__DIR__ . '/../../debug_fund_transfer.log', $debugMsg, FILE_APPEND);

    // Debug: Log the final description that will be used
    $receiverName = trim((string)($driverData[$nameColumn] ?? $driverData['name'] ?? "Driver ID $driverId"));
    if ($receiverName === '') {
        $receiverName = "Driver ID $driverId";
    }
    $receiverPlant = '';
    if (isset($driverData['plant_id']) && (int)$driverData['plant_id'] > 0) {
        $plantId = (int)$driverData['plant_id'];
        $plantStmt = $conn->prepare("SELECT plant_name FROM plants WHERE id = ? LIMIT 1");
        if ($plantStmt) {
            $plantStmt->bind_param('i', $plantId);
            $plantStmt->execute();
            $plantResult = $plantStmt->get_result();
            if ($plantRow = $plantResult->fetch_assoc()) {
                $receiverPlant = trim((string)($plantRow['plant_name'] ?? ''));
            }
            $plantStmt->close();
        }
    }
    $receiverLabel = $receiverName . ($receiverPlant !== '' ? " ($receiverPlant)" : '');
    $normalizedCategory = strtoupper($category);
    $isAdvanceCategory =
        $normalizedCategory !== '' && stripos($normalizedCategory, 'ADVANCE') !== false;

    $finalReceiverDesc = $isAdvanceCategory
        ? "Fund transfer from {$senderLabel}"
        : "Fund transfer from {$senderLabel} - $description";
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

    // Allow negative balances for advance entries (fund transfers)
    // Removed balance check to allow advance entries even when balance is negative
    // This enables drivers to receive advances even if their current balance is negative

    $createdAt = date('Y-m-d H:i:s');
    if ($timestamp !== '') {
        $ts = strtotime($timestamp);
        if ($ts !== false) {
            $createdAt = date('Y-m-d H:i:s', $ts);
        }
    }

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

        $hasCpDriverCol = column_exists($conn, 'advance_transactions', 'counterparty_driver_id');
        $hasCpPlantCol = column_exists($conn, 'advance_transactions', 'counterparty_plant_id');
        $hasCategoryCol = column_exists($conn, 'advance_transactions', 'category');

        $receiverCols = ['driver_id', 'amount', 'type', 'description', 'created_at'];
        $receiverPh = ['?', '?', '?', '?', '?'];
        $receiverTypes = 'idsss';
        $receiverVals = [$receiverDriverId, $receiverAmount, $receiverType, $receiverDesc, $createdAt];

        if ($hasCpDriverCol) {
            $receiverCols[] = 'counterparty_driver_id';
            $receiverPh[] = '?';
            $receiverTypes .= 'i';
            $receiverVals[] = (int)$senderId;
        }
        if ($hasCpPlantCol) {
            $receiverCols[] = 'counterparty_plant_id';
            $receiverPh[] = '?';
            $receiverTypes .= 'i';
            $receiverVals[] = (int)$senderPlantId;
        }
        if ($hasCategoryCol && $category !== '') {
            $receiverCols[] = 'category';
            $receiverPh[] = '?';
            $receiverTypes .= 's';
            $receiverVals[] = $category;
        }

        $receiverSql = 'INSERT INTO advance_transactions (' . implode(', ', $receiverCols) . ') VALUES (' . implode(', ', $receiverPh) . ')';
        $receiverStmt = $conn->prepare($receiverSql);
        if (!$receiverStmt) {
            throw new RuntimeException('Failed to prepare receiver insert statement');
        }
        $receiverBind = [$receiverTypes];
        foreach ($receiverVals as $k => $v) {
            $receiverBind[] = &$receiverVals[$k];
        }
        call_user_func_array([$receiverStmt, 'bind_param'], $receiverBind);
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
        $senderDesc = $isAdvanceCategory
            ? "Fund transfer to {$receiverLabel}"
            : "Fund transfer to {$receiverLabel} - $description";
        
        error_log("DEBUG: Sender transaction params - senderId: " . gettype($senderId) . " = $senderId, amount: " . gettype($amount) . " = $amount");
        
        // Cast variables to proper types for bind_param
        $senderDriverId = (int)$senderId;
        $senderAmount = (float)$amount;

        $senderCols = ['driver_id', 'amount', 'type', 'description', 'created_at'];
        $senderPh = ['?', '?', '?', '?', '?'];
        $senderTypes = 'idsss';
        $senderVals = [$senderDriverId, $senderAmount, $senderType, $senderDesc, $createdAt];

        if ($hasCpDriverCol) {
            $senderCols[] = 'counterparty_driver_id';
            $senderPh[] = '?';
            $senderTypes .= 'i';
            $senderVals[] = (int)$driverId;
        }
        if ($hasCpPlantCol) {
            $senderCols[] = 'counterparty_plant_id';
            $senderPh[] = '?';
            $senderTypes .= 'i';
            $senderVals[] = (int)$plantId;
        }
        if ($hasCategoryCol && $category !== '') {
            $senderCols[] = 'category';
            $senderPh[] = '?';
            $senderTypes .= 's';
            $senderVals[] = $category;
        }

        $senderSql = 'INSERT INTO advance_transactions (' . implode(', ', $senderCols) . ') VALUES (' . implode(', ', $senderPh) . ')';
        $senderStmt = $conn->prepare($senderSql);
        if (!$senderStmt) {
            throw new RuntimeException('Failed to prepare sender insert statement');
        }
        $senderBind = [$senderTypes];
        foreach ($senderVals as $k => $v) {
            $senderBind[] = &$senderVals[$k];
        }
        call_user_func_array([$senderStmt, 'bind_param'], $senderBind);
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
            'driverName' => $receiverLabel,
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
