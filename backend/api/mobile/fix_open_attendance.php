<?php
require_once 'common.php';

// Handle both GET and POST requests
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Check if it's JSON data or form data
    $contentType = $_SERVER['CONTENT_TYPE'] ?? '';
    if (strpos($contentType, 'application/json') !== false) {
        $data = apiRequireJson();
        $userId = $data['userId'] ?? '';
        $attendanceId = $data['attendanceId'] ?? null;
        $action = $data['action'] ?? 'check_out';
    } else {
        // Handle form data
        $userId = $_POST['userId'] ?? '';
        $attendanceId = $_POST['attendanceId'] ?? null;
        $action = $_POST['action'] ?? 'check_out';
    }
} else {
    // Handle GET request
    $userId = $_GET['userId'] ?? '';
    $attendanceId = $_GET['attendanceId'] ?? null;
    $action = $_GET['action'] ?? 'check_out';
}

if (empty($userId)) {
    echo "<p style='color: red;'>Missing userId parameter</p>";
    exit;
}

try {
    echo "<h2>Fix Open Attendance for User ID: $userId</h2>";
    
    // Find open attendance records
    $driverId = $data['driverId'] ?? null;
    
    if ($driverId && !empty($driverId)) {
        // Check for driver with driver_id
        $stmt = $conn->prepare("
            SELECT id, driver_id, plant_id, vehicle_id, assignment_id, 
                   in_time, out_time, notes, approval_status, source
            FROM attendance 
            WHERE driver_id = ? AND out_time IS NULL 
            ORDER BY in_time DESC 
            LIMIT 10
        ");
        $stmt->bind_param("i", $driverId);
        $stmt->execute();
        $result = $stmt->get_result();
        
        echo "<h3>Open Attendance Records for Driver ID: $driverId</h3>";
        if ($result->num_rows > 0) {
            echo "<table border='1' style='border-collapse: collapse;'>";
            echo "<tr><th>ID</th><th>Driver ID</th><th>Plant ID</th><th>Vehicle ID</th><th>Assignment ID</th><th>In Time</th><th>Out Time</th><th>Notes</th><th>Status</th><th>Source</th><th>Action</th></tr>";
            
            while ($row = $result->fetch_assoc()) {
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
                echo "<td>";
                echo "<button onclick='fixAttendance({$row['id']}, \"check_out\")'>Check Out</button> ";
                echo "<button onclick='fixAttendance({$row['id']}, \"delete\")' style='background: red; color: white;'>Delete</button>";
                echo "</td>";
                echo "</tr>";
            }
            echo "</table>";
        } else {
            echo "<p style='color: green;'>✅ No open attendance records found for driver</p>";
        }
        $stmt->close();
    }
    
    // Check for supervisor without driver_id
    $supervisorPattern = "SUPERVISOR_USER_ID:$userId%";
    $stmt = $conn->prepare("
        SELECT id, driver_id, plant_id, vehicle_id, assignment_id, 
               in_time, out_time, notes, approval_status, source
        FROM attendance 
        WHERE driver_id IS NULL AND notes LIKE ? AND out_time IS NULL 
        ORDER BY in_time DESC 
        LIMIT 10
    ");
    $stmt->bind_param("s", $supervisorPattern);
    $stmt->execute();
    $result = $stmt->get_result();
    
    echo "<h3>Open Attendance Records for Supervisor User ID: $userId</h3>";
    if ($result->num_rows > 0) {
        echo "<table border='1' style='border-collapse: collapse;'>";
        echo "<tr><th>ID</th><th>Driver ID</th><th>Plant ID</th><th>Vehicle ID</th><th>Assignment ID</th><th>In Time</th><th>Out Time</th><th>Notes</th><th>Status</th><th>Source</th><th>Action</th></tr>";
        
        while ($row = $result->fetch_assoc()) {
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
            echo "<td>";
            echo "<button onclick='fixAttendance({$row['id']}, \"check_out\")'>Check Out</button> ";
            echo "<button onclick='fixAttendance({$row['id']}, \"delete\")' style='background: red; color: white;'>Delete</button>";
            echo "</td>";
            echo "</tr>";
        }
        echo "</table>";
    } else {
        echo "<p style='color: green;'>✅ No open attendance records found for supervisor</p>";
    }
    $stmt->close();
    
    // Handle specific action if attendance ID is provided
    if ($attendanceId && $action) {
        echo "<h3>Processing Action: $action for Attendance ID: $attendanceId</h3>";
        
        if ($action === 'check_out') {
            $updateStmt = $conn->prepare("
                UPDATE attendance 
                SET out_time = NOW(), 
                    approval_status = 'Approved',
                    notes = CONCAT(IFNULL(notes, ''), ' [AUTO CHECKED OUT - FIXED]')
                WHERE id = ? AND out_time IS NULL
            ");
            $updateStmt->bind_param("i", $attendanceId);
            $updateStmt->execute();
            
            if ($updateStmt->affected_rows > 0) {
                echo "<p style='color: green; font-weight: bold;'>✅ Successfully checked out attendance record ID: $attendanceId</p>";
            } else {
                echo "<p style='color: red; font-weight: bold;'>❌ No records updated. Record may already be checked out or doesn't exist.</p>";
            }
            $updateStmt->close();
        } elseif ($action === 'delete') {
            $deleteStmt = $conn->prepare("DELETE FROM attendance WHERE id = ? AND out_time IS NULL");
            $deleteStmt->bind_param("i", $attendanceId);
            $deleteStmt->execute();
            
            if ($deleteStmt->affected_rows > 0) {
                echo "<p style='color: green; font-weight: bold;'>✅ Successfully deleted attendance record ID: $attendanceId</p>";
            } else {
                echo "<p style='color: red; font-weight: bold;'>❌ No records deleted. Record may already be checked out or doesn't exist.</p>";
            }
            $deleteStmt->close();
        }
    }
    
    echo "<script>
    function fixAttendance(attendanceId, action) {
        if (confirm('Are you sure you want to ' + action + ' attendance record ID: ' + attendanceId + '?')) {
            const formData = new FormData();
            formData.append('userId', '$userId');
            formData.append('attendanceId', attendanceId);
            formData.append('action', action);
            
            fetch('fix_open_attendance.php', {
                method: 'POST',
                body: formData
            })
            .then(response => response.text())
            .then(data => {
                alert('Action completed. Page will refresh.');
                location.reload();
            })
            .catch(error => {
                alert('Error: ' + error);
            });
        }
    }
    </script>";
    
} catch (Exception $e) {
    echo "<p style='color: red;'>Error: " . $e->getMessage() . "</p>";
    error_log("Fix open attendance error: " . $e->getMessage());
}
?>
