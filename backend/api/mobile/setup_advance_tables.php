<?php
require_once 'common.php';

header('Content-Type: text/html; charset=utf-8');

echo "<h2>Advance and Salary Tables Setup</h2>";
echo "<p>This script creates the necessary tables for advance and salary tracking.</p>";

try {
    // Create advance_transactions table
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
            KEY idx_created_at (created_at),
            FOREIGN KEY (driver_id) REFERENCES drivers(id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ");
    
    if ($createTableStmt->execute()) {
        echo "<p>✅ Advance transactions table created successfully</p>";
    } else {
        echo "<p>❌ Failed to create table: " . $createTableStmt->error . "</p>";
    }
    $createTableStmt->close();
    
    // Check for existing drivers and insert sample data for testing
    echo "<h3>Checking for Valid Drivers</h3>";
    
    $driverStmt = $conn->prepare("SELECT id, name FROM drivers ORDER BY id LIMIT 5");
    $driverStmt->execute();
    $drivers = $driverStmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $driverStmt->close();
    
    if (empty($drivers)) {
        echo "<p>❌ No drivers found in database. Please add drivers first.</p>";
        echo "<p>💡 You can create a driver record or use existing driver IDs.</p>";
    } else {
        echo "<p>✅ Found " . count($drivers) . " drivers:</p>";
        echo "<ul>";
        foreach ($drivers as $driver) {
            echo "<li>Driver ID: {$driver['id']} - {$driver['name']}</li>";
        }
        echo "</ul>";
        
        // Use the first available driver for sample data
        $sampleDriverId = $drivers[0]['id'];
        echo "<p>📝 Using Driver ID {$sampleDriverId} ({$drivers[0]['name']}) for sample data</p>";
        
        echo "<h3>Inserting Sample Data</h3>";
        
        $sampleData = [
            [$sampleDriverId, 'advance_received', 5000.00, 'Initial advance for trip expenses'],
            [$sampleDriverId, 'expense', 2400.00, 'Fuel expense - patrol 1021'],
            [$sampleDriverId, 'expense', 1850.00, 'Battery replacement - vikas bhai'],
            [$sampleDriverId, 'advance_received', 1000.00, 'Additional advance - Dev Advance Dehradun'],
            [$sampleDriverId, 'expense', 2000.00, 'Police fine - 5447'],
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
    }
    
    echo "<h3>✅ Setup Complete!</h3>";
    echo "<p>The advance and salary tracking system is now ready to use.</p>";
    
} catch (Exception $e) {
    echo "<h3 style='color: red;'>❌ Error</h3>";
    echo "<p>Error: " . $e->getMessage() . "</p>";
}

echo "<h3>📝 Next Steps:</h3>";
echo "<ol>";
echo "<li>Test the API endpoints with sample data</li>";
echo "<li>Implement the Flutter UI</li>";
echo "<li>Add advance tracking to driver dashboard</li>";
echo "<li>Test advance transactions</li>";
echo "</ol>";
?>
