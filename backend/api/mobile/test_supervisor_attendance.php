<?php
require_once 'common.php';

header('Content-Type: text/html; charset=utf-8');

echo "<h2>Supervisor Attendance Test</h2>";

// Test with a supervisor user ID
$testUserId = $_GET['userId'] ?? '1';

echo "<p>Testing with User ID: $testUserId</p>";

try {
    // Test 1: Check if user exists and is a supervisor
    echo "<h3>Test 1: User Validation</h3>";
    $userStmt = $conn->prepare("SELECT id, username, role, profile_photo FROM users WHERE id = ? LIMIT 1");
    $userStmt->bind_param("s", $testUserId);
    $userStmt->execute();
    $userResult = $userStmt->get_result();
    $user = $userResult->fetch_assoc();
    $userStmt->close();
    
    if (!$user) {
        echo "<p>❌ User not found</p>";
    } else {
        echo "<p>✅ User found: {$user['username']} (Role: {$user['role']})</p>";
        echo "<p>Profile Photo: " . ($user['profile_photo'] ?: 'None') . "</p>";
        
        if ($user['role'] !== 'supervisor') {
            echo "<p>⚠️ User is not a supervisor</p>";
        }
    }
    
    // Test 2: Check if user has driver_id (supervisor without driver_id)
    echo "<h3>Test 2: Driver ID Check</h3>";
    $driverStmt = $conn->prepare("SELECT id FROM drivers WHERE id = ? LIMIT 1");
    $driverStmt->bind_param("s", $testUserId);
    $driverStmt->execute();
    $driverExists = $driverStmt->get_result()->fetch_assoc();
    $driverStmt->close();
    
    if ($driverExists) {
        echo "<p>✅ User ID exists in drivers table (supervisor with driver_id)</p>";
    } else {
        echo "<p>✅ User ID does NOT exist in drivers table (supervisor without driver_id)</p>";
    }
    
    // Test 3: Test attendance submission logic
    echo "<h3>Test 3: Attendance Submission Logic</h3>";
    $driverId = $testUserId; // This is what the app sends
    
    // Check if the ID exists in drivers table, if not check users table
    $driverStmt = $conn->prepare('SELECT id FROM drivers WHERE id = ? LIMIT 1');
    $driverStmt->bind_param('i', $driverId);
    $driverStmt->execute();
    $driverExists = $driverStmt->get_result()->fetch_assoc();
    $driverStmt->close();
    
    if (!$driverExists) {
        // Check if it's a user ID (for supervisors without driver_id)
        $userStmt = $conn->prepare('SELECT id FROM users WHERE id = ? AND role = "supervisor" LIMIT 1');
        $userStmt->bind_param('i', $driverId);
        $userStmt->execute();
        $userExists = $userStmt->get_result()->fetch_assoc();
        $userStmt->close();
        
        if (!$userExists) {
            echo "<p>❌ Driver or supervisor not found in attendance validation</p>";
        } else {
            echo "<p>✅ Supervisor validation passed - can submit attendance</p>";
        }
    } else {
        echo "<p>✅ Driver validation passed - can submit attendance</p>";
    }
    
    // Test 4: Check profile photo API
    echo "<h3>Test 4: Profile Photo API Test</h3>";
    $profileStmt = $conn->prepare("
        SELECT 
            id,
            username,
            full_name,
            email,
            phone,
            role,
            profile_photo,
            created_at,
            updated_at,
            last_login_at,
            must_change_password
        FROM users 
        WHERE id = ? 
        LIMIT 1
    ");
    
    $profileStmt->bind_param("s", $testUserId);
    $profileStmt->execute();
    $profileResult = $profileStmt->get_result();
    $profileData = $profileResult->fetch_assoc();
    $profileStmt->close();
    
    if ($profileData) {
        echo "<p>✅ Profile data retrieved successfully</p>";
        echo "<p>Profile Photo URL: " . ($profileData['profile_photo'] ?: 'NULL') . "</p>";
        
        if (!empty($profileData['profile_photo'])) {
            echo "<p>🖼️ Profile photo exists in database</p>";
        } else {
            echo "<p>⚠️ No profile photo in database</p>";
        }
    } else {
        echo "<p>❌ Failed to retrieve profile data</p>";
    }
    
} catch (Exception $e) {
    echo "<h3>❌ Error</h3>";
    echo "<p>Error: " . $e->getMessage() . "</p>";
}

echo "<h3>📝 Instructions</h3>";
echo "<ol>";
echo "<li>Replace 'userId' parameter with actual supervisor user ID</li>";
echo "<li>Check all test results above</li>";
echo "<li>If any test fails, that indicates the issue</li>";
echo "</ol>";
?>
