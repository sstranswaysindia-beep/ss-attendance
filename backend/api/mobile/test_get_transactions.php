<?php
declare(strict_types=1);

echo "<h2>🔍 Testing Get Advance Transactions API</h2>";

// Test the get_advance_transactions.php API
$testData = [
    'driverId' => 169,
    'limit' => 10,
];

echo "<h3>1. Test Data:</h3>";
echo "<pre>" . json_encode($testData, JSON_PRETTY_PRINT) . "</pre>";

$url = 'https://sstranswaysindia.com/api/mobile/get_advance_transactions.php';

$options = [
    'http' => [
        'header' => "Content-Type: application/json\r\n",
        'method' => 'POST',
        'content' => json_encode($testData),
    ],
];

$context = stream_context_create($options);
$result = file_get_contents($url, false, $context);

echo "<h3>2. API Response:</h3>";
if ($result === false) {
    echo "❌ Failed to get response from API<br>";
} else {
    echo "<pre>" . htmlspecialchars($result) . "</pre>";
    
    // Try to decode the response
    $responseData = json_decode($result, true);
    if ($responseData && isset($responseData['status'])) {
        if ($responseData['status'] === 'ok') {
            echo "✅ <strong>SUCCESS!</strong> API is working<br>";
            echo "📊 Transaction Count: " . ($responseData['count'] ?? 'N/A') . "<br>";
            echo "🔍 Driver ID: " . ($responseData['driverId'] ?? 'N/A') . "<br>";
            
            if (isset($responseData['transactions']) && is_array($responseData['transactions'])) {
                echo "<h4>📋 Transactions Found:</h4>";
                if (count($responseData['transactions']) > 0) {
                    echo "<table border='1' style='border-collapse: collapse; width: 100%;'>";
                    echo "<tr><th>ID</th><th>Type</th><th>Amount</th><th>Description</th><th>Date</th><th>Balance</th></tr>";
                    foreach ($responseData['transactions'] as $transaction) {
                        echo "<tr>";
                        echo "<td>" . ($transaction['id'] ?? 'N/A') . "</td>";
                        echo "<td>" . ($transaction['type'] ?? 'N/A') . "</td>";
                        echo "<td>₹" . ($transaction['amount'] ?? 'N/A') . "</td>";
                        echo "<td>" . ($transaction['description'] ?? 'N/A') . "</td>";
                        echo "<td>" . ($transaction['created_at'] ?? 'N/A') . "</td>";
                        echo "<td>₹" . ($transaction['running_balance'] ?? 'N/A') . "</td>";
                        echo "</tr>";
                    }
                    echo "</table>";
                } else {
                    echo "⚠️ No transactions found in database<br>";
                }
            } else {
                echo "⚠️ No transactions array in response<br>";
            }
        } else {
            echo "⚠️ API responded with error: " . ($responseData['error'] ?? 'Unknown error') . "<br>";
        }
    } else {
        echo "⚠️ Response is not valid JSON or missing status field<br>";
    }
}

echo "<h3>3. Direct Database Check:</h3>";

// Also check database directly
try {
    require_once __DIR__ . '/common.php';
    
    $conn = getDbConnection();
    
    // Check if table exists
    $tableCheck = $conn->query("SHOW TABLES LIKE 'advance_transactions'");
    if ($tableCheck->num_rows > 0) {
        echo "✅ advance_transactions table exists<br>";
        
        // Count total transactions
        $countResult = $conn->query("SELECT COUNT(*) as total FROM advance_transactions");
        $totalCount = $countResult->fetch_assoc()['total'];
        echo "📊 Total transactions in database: $totalCount<br>";
        
        // Check transactions for driver 169
        $driverResult = $conn->query("SELECT COUNT(*) as driver_count FROM advance_transactions WHERE driver_id = 169");
        $driverCount = $driverResult->fetch_assoc()['driver_count'];
        echo "🔍 Transactions for driver 169: $driverCount<br>";
        
        // Show recent transactions
        $recentResult = $conn->query("SELECT * FROM advance_transactions WHERE driver_id = 169 ORDER BY created_at DESC LIMIT 5");
        if ($recentResult->num_rows > 0) {
            echo "<h4>📋 Recent Transactions for Driver 169:</h4>";
            echo "<table border='1' style='border-collapse: collapse; width: 100%;'>";
            echo "<tr><th>ID</th><th>Type</th><th>Amount</th><th>Description</th><th>Date</th></tr>";
            while ($row = $recentResult->fetch_assoc()) {
                echo "<tr>";
                echo "<td>" . $row['id'] . "</td>";
                echo "<td>" . $row['type'] . "</td>";
                echo "<td>₹" . $row['amount'] . "</td>";
                echo "<td>" . $row['description'] . "</td>";
                echo "<td>" . $row['created_at'] . "</td>";
                echo "</tr>";
            }
            echo "</table>";
        } else {
            echo "⚠️ No transactions found for driver 169<br>";
        }
        
    } else {
        echo "❌ advance_transactions table does not exist<br>";
    }
    
    $conn->close();
    
} catch (Exception $e) {
    echo "❌ Database error: " . $e->getMessage() . "<br>";
}

echo "<h3>4. Summary:</h3>";
echo "This test will show if:<br>";
echo "• The API is working correctly<br>";
echo "• Transactions exist in the database<br>";
echo "• The Flutter app should be able to load them<br>";
?>
