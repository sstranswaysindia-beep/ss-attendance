<?php
require_once 'common.php';

header('Content-Type: text/html; charset=utf-8');

echo "<h2>Advance and Salary Tables Setup (Simple Version)</h2>";
echo "<p>This script creates the advance tables without foreign key constraints for easier testing.</p>";

try {
    // Create advance_transactions table without foreign key constraint
    $createTableStmt = $conn->prepare("
        CREATE TABLE IF NOT EXISTS advance_transactions (
            id INT(11) NOT NULL AUTO_INCREMENT,
            driver_id INT(11) NOT NULL,
            type ENUM('advance_received', 'expense') NOT NULL,
            amount DECIMAL(10,2) NOT NULL,
            description TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            KEY idx_driver_id (driver_id),
            KEY idx_type (type),
            KEY idx_created_at (created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ");
    
    if ($createTableStmt->execute()) {
        echo "<p>✅ Advance transactions table created successfully (without foreign key constraint)</p>";
    } else {
        echo "<p>❌ Failed to create table: " . $createTableStmt->error . "</p>";
    }
    $createTableStmt->close();
    
    // Insert sample data for testing (using driver_id = 1)
    echo "<h3>Inserting Sample Data (Driver ID: 1)</h3>";
    
    $sampleData = [
        [1, 'advance_received', 5000.00, 'Initial advance for trip expenses'],
        [1, 'expense', 2400.00, 'Fuel expense - patrol 1021'],
        [1, 'expense', 1850.00, 'Battery replacement - vikas bhai'],
        [1, 'advance_received', 1000.00, 'Additional advance - Dev Advance Dehradun'],
        [1, 'expense', 2000.00, 'Police fine - 5447'],
    ];
    
    $insertStmt = $conn->prepare("
        INSERT INTO advance_transactions (driver_id, type, amount, description)
        VALUES (?, ?, ?, ?)
    ");
    
    foreach ($sampleData as $data) {
        $insertStmt->bind_param('isds', $data[0], $data[1], $data[2], $data[3]);
        if ($insertStmt->execute()) {
            echo "<p>✅ Sample transaction added: {$data[1]} - ₹{$data[2]}</p>";
        } else {
            echo "<p>❌ Failed to add sample transaction: " . $insertStmt->error . "</p>";
        }
    }
    $insertStmt->close();
    
    // Calculate expected balance
    $balanceStmt = $conn->prepare("
        SELECT 
            COALESCE(SUM(CASE WHEN type = 'advance_received' THEN amount ELSE 0 END), 0) -
            COALESCE(SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END), 0) as balance
        FROM advance_transactions 
        WHERE driver_id = 1
    ");
    $balanceStmt->execute();
    $balance = $balanceStmt->get_result()->fetch_assoc()['balance'] ?? 0;
    $balanceStmt->close();
    
    echo "<h3>📊 Expected Balance for Driver ID 1:</h3>";
    echo "<p>Current Balance: <strong>₹" . number_format($balance, 2) . "</strong></p>";
    
    echo "<h3>✅ Setup Complete!</h3>";
    echo "<p>The advance and salary tracking system is now ready to use.</p>";
    echo "<p><strong>Note:</strong> This version doesn't use foreign key constraints, making it easier to test.</p>";
    
} catch (Exception $e) {
    echo "<h3 style='color: red;'>❌ Error</h3>";
    echo "<p>Error: " . $e->getMessage() . "</p>";
}

echo "<h3>📝 Next Steps:</h3>";
echo "<ol>";
echo "<li>Test the Advance & Salary feature in the app</li>";
echo "<li>Login with a user that has driver_id = 1</li>";
echo "<li>Go to 'Advance & Salary' from the dashboard</li>";
echo "<li>Verify the sample data is displayed correctly</li>";
echo "</ol>";
?>
