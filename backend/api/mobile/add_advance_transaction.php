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
$userId = apiSanitizeInt($data['userId'] ?? $data['user_id'] ?? null);
$type = trim($data['type'] ?? '');
$amount = apiSanitizeFloat($data['amount'] ?? null);
$description = trim($data['description'] ?? '');
$category = trim($data['category'] ?? '');
$timestamp = trim($data['timestamp'] ?? '');
$vehicleId = apiSanitizeInt($data['vehicleId'] ?? $data['vehicle_id'] ?? null);
$vehiclePlantId = apiSanitizeInt(
    $data['vehiclePlantId'] ?? $data['vehicle_plant_id'] ?? $data['vehicle_plantId'] ?? null
);
$counterpartyDriverId = apiSanitizeInt(
    $data['counterpartyDriverId'] ?? $data['counterparty_driver_id'] ?? $data['targetDriverId'] ?? null
);
$counterpartyPlantId = apiSanitizeInt(
    $data['counterpartyPlantId'] ?? $data['counterparty_plant_id'] ?? null
);

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
$createdAtValue = date('Y-m-d H:i:s');
$entryDate = new DateTime(); // default now
if (!empty($timestamp)) {
    $timestampTime = strtotime($timestamp);
    if ($timestampTime !== false) {
        $createdAtValue = date('Y-m-d H:i:s', $timestampTime);
        $entryDate = new DateTime($createdAtValue);
    }
} else {
    $entryDate = new DateTime(); // now
}

