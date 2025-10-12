<?php
require_once 'common.php';

header('Content-Type: text/html; charset=utf-8');

echo "<h2>Attendance Approval Workflow Setup</h2>";
echo "<p>This script sets up the approval workflow for supervisors without driver_id to route to HR.</p>";

try {
    // Check if approval_workflow table exists
    $checkTableStmt = $conn->prepare("
        SELECT COUNT(*) as table_exists 
        FROM information_schema.tables 
        WHERE table_schema = DATABASE() 
        AND table_name = 'attendance_approval_workflow'
    ");
    $checkTableStmt->execute();
    $tableExists = $checkTableStmt->get_result()->fetch_assoc()['table_exists'];
    $checkTableStmt->close();
    
    if (!$tableExists) {
        echo "<h3>Creating Approval Workflow Table</h3>";
        
        $createTableStmt = $conn->prepare("
            CREATE TABLE attendance_approval_workflow (
                id INT(11) NOT NULL AUTO_INCREMENT,
                user_id INT(11) NOT NULL,
                user_type ENUM('driver', 'supervisor_with_driver_id', 'supervisor_without_driver_id') NOT NULL,
                approver_user_id INT(11) NOT NULL,
                approver_role VARCHAR(50) NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY uq_user_workflow (user_id),
                KEY idx_user_type (user_type),
                KEY idx_approver (approver_user_id),
                FOREIGN KEY (approver_user_id) REFERENCES users(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ");
        
        if ($createTableStmt->execute()) {
            echo "<p>✅ Attendance approval workflow table created successfully</p>";
        } else {
            echo "<p>❌ Failed to create table: " . $createTableStmt->error . "</p>";
        }
        $createTableStmt->close();
    } else {
        echo "<p>✅ Attendance approval workflow table already exists</p>";
    }
    
    // Get HR user ID
    $hrStmt = $conn->prepare("SELECT id, username FROM users WHERE username = 'hrattendence' LIMIT 1");
    $hrStmt->execute();
    $hrUser = $hrStmt->get_result()->fetch_assoc();
    $hrStmt->close();
    
    if (!$hrUser) {
        echo "<p>❌ HR user 'hrattendence' not found</p>";
        exit;
    }
    
    echo "<p>✅ HR User found: " . $hrUser['username'] . " (ID: " . $hrUser['id'] . ")</p>";
    
    // Set up approval workflow for all supervisors
    echo "<h3>Setting Up Approval Workflow</h3>";
    
    // Get all supervisors without driver_id
    $supervisorsWithoutDriverStmt = $conn->prepare("
        SELECT id, username, full_name 
        FROM users 
        WHERE role = 'supervisor' 
        AND (driver_id IS NULL OR driver_id = 0)
    ");
    $supervisorsWithoutDriverStmt->execute();
    $supervisorsWithoutDriver = $supervisorsWithoutDriverStmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $supervisorsWithoutDriverStmt->close();
    
    echo "<p>Found " . count($supervisorsWithoutDriver) . " supervisors without driver_id:</p>";
    
    if (!empty($supervisorsWithoutDriver)) {
        echo "<table border='1' style='border-collapse: collapse;'>";
        echo "<tr><th>User ID</th><th>Username</th><th>Full Name</th><th>User Type</th><th>Approval Workflow</th></tr>";
        
        foreach ($supervisorsWithoutDriver as $supervisor) {
            echo "<tr>";
            echo "<td>" . $supervisor['id'] . "</td>";
            echo "<td>" . htmlspecialchars($supervisor['username']) . "</td>";
            echo "<td>" . htmlspecialchars($supervisor['full_name'] ?? 'N/A') . "</td>";
            echo "<td>supervisor_without_driver_id</td>";
            
            // Insert or update approval workflow
            $insertWorkflowStmt = $conn->prepare("
                INSERT INTO attendance_approval_workflow (user_id, user_type, approver_user_id, approver_role)
                VALUES (?, 'supervisor_without_driver_id', ?, 'hr')
                ON DUPLICATE KEY UPDATE 
                approver_user_id = VALUES(approver_user_id),
                approver_role = VALUES(approver_role),
                updated_at = CURRENT_TIMESTAMP
            ");
            
            if ($insertWorkflowStmt) {
                $insertWorkflowStmt->bind_param('ii', $supervisor['id'], $hrUser['id']);
                if ($insertWorkflowStmt->execute()) {
                    echo "<td style='color: green;'>✅ Routes to HR (ID: " . $hrUser['id'] . ")</td>";
                } else {
                    echo "<td style='color: red;'>❌ Failed: " . $insertWorkflowStmt->error . "</td>";
                }
                $insertWorkflowStmt->close();
            } else {
                echo "<td style='color: red;'>❌ Failed to prepare statement</td>";
            }
            
            echo "</tr>";
        }
        echo "</table>";
    }
    
    // Get all supervisors with driver_id
    $supervisorsWithDriverStmt = $conn->prepare("
        SELECT u.id, u.username, u.full_name, u.driver_id 
        FROM users u
        WHERE u.role = 'supervisor' 
        AND u.driver_id IS NOT NULL 
        AND u.driver_id > 0
    ");
    $supervisorsWithDriverStmt->execute();
    $supervisorsWithDriver = $supervisorsWithDriverStmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $supervisorsWithDriverStmt->close();
    
    echo "<p>Found " . count($supervisorsWithDriver) . " supervisors with driver_id:</p>";
    
    if (!empty($supervisorsWithDriver)) {
        echo "<table border='1' style='border-collapse: collapse;'>";
        echo "<tr><th>User ID</th><th>Username</th><th>Full Name</th><th>Driver ID</th><th>User Type</th><th>Approval Workflow</th></tr>";
        
        foreach ($supervisorsWithDriver as $supervisor) {
            echo "<tr>";
            echo "<td>" . $supervisor['id'] . "</td>";
            echo "<td>" . htmlspecialchars($supervisor['username']) . "</td>";
            echo "<td>" . htmlspecialchars($supervisor['full_name'] ?? 'N/A') . "</td>";
            echo "<td>" . $supervisor['driver_id'] . "</td>";
            echo "<td>supervisor_with_driver_id</td>";
            
            // Insert or update approval workflow
            $insertWorkflowStmt = $conn->prepare("
                INSERT INTO attendance_approval_workflow (user_id, user_type, approver_user_id, approver_role)
                VALUES (?, 'supervisor_with_driver_id', ?, 'hr')
                ON DUPLICATE KEY UPDATE 
                approver_user_id = VALUES(approver_user_id),
                approver_role = VALUES(approver_role),
                updated_at = CURRENT_TIMESTAMP
            ");
            
            if ($insertWorkflowStmt) {
                $insertWorkflowStmt->bind_param('ii', $supervisor['id'], $hrUser['id']);
                if ($insertWorkflowStmt->execute()) {
                    echo "<td style='color: green;'>✅ Routes to HR (ID: " . $hrUser['id'] . ")</td>";
                } else {
                    echo "<td style='color: red;'>❌ Failed: " . $insertWorkflowStmt->error . "</td>";
                }
                $insertWorkflowStmt->close();
            } else {
                echo "<td style='color: red;'>❌ Failed to prepare statement</td>";
            }
            
            echo "</tr>";
        }
        echo "</table>";
    }
    
    // Show current workflow configuration
    echo "<h3>Current Approval Workflow Configuration</h3>";
    $workflowStmt = $conn->prepare("
        SELECT 
            aw.user_id,
            u.username,
            u.full_name,
            aw.user_type,
            aw.approver_user_id,
            approver.username as approver_username,
            aw.approver_role,
            aw.created_at
        FROM attendance_approval_workflow aw
        LEFT JOIN users u ON aw.user_id = u.id
        LEFT JOIN users approver ON aw.approver_user_id = approver.id
        ORDER BY aw.user_id
    ");
    $workflowStmt->execute();
    $workflows = $workflowStmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $workflowStmt->close();
    
    if (!empty($workflows)) {
        echo "<table border='1' style='border-collapse: collapse;'>";
        echo "<tr><th>User ID</th><th>Username</th><th>Full Name</th><th>User Type</th><th>Approver ID</th><th>Approver Username</th><th>Approver Role</th><th>Created</th></tr>";
        foreach ($workflows as $workflow) {
            echo "<tr>";
            echo "<td>" . $workflow['user_id'] . "</td>";
            echo "<td>" . htmlspecialchars($workflow['username']) . "</td>";
            echo "<td>" . htmlspecialchars($workflow['full_name'] ?? 'N/A') . "</td>";
            echo "<td>" . htmlspecialchars($workflow['user_type']) . "</td>";
            echo "<td>" . $workflow['approver_user_id'] . "</td>";
            echo "<td>" . htmlspecialchars($workflow['approver_username']) . "</td>";
            echo "<td>" . htmlspecialchars($workflow['approver_role']) . "</td>";
            echo "<td>" . $workflow['created_at'] . "</td>";
            echo "</tr>";
        }
        echo "</table>";
    } else {
        echo "<p>No approval workflows configured yet.</p>";
    }
    
    echo "<h3>✅ Approval Workflow Setup Complete!</h3>";
    echo "<p>All supervisors (with and without driver_id) will now have their attendance routed to HR for approval.</p>";
    
} catch (Exception $e) {
    echo "<h3 style='color: red;'>❌ Error</h3>";
    echo "<p>Error: " . $e->getMessage() . "</p>";
}

echo "<h3>📝 Next Steps:</h3>";
echo "<ol>";
echo "<li>Run this script to set up approval workflow</li>";
echo "<li>Test attendance submission for supervisors with driver_id</li>";
echo "<li>Test attendance submission for supervisors without driver_id</li>";
echo "<li>Verify approvals are routed to HR user (hrattendence)</li>";
echo "<li>Check debug logs for approval routing</li>";
echo "</ol>";
?>
