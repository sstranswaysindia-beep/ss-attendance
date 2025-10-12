<?php
require_once 'common.php';

header('Content-Type: text/html; charset=utf-8');

echo "<h2>All Users in Database</h2>";

try {
    // Get all users
    $stmt = $conn->prepare("
        SELECT id, username, full_name, role, driver_id, profile_photo, created_at 
        FROM users 
        ORDER BY id ASC
    ");
    
    if (!$stmt) {
        throw new Exception("Failed to prepare statement: " . $conn->error);
    }
    
    $stmt->execute();
    $result = $stmt->get_result();
    $users = [];
    
    while ($row = $result->fetch_assoc()) {
        $users[] = $row;
    }
    $stmt->close();
    
    echo "<p>Total users found: " . count($users) . "</p>";
    
    if (empty($users)) {
        echo "<p>❌ No users found in database</p>";
    } else {
        echo "<table border='1' style='border-collapse: collapse; width: 100%;'>";
        echo "<tr>";
        echo "<th>ID</th>";
        echo "<th>Username</th>";
        echo "<th>Full Name</th>";
        echo "<th>Role</th>";
        echo "<th>Driver ID</th>";
        echo "<th>Profile Photo</th>";
        echo "<th>Created</th>";
        echo "<th>Actions</th>";
        echo "</tr>";
        
        foreach ($users as $user) {
            $hasDriverId = !empty($user['driver_id']) ? "✅" : "❌";
            $hasProfilePhoto = !empty($user['profile_photo']) ? "✅" : "❌";
            
            echo "<tr>";
            echo "<td>" . htmlspecialchars($user['id']) . "</td>";
            echo "<td>" . htmlspecialchars($user['username']) . "</td>";
            echo "<td>" . htmlspecialchars($user['full_name'] ?? 'N/A') . "</td>";
            echo "<td>" . htmlspecialchars($user['role']) . "</td>";
            echo "<td>$hasDriverId " . htmlspecialchars($user['driver_id'] ?? 'NULL') . "</td>";
            echo "<td>$hasProfilePhoto " . htmlspecialchars(substr($user['profile_photo'] ?? 'NULL', 0, 50)) . "</td>";
            echo "<td>" . htmlspecialchars($user['created_at']) . "</td>";
            echo "<td>";
            echo "<a href='debug_profile_photo.php?userId=" . $user['id'] . "' target='_blank'>Debug Profile</a> | ";
            echo "<a href='test_supervisor_attendance.php?userId=" . $user['id'] . "' target='_blank'>Test Attendance</a>";
            echo "</td>";
            echo "</tr>";
        }
        echo "</table>";
        
        // Show supervisors without driver_id specifically
        $supervisorsWithoutDriverId = array_filter($users, function($user) {
            return $user['role'] === 'supervisor' && (empty($user['driver_id']) || $user['driver_id'] == 0);
        });
        
        if (!empty($supervisorsWithoutDriverId)) {
            echo "<h3>⚠️ Supervisors Without Driver ID (" . count($supervisorsWithoutDriverId) . "):</h3>";
            echo "<ul>";
            foreach ($supervisorsWithoutDriverId as $supervisor) {
                echo "<li>ID: " . $supervisor['id'] . " - " . $supervisor['username'] . " (" . ($supervisor['full_name'] ?? 'No name') . ")</li>";
            }
            echo "</ul>";
            echo "<p><a href='fix_supervisor_driver_records.php' style='background: #ff6b6b; color: white; padding: 10px; text-decoration: none; border-radius: 5px;'>🚨 FIX THESE SUPERVISORS</a></p>";
        }
    }
    
    // Show database connection info
    echo "<h3>Database Connection Info:</h3>";
    echo "<p>Host: " . $conn->host_info . "</p>";
    echo "<p>Server Info: " . $conn->server_info . "</p>";
    echo "<p>Database: " . $conn->get_server_info() . "</p>";
    
} catch (Exception $e) {
    echo "<h3 style='color: red;'>❌ Error</h3>";
    echo "<p>Error: " . $e->getMessage() . "</p>";
}

echo "<h3>📝 Instructions</h3>";
echo "<ol>";
echo "<li>Find a supervisor user ID from the table above</li>";
echo "<li>Use that ID to test: <code>debug_profile_photo.php?userId=ACTUAL_USER_ID</code></li>";
echo "<li>If supervisors are missing driver_id, run the fix script first</li>";
echo "</ol>";
?>
