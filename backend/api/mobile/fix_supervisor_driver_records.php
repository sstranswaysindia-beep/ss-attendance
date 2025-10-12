<?php
require_once 'common.php';

header('Content-Type: text/html; charset=utf-8');

echo "<h2>Fix Supervisor Driver Records</h2>";
echo "<p>This script will create driver records for supervisors without driver_id to fix attendance foreign key issues.</p>";

try {
    // Find supervisors without driver_id
    $stmt = $conn->prepare("
        SELECT u.id, u.username, u.full_name, u.role 
        FROM users u 
        WHERE u.role = 'supervisor' 
        AND (u.driver_id IS NULL OR u.driver_id = 0)
    ");
    
    if (!$stmt) {
        throw new Exception("Failed to prepare statement: " . $conn->error);
    }
    
    $stmt->execute();
    $result = $stmt->get_result();
    $supervisorsWithoutDriverId = [];
    
    while ($row = $result->fetch_assoc()) {
        $supervisorsWithoutDriverId[] = $row;
    }
    $stmt->close();
    
    echo "<h3>Found " . count($supervisorsWithoutDriverId) . " supervisors without driver_id:</h3>";
    
    if (empty($supervisorsWithoutDriverId)) {
        echo "<p>✅ All supervisors already have driver_id assigned.</p>";
    } else {
        echo "<table border='1' style='border-collapse: collapse; width: 100%;'>";
        echo "<tr><th>User ID</th><th>Username</th><th>Full Name</th><th>Action</th></tr>";
        
        foreach ($supervisorsWithoutDriverId as $supervisor) {
            echo "<tr>";
            echo "<td>" . htmlspecialchars($supervisor['id']) . "</td>";
            echo "<td>" . htmlspecialchars($supervisor['username']) . "</td>";
            echo "<td>" . htmlspecialchars($supervisor['full_name'] ?? 'N/A') . "</td>";
            
            // Get supervised plants for this supervisor
            $plantStmt = $conn->prepare("
                SELECT DISTINCT p.id, p.plant_name
                FROM plants p
                LEFT JOIN supervisor_plants sp ON sp.plant_id = p.id
                WHERE p.supervisor_user_id = ? OR sp.user_id = ?
                ORDER BY p.plant_name
                LIMIT 1
            ");
            
            if ($plantStmt) {
                $plantStmt->bind_param('ii', $supervisor['id'], $supervisor['id']);
                $plantStmt->execute();
                $plantResult = $plantStmt->get_result();
                $primaryPlant = $plantResult->fetch_assoc();
                $plantStmt->close();
                
                if ($primaryPlant) {
                    // Create driver record
                    $supervisorName = $supervisor['full_name'] ?? $supervisor['username'];
                    $createDriverStmt = $conn->prepare(
                        'INSERT INTO drivers (name, role, plant_id, status, created_at, updated_at) VALUES (?, "supervisor", ?, "active", NOW(), NOW())'
                    );
                    
                    if ($createDriverStmt) {
                        $createDriverStmt->bind_param('si', $supervisorName, $primaryPlant['id']);
                        if ($createDriverStmt->execute()) {
                            $newDriverId = $createDriverStmt->insert_id;
                            $createDriverStmt->close();
                            
                            // Update user record with the new driver_id
                            $updateUserStmt = $conn->prepare('UPDATE users SET driver_id = ? WHERE id = ?');
                            if ($updateUserStmt) {
                                $updateUserStmt->bind_param('ii', $newDriverId, $supervisor['id']);
                                if ($updateUserStmt->execute()) {
                                    echo "<td style='color: green;'>✅ Created driver record #$newDriverId for plant '{$primaryPlant['plant_name']}'</td>";
                                } else {
                                    echo "<td style='color: red;'>❌ Failed to update user record: " . $updateUserStmt->error . "</td>";
                                }
                                $updateUserStmt->close();
                            } else {
                                echo "<td style='color: red;'>❌ Failed to prepare user update: " . $conn->error . "</td>";
                            }
                        } else {
                            echo "<td style='color: red;'>❌ Failed to create driver record: " . $createDriverStmt->error . "</td>";
                            $createDriverStmt->close();
                        }
                    } else {
                        echo "<td style='color: red;'>❌ Failed to prepare driver creation: " . $conn->error . "</td>";
                    }
                } else {
                    echo "<td style='color: orange;'>⚠️ No supervised plants found</td>";
                }
            } else {
                echo "<td style='color: red;'>❌ Failed to query supervised plants</td>";
            }
            
            echo "</tr>";
        }
        echo "</table>";
    }
    
    // Show final status
    echo "<h3>Final Status Check:</h3>";
    $finalStmt = $conn->prepare("
        SELECT COUNT(*) as total_supervisors,
               SUM(CASE WHEN driver_id IS NOT NULL AND driver_id > 0 THEN 1 ELSE 0 END) as with_driver_id
        FROM users 
        WHERE role = 'supervisor'
    ");
    
    $finalStmt->execute();
    $finalResult = $finalStmt->get_result()->fetch_assoc();
    $finalStmt->close();
    
    echo "<p>Total Supervisors: " . $finalResult['total_supervisors'] . "</p>";
    echo "<p>With Driver ID: " . $finalResult['with_driver_id'] . "</p>";
    echo "<p>Without Driver ID: " . ($finalResult['total_supervisors'] - $finalResult['with_driver_id']) . "</p>";
    
    if ($finalResult['with_driver_id'] == $finalResult['total_supervisors']) {
        echo "<h3 style='color: green;'>✅ All supervisors now have driver_id assigned!</h3>";
        echo "<p>Attendance should now work without foreign key constraint errors.</p>";
    } else {
        echo "<h3 style='color: orange;'>⚠️ Some supervisors still don't have driver_id</h3>";
        echo "<p>These supervisors may need manual intervention or have no supervised plants.</p>";
    }
    
} catch (Exception $e) {
    echo "<h3 style='color: red;'>❌ Error</h3>";
    echo "<p>Error: " . $e->getMessage() . "</p>";
}

echo "<h3>📝 Next Steps:</h3>";
echo "<ol>";
echo "<li>Run this script to create driver records for supervisors without driver_id</li>";
echo "<li>Test attendance check-in/check-out for supervisors</li>";
echo "<li>Verify that foreign key constraint errors are resolved</li>";
echo "</ol>";
?>
