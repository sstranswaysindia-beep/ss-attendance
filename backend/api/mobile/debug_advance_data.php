<?php
require_once 'common.php';

header('Content-Type: text/html; charset=utf-8');

echo "<h2>Debug Advance & Salary Data</h2>";
echo "<p>This script helps debug the advance and salary feature.</p>";

try {
    // Check if advance_transactions table exists
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
        echo "<p>Please run setup_advance_tables.php first.</p>";
        exit;
    }
    
    echo "<p style='color: green;'>✅ advance_transactions table exists</p>";
    
    // Show all transactions
    echo "<h3>All Advance Transactions</h3>";
    $transactionsStmt = $conn->prepare("
        SELECT 
            id,
            driver_id,
            type,
            amount,
            description,
            created_at
        FROM advance_transactions 
        ORDER BY created_at DESC
    ");
    $transactionsStmt->execute();
    $transactions = $transactionsStmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $transactionsStmt->close();
    
    if (empty($transactions)) {
        echo "<p style='color: orange;'>⚠️ No transactions found in advance_transactions table</p>";
    } else {
        echo "<p>Found " . count($transactions) . " transactions:</p>";
        echo "<table border='1' style='border-collapse: collapse; width: 100%;'>";
        echo "<tr><th>ID</th><th>Driver ID</th><th>Type</th><th>Amount</th><th>Description</th><th>Created</th></tr>";
        
        foreach ($transactions as $transaction) {
            echo "<tr>";
            echo "<td>" . $transaction['id'] . "</td>";
            echo "<td>" . $transaction['driver_id'] . "</td>";
            echo "<td>" . $transaction['type'] . "</td>";
            echo "<td>₹" . number_format($transaction['amount'], 2) . "</td>";
            echo "<td>" . htmlspecialchars($transaction['description']) . "</td>";
            echo "<td>" . $transaction['created_at'] . "</td>";
            echo "</tr>";
        }
        echo "</table>";
    }
    
    // Show balance calculation
    echo "<h3>Balance Calculation by Driver</h3>";
    $balanceStmt = $conn->prepare("
        SELECT 
            driver_id,
            COUNT(*) as transaction_count,
            COALESCE(SUM(CASE WHEN type = 'advance_received' THEN amount ELSE 0 END), 0) as total_received,
            COALESCE(SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END), 0) as total_expenses,
            COALESCE(SUM(CASE WHEN type = 'advance_received' THEN amount ELSE 0 END), 0) -
            COALESCE(SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END), 0) as balance
        FROM advance_transactions 
        GROUP BY driver_id
        ORDER BY driver_id
    ");
    $balanceStmt->execute();
    $balances = $balanceStmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $balanceStmt->close();
    
    if (empty($balances)) {
        echo "<p style='color: orange;'>⚠️ No balance data found</p>";
    } else {
        echo "<table border='1' style='border-collapse: collapse; width: 100%;'>";
        echo "<tr><th>Driver ID</th><th>Transactions</th><th>Total Received</th><th>Total Expenses</th><th>Balance</th></tr>";
        
        foreach ($balances as $balance) {
            echo "<tr>";
            echo "<td>" . $balance['driver_id'] . "</td>";
            echo "<td>" . $balance['transaction_count'] . "</td>";
            echo "<td>₹" . number_format($balance['total_received'], 2) . "</td>";
            echo "<td>₹" . number_format($balance['total_expenses'], 2) . "</td>";
            echo "<td><strong>₹" . number_format($balance['balance'], 2) . "</strong></td>";
            echo "</tr>";
        }
        echo "</table>";
    }
    
    // Test API endpoints
    echo "<h3>API Endpoint Tests</h3>";
    
    // Test get_advance_balance.php
    echo "<h4>Test: get_advance_balance.php</h4>";
    if (!empty($transactions)) {
        $testDriverId = $transactions[0]['driver_id'];
        echo "<p>Testing with Driver ID: $testDriverId</p>";
        
        // Simulate the API call
        $testBalanceStmt = $conn->prepare("
            SELECT 
                COALESCE(SUM(CASE WHEN type = 'advance_received' THEN amount ELSE 0 END), 0) -
                COALESCE(SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END), 0) as balance
            FROM advance_transactions 
            WHERE driver_id = ?
        ");
        $testBalanceStmt->bind_param('i', $testDriverId);
        $testBalanceStmt->execute();
        $testBalance = $testBalanceStmt->get_result()->fetch_assoc()['balance'] ?? 0;
        $testBalanceStmt->close();
        
        echo "<p>Expected API Response:</p>";
        echo "<pre>";
        echo json_encode([
            'status' => 'ok',
            'balance' => (float)$testBalance,
            'currency' => 'INR',
            'driverId' => (int)$testDriverId
        ], JSON_PRETTY_PRINT);
        echo "</pre>";
    }
    
    // Test get_advance_transactions.php
    echo "<h4>Test: get_advance_transactions.php</h4>";
    if (!empty($transactions)) {
        $testDriverId = $transactions[0]['driver_id'];
        echo "<p>Testing with Driver ID: $testDriverId</p>";
        
        $testTransactionsStmt = $conn->prepare("
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
            LIMIT 10
        ");
        $testTransactionsStmt->bind_param('i', $testDriverId);
        $testTransactionsStmt->execute();
        $testTransactions = $testTransactionsStmt->get_result()->fetch_all(MYSQLI_ASSOC);
        $testTransactionsStmt->close();
        
        echo "<p>Expected API Response:</p>";
        echo "<pre>";
        echo json_encode([
            'status' => 'ok',
            'transactions' => $testTransactions,
            'driverId' => (int)$testDriverId,
            'count' => count($testTransactions)
        ], JSON_PRETTY_PRINT);
        echo "</pre>";
    }
    
    echo "<h3>🔍 Troubleshooting Tips</h3>";
    echo "<ul>";
    echo "<li>Make sure you're logged in with a user that has a valid driver_id</li>";
    echo "<li>Check that the advance_transactions table has data</li>";
    echo "<li>Verify the API endpoints are accessible</li>";
    echo "<li>Check the app's debug logs for any errors</li>";
    echo "</ul>";
    
} catch (Exception $e) {
    echo "<h3 style='color: red;'>❌ Error</h3>";
    echo "<p>Error: " . $e->getMessage() . "</p>";
}
?>
