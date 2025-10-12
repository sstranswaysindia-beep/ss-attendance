<?php
require_once 'common.php';

header('Content-Type: text/html; charset=utf-8');

echo "<h2>Debug Profile Photo Upload</h2>";

try {
    // Test 1: Check if common.php is loaded correctly
    echo "<h3>Test 1: Common.php Functions</h3>";
    if (function_exists('apiSaveUploadedFile')) {
        echo "<p>✅ apiSaveUploadedFile function exists</p>";
    } else {
        echo "<p>❌ apiSaveUploadedFile function not found</p>";
    }
    
    if (function_exists('apiRespond')) {
        echo "<p>✅ apiRespond function exists</p>";
    } else {
        echo "<p>❌ apiRespond function not found</p>";
    }
    
    // Test 2: Check database connection
    echo "<h3>Test 2: Database Connection</h3>";
    if ($conn && !$conn->connect_error) {
        echo "<p>✅ Database connection successful</p>";
        echo "<p>Database: " . $conn->get_server_info() . "</p>";
    } else {
        echo "<p>❌ Database connection failed: " . ($conn->connect_error ?? 'Unknown error') . "</p>";
    }
    
    // Test 3: Check upload directory
    echo "<h3>Test 3: Upload Directory</h3>";
    $baseDir = realpath(__DIR__ . '/../../DriverDocs/uploads');
    echo "<p>Base upload directory: <code>$baseDir</code></p>";
    
    if ($baseDir && is_dir($baseDir)) {
        echo "<p>✅ Base upload directory exists</p>";
        echo "<p>Permissions: " . substr(sprintf('%o', fileperms($baseDir)), -4) . "</p>";
    } else {
        echo "<p>❌ Base upload directory does not exist</p>";
        echo "<p>Creating directory...</p>";
        if (mkdir($baseDir, 0755, true)) {
            echo "<p>✅ Base upload directory created</p>";
        } else {
            echo "<p>❌ Failed to create base upload directory</p>";
        }
    }
    
    // Test 4: Check user ID 4 (vedpal)
    echo "<h3>Test 4: User Check</h3>";
    $testUserId = 4;
    $userStmt = $conn->prepare("SELECT id, username, role, driver_id FROM users WHERE id = ? LIMIT 1");
    $userStmt->bind_param("s", $testUserId);
    $userStmt->execute();
    $userResult = $userStmt->get_result();
    $user = $userResult->fetch_assoc();
    $userStmt->close();
    
    if ($user) {
        echo "<p>✅ User found:</p>";
        echo "<ul>";
        echo "<li>ID: " . $user['id'] . "</li>";
        echo "<li>Username: " . $user['username'] . "</li>";
        echo "<li>Role: " . $user['role'] . "</li>";
        echo "<li>Driver ID: " . ($user['driver_id'] ?? 'NULL') . "</li>";
        echo "</ul>";
        
        // Test 5: Check user-specific upload directory
        echo "<h3>Test 5: User Upload Directory</h3>";
        $userUploadDir = $baseDir . '/' . $testUserId;
        echo "<p>User upload directory: <code>$userUploadDir</code></p>";
        
        if (is_dir($userUploadDir)) {
            echo "<p>✅ User upload directory exists</p>";
            echo "<p>Permissions: " . substr(sprintf('%o', fileperms($userUploadDir)), -4) . "</p>";
        } else {
            echo "<p>⚠️ User upload directory does not exist (will be created on upload)</p>";
        }
    } else {
        echo "<p>❌ User not found</p>";
    }
    
    // Test 6: Check PHP upload settings
    echo "<h3>Test 6: PHP Upload Settings</h3>";
    echo "<ul>";
    echo "<li>file_uploads: " . (ini_get('file_uploads') ? 'ON' : 'OFF') . "</li>";
    echo "<li>upload_max_filesize: " . ini_get('upload_max_filesize') . "</li>";
    echo "<li>post_max_size: " . ini_get('post_max_size') . "</li>";
    echo "<li>max_file_uploads: " . ini_get('max_file_uploads') . "</li>";
    echo "</ul>";
    
    // Test 7: Check if user_profile_photo_upload.php exists
    echo "<h3>Test 7: Profile Upload Script</h3>";
    $uploadScript = __DIR__ . '/user_profile_photo_upload.php';
    if (file_exists($uploadScript)) {
        echo "<p>✅ user_profile_photo_upload.php exists</p>";
        echo "<p>File size: " . filesize($uploadScript) . " bytes</p>";
        echo "<p>Last modified: " . date('Y-m-d H:i:s', filemtime($uploadScript)) . "</p>";
    } else {
        echo "<p>❌ user_profile_photo_upload.php not found</p>";
    }
    
    // Test 8: Check get_user_profile.php
    echo "<h3>Test 8: Profile Fetch Script</h3>";
    $profileScript = __DIR__ . '/get_user_profile.php';
    if (file_exists($profileScript)) {
        echo "<p>✅ get_user_profile.php exists</p>";
        echo "<p>File size: " . filesize($profileScript) . " bytes</p>";
    } else {
        echo "<p>❌ get_user_profile.php not found</p>";
    }
    
} catch (Exception $e) {
    echo "<h3 style='color: red;'>❌ Error</h3>";
    echo "<p>Error: " . $e->getMessage() . "</p>";
}

echo "<h3>📝 Next Steps:</h3>";
echo "<ol>";
echo "<li>Check all test results above</li>";
echo "<li>If upload directory issues, fix permissions</li>";
echo "<li>If script issues, re-upload the files</li>";
echo "<li>Test profile photo upload with mobile app</li>";
echo "</ol>";
?>
