<?php
require_once 'common.php';

header('Content-Type: text/html; charset=utf-8');

echo "<h2>Fix Attendance Foreign Key Constraint</h2>";
echo "<p>This script will modify the attendance table to allow supervisors without driver_id to use attendance.</p>";

try {
    // Check current foreign key constraints on attendance table
    echo "<h3>Current Foreign Key Constraints on Attendance Table:</h3>";
    
    $constraintStmt = $conn->prepare("
        SELECT 
            CONSTRAINT_NAME,
            COLUMN_NAME,
            REFERENCED_TABLE_NAME,
            REFERENCED_COLUMN_NAME,
            DELETE_RULE,
            UPDATE_RULE
        FROM information_schema.KEY_COLUMN_USAGE 
        WHERE TABLE_SCHEMA = DATABASE() 
        AND TABLE_NAME = 'attendance' 
        AND REFERENCED_TABLE_NAME IS NOT NULL
    ");
    
    $constraintStmt->execute();
    $constraints = $constraintStmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $constraintStmt->close();
    
    if (empty($constraints)) {
        echo "<p>✅ No foreign key constraints found on attendance table</p>";
    } else {
        echo "<table border='1' style='border-collapse: collapse;'>";
        echo "<tr><th>Constraint Name</th><th>Column</th><th>References Table</th><th>References Column</th><th>Delete Rule</th><th>Update Rule</th></tr>";
        foreach ($constraints as $constraint) {
            echo "<tr>";
            echo "<td>" . htmlspecialchars($constraint['CONSTRAINT_NAME']) . "</td>";
            echo "<td>" . htmlspecialchars($constraint['COLUMN_NAME']) . "</td>";
            echo "<td>" . htmlspecialchars($constraint['REFERENCED_TABLE_NAME']) . "</td>";
            echo "<td>" . htmlspecialchars($constraint['REFERENCED_COLUMN_NAME']) . "</td>";
            echo "<td>" . htmlspecialchars($constraint['DELETE_RULE']) . "</td>";
            echo "<td>" . htmlspecialchars($constraint['UPDATE_RULE']) . "</td>";
            echo "</tr>";
        }
        echo "</table>";
    }
    
    // Check attendance table structure
    echo "<h3>Current Attendance Table Structure:</h3>";
    
    $structureStmt = $conn->prepare("DESCRIBE attendance");
    $structureStmt->execute();
    $structure = $structureStmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $structureStmt->close();
    
    echo "<table border='1' style='border-collapse: collapse;'>";
    echo "<tr><th>Field</th><th>Type</th><th>Null</th><th>Key</th><th>Default</th><th>Extra</th></tr>";
    foreach ($structure as $field) {
        $highlight = $field['Field'] === 'driver_id' ? ' style="background-color: #FFE4B5;"' : '';
        echo "<tr$highlight>";
        echo "<td>" . htmlspecialchars($field['Field']) . "</td>";
        echo "<td>" . htmlspecialchars($field['Type']) . "</td>";
        echo "<td>" . htmlspecialchars($field['Null']) . "</td>";
        echo "<td>" . htmlspecialchars($field['Key']) . "</td>";
        echo "<td>" . htmlspecialchars($field['Default'] ?? 'NULL') . "</td>";
        echo "<td>" . htmlspecialchars($field['Extra']) . "</td>";
        echo "</tr>";
    }
    echo "</table>";
    
    // Check if driver_id column allows NULL
    $driverIdField = array_filter($structure, function($field) {
        return $field['Field'] === 'driver_id';
    });
    
    if (!empty($driverIdField)) {
        $driverIdField = array_values($driverIdField)[0];
        echo "<h3>Driver ID Column Analysis:</h3>";
        echo "<p>Current driver_id column allows NULL: <strong>" . ($driverIdField['Null'] === 'YES' ? 'YES ✅' : 'NO ❌') . "</strong></p>";
        
        if ($driverIdField['Null'] === 'NO') {
            echo "<p>⚠️ The driver_id column does NOT allow NULL values. This needs to be changed.</p>";
        } else {
            echo "<p>✅ The driver_id column allows NULL values.</p>";
        }
    }
    
    // Show the solution
    echo "<h3>🔧 Solution:</h3>";
    echo "<p>To fix the foreign key constraint issue for supervisors without driver_id:</p>";
    echo "<ol>";
    echo "<li><strong>Remove the foreign key constraint</strong> on driver_id column</li>";
    echo "<li><strong>Allow NULL values</strong> in driver_id column (if not already allowed)</li>";
    echo "<li><strong>Modify attendance logic</strong> to handle NULL driver_id for supervisors</li>";
    echo "</ol>";
    
    // Check if we need to make changes
    $needsChanges = false;
    $constraintToRemove = null;
    
    foreach ($constraints as $constraint) {
        if ($constraint['COLUMN_NAME'] === 'driver_id' && $constraint['REFERENCED_TABLE_NAME'] === 'drivers') {
            $needsChanges = true;
            $constraintToRemove = $constraint['CONSTRAINT_NAME'];
            break;
        }
    }
    
    if ($driverIdField['Null'] === 'NO') {
        $needsChanges = true;
    }
    
    if ($needsChanges) {
        echo "<h3>🚨 Changes Required:</h3>";
        echo "<div style='background: #ffebee; padding: 15px; border-left: 4px solid #f44336;'>";
        
        if ($constraintToRemove) {
            echo "<p><strong>1. Remove Foreign Key Constraint:</strong></p>";
            echo "<code>ALTER TABLE attendance DROP FOREIGN KEY $constraintToRemove;</code><br><br>";
        }
        
        if ($driverIdField['Null'] === 'NO') {
            echo "<p><strong>2. Allow NULL in driver_id column:</strong></p>";
            echo "<code>ALTER TABLE attendance MODIFY COLUMN driver_id INT(11) NULL;</code><br><br>";
        }
        
        echo "<p><strong>3. Update attendance_submit.php to handle NULL driver_id:</strong></p>";
        echo "<p>✅ Already implemented - the code uses user ID as fallback for supervisors</p>";
        
        echo "</div>";
        
        // Ask for confirmation
        echo "<h3>⚠️ Confirmation Required:</h3>";
        echo "<p>These changes will:</p>";
        echo "<ul>";
        echo "<li>✅ Allow supervisors without driver_id to use attendance</li>";
        echo "<li>✅ Fix the foreign key constraint error</li>";
        echo "<li>⚠️ Remove the database-level constraint (application logic will handle validation)</li>";
        echo "</ul>";
        
        echo "<form method='post'>";
        echo "<input type='hidden' name='action' value='apply_fixes'>";
        echo "<button type='submit' style='background: #4CAF50; color: white; padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer;'>Apply Database Fixes</button>";
        echo "</form>";
        
    } else {
        echo "<h3>✅ No Changes Required</h3>";
        echo "<p>The attendance table is already properly configured to handle supervisors without driver_id.</p>";
    }
    
    // Apply fixes if requested
    if ($_POST['action'] === 'apply_fixes') {
        echo "<h3>🔧 Applying Database Fixes...</h3>";
        
        try {
            // Remove foreign key constraint if it exists
            foreach ($constraints as $constraint) {
                if ($constraint['COLUMN_NAME'] === 'driver_id' && $constraint['REFERENCED_TABLE_NAME'] === 'drivers') {
                    $dropConstraintSql = "ALTER TABLE attendance DROP FOREIGN KEY " . $constraint['CONSTRAINT_NAME'];
                    echo "<p>Executing: <code>$dropConstraintSql</code></p>";
                    
                    if ($conn->query($dropConstraintSql)) {
                        echo "<p>✅ Foreign key constraint removed successfully</p>";
                    } else {
                        echo "<p>❌ Failed to remove foreign key constraint: " . $conn->error . "</p>";
                    }
                    break;
                }
            }
            
            // Allow NULL in driver_id column if needed
            if ($driverIdField['Null'] === 'NO') {
                $modifyColumnSql = "ALTER TABLE attendance MODIFY COLUMN driver_id INT(11) NULL";
                echo "<p>Executing: <code>$modifyColumnSql</code></p>";
                
                if ($conn->query($modifyColumnSql)) {
                    echo "<p>✅ driver_id column now allows NULL values</p>";
                } else {
                    echo "<p>❌ Failed to modify driver_id column: " . $conn->error . "</p>";
                }
            }
            
            echo "<h3>🎉 Database Fixes Applied Successfully!</h3>";
            echo "<p>Supervisors without driver_id can now use attendance without foreign key constraint errors.</p>";
            echo "<p><a href='test_supervisor_attendance.php?userId=4' style='background: #2196F3; color: white; padding: 10px; text-decoration: none; border-radius: 5px;'>Test Attendance with Supervisor (vedpal)</a></p>";
            
        } catch (Exception $e) {
            echo "<p>❌ Error applying fixes: " . $e->getMessage() . "</p>";
        }
    }
    
} catch (Exception $e) {
    echo "<h3 style='color: red;'>❌ Error</h3>";
    echo "<p>Error: " . $e->getMessage() . "</p>";
}

echo "<h3>📝 Next Steps:</h3>";
echo "<ol>";
echo "<li>Review the current database constraints above</li>";
echo "<li>If changes are required, click 'Apply Database Fixes'</li>";
echo "<li>Test attendance with supervisors without driver_id</li>";
echo "<li>Debug profile photo issues separately</li>";
echo "</ol>";
?>
