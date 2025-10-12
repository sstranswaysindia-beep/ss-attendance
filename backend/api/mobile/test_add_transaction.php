<?php
require_once 'common.php';

header('Content-Type: text/html; charset=utf-8');

echo "<h2>Test Add Transaction API</h2>";
echo "<p>This script tests the add_advance_transaction.php endpoint.</p>";

try {
    // Check if table exists
    $tableCheckStmt = $conn->prepare("
        SELECT COUNT(*) as table_exists 
        FROM information_schema.tables 
        WHERE table_schema = DATABASE() 
        AND table_name = 'advance_transactions'
    ");
    $tableCheckStmt->execute();
    $tableExists = $tableCheckStmt->get_result()->fetch_assoc()['table_exists'];
    $tableCheckStmt->close();
    
    if (!$tableExists) {
        echo "<p style='color: red;'>❌ advance_transactions table does not exist!</p>";
        exit;
    }
    
    echo "<p style='color: green;'>✅ advance_transactions table exists</p>";
    
    // Test data
    $testData = [
        'driverId' => 1,
        'type' => 'expense',
        'amount' => 100.00,
        'description' => 'Test transaction from debug script'
    ];
    
    echo "<h3>Test Data:</h3>";
    echo "<pre>" . json_encode($testData, JSON_PRETTY_PRINT) . "</pre>";
    
    // Simulate the API call
    echo "<h3>Testing API Logic:</h3>";
    
    $driverId = $testData['driverId'];
    $type = $testData['type'];
    $amount = $testData['amount'];
    $description = $testData['description'];
    
    // Validate inputs
    if (!$driverId || !$type || !$amount) {
        echo "<p style='color: red;'>❌ Validation failed: driverId, type, and amount are required</p>";
        exit;
    }
    
    if (!in_array($type, ['advance_received', 'expense'], true)) {
        echo "<p style='color: red;'>❌ Validation failed: type must be advance_received or expense</p>";
        exit;
    }
    
    if ($amount <= 0) {
        echo "<p style='color: red;'>❌ Validation failed: amount must be positive</p>";
        exit;
    }
    
    echo "<p style='color: green;'>✅ Input validation passed</p>";
    
    // Test insert
    echo "<h3>Testing Database Insert:</h3>";
    
    $insertStmt = $conn->prepare("
        INSERT INTO advance_transactions (driver_id, type, amount, description, created_at)
        VALUES (?, ?, ?, ?, NOW())
    ");
    
    if (!$insertStmt) {
        echo "<p style='color: red;'>❌ Failed to prepare statement: " . $conn->error . "</p>";
        exit;
    }
    
    $insertStmt->bind_param('isds', $driverId, $type, $amount, $description);
    
    if ($insertStmt->execute()) {
        $transactionId = $insertStmt->insert_id;
        echo "<p style='color: green;'>✅ Transaction inserted successfully with ID: $transactionId</p>";
        
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
        
        echo "<p>Updated balance for driver $driverId: ₹" . number_format($balance, 2) . "</p>";
        
        // Expected API response
        echo "<h3>Expected API Response:</h3>";
        echo "<pre>";
        echo json_encode([
            'status' => 'ok',
            'transactionId' => (int)$transactionId,
            'balance' => (float)$balance,
            'message' => 'Transaction added successfully'
        ], JSON_PRETTY_PRINT);
        echo "</pre>";
        
    } else {
        echo "<p style='color: red;'>❌ Failed to insert transaction: " . $insertStmt->error . "</p>";
    }
    
    $insertStmt->close();
    
} catch (Exception $e) {
    echo "<h3 style='color: red;'>❌ Error</h3>";
    echo "<p>Error: " . $e->getMessage() . "</p>";
}

echo "<h3>🔍 Troubleshooting:</h3>";
echo "<ul>";
echo "<li>Check if the add_advance_transaction.php file exists and is accessible</li>";
echo "<li>Verify the database connection is working</li>";
echo "<li>Check if the advance_transactions table has the correct structure</li>";
echo "<li>Ensure the driver_id exists (or use a valid one)</li>";
echo "</ul>";
?>
