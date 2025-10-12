<?php
require_once 'common.php';

header('Content-Type: text/html; charset=utf-8');

// Get user ID from request
$userId = $_GET['userId'] ?? $_POST['userId'] ?? '4'; // Default to vedpal

echo "<h2>Test Supervisor Attendance (Fixed Version)</h2>";
echo "<p>Testing attendance for supervisor without driver_id: User ID $userId</p>";

try {
    // Test 1: Check user data
    echo "<h3>Test 1: User Data</h3>";
    $userStmt = $conn->prepare("SELECT id, username, full_name, role, driver_id FROM users WHERE id = ? LIMIT 1");
    $userStmt->bind_param("s", $userId);
    $userStmt->execute();
    $userResult = $userStmt->get_result();
    $user = $userResult->fetch_assoc();
    $userStmt->close();
    
    if (!$user) {
        echo "<p>❌ User not found</p>";
        exit;
    }
    
    echo "<table border='1' style='border-collapse: collapse;'>";
    echo "<tr><th>Field</th><th>Value</th></tr>";
    foreach ($user as $field => $value) {
        echo "<tr>";
        echo "<td>" . htmlspecialchars($field) . "</td>";
        echo "<td>" . htmlspecialchars($value ?? 'NULL') . "</td>";
        echo "</tr>";
    }
    echo "</table>";
    
    if ($user['role'] !== 'supervisor') {
        echo "<p>⚠️ User is not a supervisor: " . $user['role'] . "</p>";
    }
    
    if (!empty($user['driver_id'])) {
        echo "<p>✅ User has driver_id: " . $user['driver_id'] . "</p>";
    } else {
        echo "<p>⚠️ User does NOT have driver_id (this is what we're testing)</p>";
    }
    
    // Test 2: Check attendance table structure
    echo "<h3>Test 2: Attendance Table Structure</h3>";
    $structureStmt = $conn->prepare("DESCRIBE attendance");
    $structureStmt->execute();
    $structure = $structureStmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $structureStmt->close();
    
    $driverIdField = array_filter($structure, function($field) {
        return $field['Field'] === 'driver_id';
    });
    
    if (!empty($driverIdField)) {
        $driverIdField = array_values($driverIdField)[0];
        echo "<p>driver_id column allows NULL: <strong>" . ($driverIdField['Null'] === 'YES' ? 'YES ✅' : 'NO ❌') . "</strong></p>";
    }
    
    // Test 3: Check foreign key constraints
    echo "<h3>Test 3: Foreign Key Constraints</h3>";
    $constraintStmt = $conn->prepare("
        SELECT CONSTRAINT_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME 
        FROM information_schema.KEY_COLUMN_USAGE 
        WHERE TABLE_SCHEMA = DATABASE() 
        AND TABLE_NAME = 'attendance' 
        AND REFERENCED_TABLE_NAME IS NOT NULL
        AND COLUMN_NAME = 'driver_id'
    ");
    $constraintStmt->execute();
    $constraints = $constraintStmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $constraintStmt->close();
    
    if (empty($constraints)) {
        echo "<p>✅ No foreign key constraint on driver_id column</p>";
    } else {
        echo "<p>⚠️ Foreign key constraint still exists:</p>";
        echo "<ul>";
        foreach ($constraints as $constraint) {
            echo "<li>" . $constraint['CONSTRAINT_NAME'] . " -> " . $constraint['REFERENCED_TABLE_NAME'] . "</li>";
        }
        echo "</ul>";
    }
    
    // Test 4: Simulate attendance submission
    echo "<h3>Test 4: Simulate Attendance Submission</h3>";
    
    // Check if user exists in drivers table
    $driverStmt = $conn->prepare('SELECT id FROM drivers WHERE id = ? LIMIT 1');
    $driverStmt->bind_param('i', $userId);
    $driverStmt->execute();
    $driverExists = $driverStmt->get_result()->fetch_assoc();
    $driverStmt->close();
    
    echo "<p>User exists in drivers table: " . ($driverExists ? 'YES ✅' : 'NO ❌') . "</p>";
    
    // Check if user exists in users table (for supervisors)
    $userStmt2 = $conn->prepare('SELECT id FROM users WHERE id = ? AND role = "supervisor" LIMIT 1');
    $userStmt2->bind_param('i', $userId);
    $userStmt2->execute();
    $userExists = $userStmt2->get_result()->fetch_assoc();
    $userStmt2->close();
    
    echo "<p>User exists in users table as supervisor: " . ($userExists ? 'YES ✅' : 'NO ❌') . "</p>";
    
    // Determine what driver_id to use
    $attendanceDriverId = $driverExists ? $userId : null;
    echo "<p>Attendance driver_id will be: " . ($attendanceDriverId ?? 'NULL') . "</p>";
    
    // Test 5: Check if attendance table can accept NULL driver_id
    echo "<h3>Test 5: Test NULL driver_id Insert</h3>";
    
    // Create a test record (we'll delete it immediately)
    $testStmt = $conn->prepare("
        INSERT INTO attendance (
            driver_id, plant_id, vehicle_id, assignment_id, in_time, 
            in_photo_url, notes, source, approval_status, pending_sync
        ) VALUES (NULL, 1, 1, NULL, NOW(), 'test.jpg', 'Test', 'test', 'Pending', 0)
    ");
    
    if ($testStmt->execute()) {
        $testId = $conn->insert_id;
        echo "<p>✅ Successfully inserted test record with NULL driver_id (ID: $testId)</p>";
        
        // Delete the test record
        $deleteStmt = $conn->prepare("DELETE FROM attendance WHERE id = ?");
        $deleteStmt->bind_param('i', $testId);
        $deleteStmt->execute();
        $deleteStmt->close();
        echo "<p>✅ Test record deleted</p>";
    } else {
        echo "<p>❌ Failed to insert test record with NULL driver_id: " . $conn->error . "</p>";
    }
    $testStmt->close();
    
    // Test 6: Show current attendance records for this user
    echo "<h3>Test 6: Current Attendance Records</h3>";
    $attendanceStmt = $conn->prepare("
        SELECT id, driver_id, in_time, out_time, approval_status, source 
        FROM attendance 
        WHERE driver_id = ? OR driver_id IS NULL
        ORDER BY in_time DESC 
        LIMIT 5
    ");
    $attendanceStmt->bind_param('i', $userId);
    $attendanceStmt->execute();
    $attendanceRecords = $attendanceStmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $attendanceStmt->close();
    
    if (empty($attendanceRecords)) {
        echo "<p>No attendance records found for this user</p>";
    } else {
        echo "<table border='1' style='border-collapse: collapse;'>";
        echo "<tr><th>ID</th><th>Driver ID</th><th>In Time</th><th>Out Time</th><th>Status</th><th>Source</th></tr>";
        foreach ($attendanceRecords as $record) {
            echo "<tr>";
            echo "<td>" . $record['id'] . "</td>";
            echo "<td>" . ($record['driver_id'] ?? 'NULL') . "</td>";
            echo "<td>" . $record['in_time'] . "</td>";
            echo "<td>" . ($record['out_time'] ?? 'NULL') . "</td>";
            echo "<td>" . $record['approval_status'] . "</td>";
            echo "<td>" . $record['source'] . "</td>";
            echo "</tr>";
        }
        echo "</table>";
    }
    
    echo "<h3>🎯 Summary</h3>";
    echo "<ul>";
    echo "<li>User Role: " . $user['role'] . "</li>";
    echo "<li>Has Driver ID: " . (!empty($user['driver_id']) ? 'YES' : 'NO') . "</li>";
    echo "<li>Driver ID Column Allows NULL: " . ($driverIdField['Null'] === 'YES' ? 'YES' : 'NO') . "</li>";
    echo "<li>Foreign Key Constraint: " . (empty($constraints) ? 'REMOVED' : 'STILL EXISTS') . "</li>";
    echo "<li>Test Insert with NULL: " . ($testStmt ? 'SUCCESS' : 'FAILED') . "</li>";
    echo "</ul>";
    
    if ($driverIdField['Null'] === 'YES' && empty($constraints)) {
        echo "<h3 style='color: green;'>✅ Attendance should work for supervisors without driver_id!</h3>";
        echo "<p>The database is properly configured to handle NULL driver_id values.</p>";
    } else {
        echo "<h3 style='color: red;'>❌ Attendance may still fail</h3>";
        echo "<p>Database configuration issues need to be resolved.</p>";
    }
    
} catch (Exception $e) {
    echo "<h3 style='color: red;'>❌ Error</h3>";
    echo "<p>Error: " . $e->getMessage() . "</p>";
}

echo "<h3>📝 Next Steps:</h3>";
echo "<ol>";
echo "<li>If database issues are found, run <a href='fix_attendance_foreign_key.php'>fix_attendance_foreign_key.php</a></li>";
echo "<li>Test actual attendance submission from the mobile app</li>";
echo "<li>Debug profile photo issues separately</li>";
echo "</ol>";
?>
