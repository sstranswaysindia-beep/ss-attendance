<?php
require_once 'common.php';

try {
    echo "<h2>Quick Fix for Attendance Record ID: 46</h2>";
    
    // First, let's check the current status
    $checkStmt = $conn->prepare("
        SELECT id, driver_id, plant_id, vehicle_id, assignment_id, 
               in_time, out_time, notes, approval_status, source
        FROM attendance 
        WHERE id = 46
    ");
    $checkStmt->execute();
    $result = $checkStmt->get_result();
    
    if ($result->num_rows > 0) {
        $row = $result->fetch_assoc();
        echo "<h3>Current Status of Record ID: 46</h3>";
        echo "<table border='1' style='border-collapse: collapse;'>";
        echo "<tr><th>ID</th><th>Driver ID</th><th>Plant ID</th><th>Vehicle ID</th><th>Assignment ID</th><th>In Time</th><th>Out Time</th><th>Notes</th><th>Status</th><th>Source</th></tr>";
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
        echo "</table>";
        
        // Check if it's still open (no out_time)
        if ($row['out_time'] == null) {
            echo "<h3>🔧 Fixing the Record...</h3>";
            
            // Option 1: Check out the record
            $updateStmt = $conn->prepare("
                UPDATE attendance 
                SET out_time = NOW(), 
                    notes = CONCAT(IFNULL(notes, ''), ' [AUTO CHECKED OUT - QUICK FIX]')
                WHERE id = 46 AND out_time IS NULL
            ");
            $updateStmt->execute();
            
            if ($updateStmt->affected_rows > 0) {
                echo "<p style='color: green; font-weight: bold; font-size: 18px;'>✅ SUCCESS! Attendance record ID: 46 has been checked out!</p>";
                echo "<p>Out time set to: " . date('Y-m-d H:i:s') . "</p>";
                
                // Show the updated record
                $checkStmt->execute();
                $result = $checkStmt->get_result();
                $row = $result->fetch_assoc();
                
                echo "<h3>Updated Record</h3>";
                echo "<table border='1' style='border-collapse: collapse;'>";
                echo "<tr><th>ID</th><th>Driver ID</th><th>Plant ID</th><th>Vehicle ID</th><th>Assignment ID</th><th>In Time</th><th>Out Time</th><th>Notes</th><th>Status</th><th>Source</th></tr>";
                echo "<tr>";
                echo "<td>{$row['id']}</td>";
                echo "<td>" . ($row['driver_id'] ?? 'NULL') . "</td>";
                echo "<td>{$row['plant_id']}</td>";
                echo "<td>{$row['vehicle_id']}</td>";
                echo "<td>{$row['assignment_id']}</td>";
                echo "<td>{$row['in_time']}</td>";
                echo "<td style='background-color: #90EE90;'>{$row['out_time']}</td>";
                echo "<td>{$row['notes']}</td>";
                echo "<td>{$row['approval_status']}</td>";
                echo "<td>{$row['source']}</td>";
                echo "</tr>";
                echo "</table>";
                
                echo "<h3>🎉 RESULT</h3>";
                echo "<p style='color: green; font-weight: bold;'>User ID 4 (vedpal) can now check in again!</p>";
                echo "<p>The attendance system should work normally now.</p>";
                
            } else {
                echo "<p style='color: red;'>❌ No records were updated. Record may have been already fixed.</p>";
            }
            $updateStmt->close();
        } else {
            echo "<p style='color: green;'>✅ Record ID: 46 is already checked out. No action needed.</p>";
        }
    } else {
        echo "<p style='color: red;'>❌ Record ID: 46 not found.</p>";
    }
    
    $checkStmt->close();
    
} catch (Exception $e) {
    echo "<p style='color: red;'>Error: " . $e->getMessage() . "</p>";
    error_log("Quick fix attendance error: " . $e->getMessage());
}
?>
