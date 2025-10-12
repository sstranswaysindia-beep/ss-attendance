<?php
require_once 'common.php';

// Handle both GET and POST requests
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $data = apiRequireJson();
    $userId = $data['userId'] ?? '';
    $driverId = $data['driverId'] ?? null;
} else {
    // Handle GET request
    $userId = $_GET['userId'] ?? '';
    $driverId = $_GET['driverId'] ?? null;
}

if (empty($userId)) {
    echo "<p style='color: red;'>Missing userId parameter</p>";
    exit;
}

try {
    echo "<h2>Open Attendance Debug for User ID: $userId</h2>";
    
    // Check if user exists in drivers table
    $driverExists = false;
    if ($driverId && !empty($driverId)) {
        $driverStmt = $conn->prepare("SELECT id, full_name FROM drivers WHERE id = ? LIMIT 1");
        $driverStmt->bind_param("s", $driverId);
        $driverStmt->execute();
        $driverResult = $driverStmt->get_result();
        if ($driverResult->num_rows > 0) {
            $driverExists = true;
            $driverData = $driverResult->fetch_assoc();
            echo "<h3>Driver Data</h3>";
            echo "<p>Driver ID: {$driverData['id']}</p>";
            echo "<p>Driver Name: {$driverData['full_name']}</p>";
        }
        $driverStmt->close();
    }
    
    // Check if user exists in users table
    $userStmt = $conn->prepare("SELECT id, username, full_name, role, driver_id FROM users WHERE id = ? LIMIT 1");
    $userStmt->bind_param("s", $userId);
    $userStmt->execute();
    $userResult = $userStmt->get_result();
    if ($userResult->num_rows > 0) {
        $userData = $userResult->fetch_assoc();
        echo "<h3>User Data</h3>";
        echo "<p>User ID: {$userData['id']}</p>";
        echo "<p>Username: {$userData['username']}</p>";
        echo "<p>Full Name: {$userData['full_name']}</p>";
        echo "<p>Role: {$userData['role']}</p>";
        echo "<p>Driver ID: " . ($userData['driver_id'] ?? 'NULL') . "</p>";
    }
    $userStmt->close();
    
    echo "<h3>Open Attendance Records Check</h3>";
    
    // Check for open attendance records using driver_id
    if ($driverExists) {
        echo "<h4>Checking by driver_id = $driverId</h4>";
        $openStmt = $conn->prepare("
            SELECT id, driver_id, plant_id, vehicle_id, assignment_id, 
                   in_time, out_time, notes, approval_status, source
            FROM attendance 
            WHERE driver_id = ? AND out_time IS NULL 
            ORDER BY in_time DESC 
            LIMIT 5
        ");
        $openStmt->bind_param("i", $driverId);
        $openStmt->execute();
        $openResult = $openStmt->get_result();
        
        if ($openResult->num_rows > 0) {
            echo "<p style='color: red; font-weight: bold;'>❌ FOUND OPEN ATTENDANCE RECORDS:</p>";
            echo "<table border='1' style='border-collapse: collapse;'>";
            echo "<tr><th>ID</th><th>Driver ID</th><th>Plant ID</th><th>Vehicle ID</th><th>Assignment ID</th><th>In Time</th><th>Out Time</th><th>Notes</th><th>Status</th><th>Source</th></tr>";
            
            while ($row = $openResult->fetch_assoc()) {
                echo "<tr>";
                echo "<td>{$row['id']}</td>";
                echo "<td>{$row['driver_id']}</td>";
                echo "<td>{$row['plant_id']}</td>";
                echo "<td>{$row['vehicle_id']}</td>";
                echo "<td>{$row['assignment_id']}</td>";
                echo "<td>{$row['in_time']}</td>";
                echo "<td>" . ($row['out_time'] ?? 'NULL') . "</td>";
                echo "<td>" . ($row['notes'] ?? 'NULL') . "</td>";
                echo "<td>{$row['approval_status']}</td>";
                echo "<td>{$row['source']}</td>";
                echo "</tr>";
            }
            echo "</table>";
        } else {
            echo "<p style='color: green;'>✅ No open attendance records found by driver_id</p>";
        }
        $openStmt->close();
    }
    
    // Check for open attendance records using NULL driver_id and user_id in notes
    echo "<h4>Checking by NULL driver_id and user_id in notes</h4>";
    $supervisorPattern = "SUPERVISOR_USER_ID:$userId%";
    $supervisorStmt = $conn->prepare("
        SELECT id, driver_id, plant_id, vehicle_id, assignment_id, 
               in_time, out_time, notes, approval_status, source
        FROM attendance 
        WHERE driver_id IS NULL AND notes LIKE ? AND out_time IS NULL 
        ORDER BY in_time DESC 
        LIMIT 5
    ");
    $supervisorStmt->bind_param("s", $supervisorPattern);
    $supervisorStmt->execute();
    $supervisorResult = $supervisorStmt->get_result();
    
    if ($supervisorResult->num_rows > 0) {
        echo "<p style='color: red; font-weight: bold;'>❌ FOUND OPEN ATTENDANCE RECORDS FOR SUPERVISOR:</p>";
        echo "<table border='1' style='border-collapse: collapse;'>";
        echo "<tr><th>ID</th><th>Driver ID</th><th>Plant ID</th><th>Vehicle ID</th><th>Assignment ID</th><th>In Time</th><th>Out Time</th><th>Notes</th><th>Status</th><th>Source</th></tr>";
        
        while ($row = $supervisorResult->fetch_assoc()) {
            echo "<tr>";
            echo "<td>{$row['id']}</td>";
            echo "<td>" . ($row['driver_id'] ?? 'NULL') . "</td>";
            echo "<td>{$row['plant_id']}</td>";
            echo "<td>{$row['vehicle_id']}</td>";
            echo "<td>{$row['assignment_id']}</td>";
            echo "<td>{$row['in_time']}</td>";
            echo "<td>" . ($row['out_time'] ?? 'NULL') . "</td>";
            echo "<td>" . ($row['notes'] ?? 'NULL') . "</td>";
            echo "<td>{$row['approval_status']}</td>";
            echo "<td>{$row['source']}</td>";
            echo "</tr>";
        }
        echo "</table>";
    } else {
        echo "<p style='color: green;'>✅ No open attendance records found for supervisor</p>";
    }
    $supervisorStmt->close();
    
    // Show recent attendance records (last 10)
    echo "<h3>Recent Attendance Records (Last 10)</h3>";
    $recentStmt = $conn->prepare("
        SELECT id, driver_id, plant_id, vehicle_id, assignment_id, 
               in_time, out_time, notes, approval_status, source
        FROM attendance 
        WHERE (driver_id = ? OR (driver_id IS NULL AND notes LIKE ?))
        ORDER BY in_time DESC 
        LIMIT 10
    ");
    $recentStmt->bind_param("is", $driverId, $supervisorPattern);
    $recentStmt->execute();
    $recentResult = $recentStmt->get_result();
    
    if ($recentResult->num_rows > 0) {
        echo "<table border='1' style='border-collapse: collapse;'>";
        echo "<tr><th>ID</th><th>Driver ID</th><th>Plant ID</th><th>In Time</th><th>Out Time</th><th>Notes</th><th>Status</th><th>Source</th></tr>";
        
        while ($row = $recentResult->fetch_assoc()) {
            $rowColor = ($row['out_time'] == null) ? "style='background-color: #ffcccc;'" : "";
            echo "<tr $rowColor>";
            echo "<td>{$row['id']}</td>";
            echo "<td>" . ($row['driver_id'] ?? 'NULL') . "</td>";
            echo "<td>{$row['plant_id']}</td>";
            echo "<td>{$row['in_time']}</td>";
            echo "<td>" . ($row['out_time'] ?? 'NULL') . "</td>";
            echo "<td>" . ($row['notes'] ?? 'NULL') . "</td>";
            echo "<td>{$row['approval_status']}</td>";
            echo "<td>{$row['source']}</td>";
            echo "</tr>";
        }
        echo "</table>";
        echo "<p><em>Note: Rows with red background have open attendance (no out_time)</em></p>";
    } else {
        echo "<p>No recent attendance records found</p>";
    }
    $recentStmt->close();
    
} catch (Exception $e) {
    echo "<p style='color: red;'>Error: " . $e->getMessage() . "</p>";
    error_log("Open attendance debug error: " . $e->getMessage());
}
?>