try {
    // Check if user is allowed to backdate
    $advanceEntryAllowed = false;
    $advanceEntryFlagKnown = false;
    if ($userId) {
        // Only attempt if column exists
        $colCheck = $conn->query("SHOW COLUMNS FROM users LIKE 'advance_entry'");
        if ($colCheck && $colCheck->num_rows > 0) {
            $advanceEntryFlagKnown = true;
            $userStmt = $conn->prepare('SELECT advance_entry FROM users WHERE id = ? LIMIT 1');
            if ($userStmt) {
                $userStmt->bind_param('i', $userId);
                $userStmt->execute();
                $userRes = $userStmt->get_result();
                if ($userRow = $userRes->fetch_assoc()) {
                    $advanceEntryAllowed = strtoupper((string)($userRow['advance_entry'] ?? 'N')) === 'Y';
                }
                $userStmt->close();
            }
        }
    } elseif ($driverId) {
        // Fallback: try to resolve via driver_id mapping when userId not provided
        $colCheck = $conn->query("SHOW COLUMNS FROM users LIKE 'advance_entry'");
        if ($colCheck && $colCheck->num_rows > 0) {
            $advanceEntryFlagKnown = true;
            $userStmt = $conn->prepare('SELECT advance_entry FROM users WHERE driver_id = ? LIMIT 1');
            if ($userStmt) {
                $userStmt->bind_param('i', $driverId);
                $userStmt->execute();
                $userRes = $userStmt->get_result();
                if ($userRow = $userRes->fetch_assoc()) {
                    $advanceEntryAllowed = strtoupper((string)($userRow['advance_entry'] ?? 'N')) === 'Y';
                }
                $userStmt->close();
            }
        }
    }

    // Enforce date rule: after 5th, block past-month entries unless allowed
    $now = new DateTime();
    $currentYear = (int)$now->format('Y');
    $currentMonth = (int)$now->format('n');
    $entryYear = (int)$entryDate->format('Y');
    $entryMonth = (int)$entryDate->format('n');

    $isPastMonth = ($entryYear < $currentYear) || ($entryYear === $currentYear && $entryMonth < $currentMonth);
    if ($isPastMonth && !$advanceEntryAllowed && $now->format('j') > 5) {
        apiRespond(200, [
            'status' => 'error',
            'error' => 'Last day is already passed.',
        ]);
    }

    // If vehicle is provided but plant id is missing, try to resolve from vehicles table.
    if ($vehicleId !== null && ($vehiclePlantId === null || $vehiclePlantId <= 0)) {
        if (column_exists($conn, 'vehicles', 'plant_id')) {
            $vpStmt = $conn->prepare('SELECT plant_id FROM vehicles WHERE id = ? LIMIT 1');
            if ($vpStmt) {
                $vpStmt->bind_param('i', $vehicleId);
                if ($vpStmt->execute()) {
                    $vpRow = $vpStmt->get_result()->fetch_assoc();
                    if ($vpRow && isset($vpRow['plant_id'])) {
                        $resolved = (int)$vpRow['plant_id'];
                        if ($resolved > 0) {
                            $vehiclePlantId = $resolved;
                        }
                    }
                }
                $vpStmt->close();
            }
        }
    }

    // If counterparty driver is provided but counterparty plant id is missing,
    // try to resolve it from drivers table (or users table fallback).
    if ($counterpartyDriverId !== null && $counterpartyDriverId > 0 && ($counterpartyPlantId === null || $counterpartyPlantId <= 0)) {
        if (column_exists($conn, 'drivers', 'plant_id')) {
            $cpStmt = $conn->prepare('SELECT plant_id FROM drivers WHERE id = ? LIMIT 1');
            if ($cpStmt) {
                $cpStmt->bind_param('i', $counterpartyDriverId);
                if ($cpStmt->execute()) {
                    $cpRow = $cpStmt->get_result()->fetch_assoc();
                    if ($cpRow && isset($cpRow['plant_id'])) {
                        $resolved = (int)$cpRow['plant_id'];
                        if ($resolved > 0) {
                            $counterpartyPlantId = $resolved;
                        }
                    }
                }
                $cpStmt->close();
            }
        } elseif (column_exists($conn, 'users', 'plant_id')) {
            $cpStmt = $conn->prepare('SELECT plant_id FROM users WHERE driver_id = ? LIMIT 1');
            if ($cpStmt) {
                $cpStmt->bind_param('i', $counterpartyDriverId);
                if ($cpStmt->execute()) {
                    $cpRow = $cpStmt->get_result()->fetch_assoc();
                    if ($cpRow && isset($cpRow['plant_id'])) {
                        $resolved = (int)$cpRow['plant_id'];
                        if ($resolved > 0) {
                            $counterpartyPlantId = $resolved;
                        }
                    }
                }
                $cpStmt->close();
            }
        }
    }

    // Insert transaction with custom timestamp
    $cols = ['driver_id', 'type', 'amount', 'description', 'created_at'];
    $placeholders = ['?', '?', '?', '?', '?'];
    $types = 'isdss';
    $values = [$driverId, $type, (float)$amount, $description, $createdAtValue];

    // Optional category column (e.g., selected from KhataBook "You Gave" dialog)
    if ($category !== '' && column_exists($conn, 'advance_transactions', 'category')) {
        $cols[] = 'category';
        $placeholders[] = '?';
        $types .= 's';
        $values[] = $category;
    }

    if ($vehicleId !== null && $vehicleId > 0 && column_exists($conn, 'advance_transactions', 'vehicle_id')) {
        $cols[] = 'vehicle_id';
        $placeholders[] = '?';
        $types .= 'i';
        $values[] = $vehicleId;
    }
    if ($vehiclePlantId !== null && $vehiclePlantId > 0 && column_exists($conn, 'advance_transactions', 'vehicle_plant_id')) {
        $cols[] = 'vehicle_plant_id';
        $placeholders[] = '?';
        $types .= 'i';
        $values[] = $vehiclePlantId;
    }
    if ($counterpartyDriverId !== null && $counterpartyDriverId > 0 && column_exists($conn, 'advance_transactions', 'counterparty_driver_id')) {
        $cols[] = 'counterparty_driver_id';
        $placeholders[] = '?';
        $types .= 'i';
        $values[] = $counterpartyDriverId;
    }
    if ($counterpartyPlantId !== null && $counterpartyPlantId > 0 && column_exists($conn, 'advance_transactions', 'counterparty_plant_id')) {
        $cols[] = 'counterparty_plant_id';
        $placeholders[] = '?';
        $types .= 'i';
        $values[] = $counterpartyPlantId;
    }

    $sql = 'INSERT INTO advance_transactions (' . implode(', ', $cols) . ') VALUES (' . implode(', ', $placeholders) . ')';
    $insertStmt = $conn->prepare($sql);
    if (!$insertStmt) {
        apiRespond(500, ['status' => 'error', 'error' => 'Failed to prepare insert statement']);
    }
    $bindParams = [$types];
    foreach ($values as $k => $v) {
        $bindParams[] = &$values[$k];
    }
    call_user_func_array([$insertStmt, 'bind_param'], $bindParams);
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
