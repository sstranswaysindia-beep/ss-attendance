<?php
require_once 'common.php';

header('Content-Type: text/html; charset=utf-8');

$userId = 5; // Supervisor ID 5

echo "<h2>Debug Profile Photo for Supervisor ID: $userId</h2>";

try {
    // Test 1: Check user data
    echo "<h3>Test 1: User Data</h3>";
    $userStmt = $conn->prepare("SELECT id, username, full_name, role, driver_id, profile_photo FROM users WHERE id = ? LIMIT 1");
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
        $highlight = $field === 'profile_photo' ? ' style="background-color: #90EE90;"' : '';
        echo "<tr$highlight>";
        echo "<td>" . htmlspecialchars($field) . "</td>";
        echo "<td>" . htmlspecialchars($value ?? 'NULL') . "</td>";
        echo "</tr>";
    }
    echo "</table>";
    
    // Test 2: Check if profile photo file exists
    echo "<h3>Test 2: Profile Photo File Check</h3>";
    if (!empty($user['profile_photo'])) {
        $photoUrl = $user['profile_photo'];
        echo "<p>Profile Photo URL: <code>$photoUrl</code></p>";
        
        // Check if it's a full URL or relative path
        if (strpos($photoUrl, 'http') === 0) {
            echo "<p>✅ Full URL detected</p>";
            
            // Try to check if file exists on server
            $relativePath = str_replace('https://sstranswaysindia.com', '', $photoUrl);
            $fullPath = $_SERVER['DOCUMENT_ROOT'] . $relativePath;
            
            echo "<p>Expected file path: <code>$fullPath</code></p>";
            
            if (file_exists($fullPath)) {
                echo "<p>✅ File exists on server</p>";
                echo "<p>File size: " . filesize($fullPath) . " bytes</p>";
                echo "<p>File permissions: " . substr(sprintf('%o', fileperms($fullPath)), -4) . "</p>";
                
                // Show image preview
                echo "<h4>Image Preview:</h4>";
                echo "<img src='$photoUrl' style='max-width: 200px; max-height: 200px; border: 1px solid #ccc;' alt='Profile Photo'>";
            } else {
                echo "<p>❌ File does not exist on server</p>";
                
                // Check if directory exists
                $dirPath = dirname($fullPath);
                if (is_dir($dirPath)) {
                    echo "<p>✅ Directory exists: $dirPath</p>";
                    echo "<p>Directory contents:</p>";
                    echo "<ul>";
                    $files = scandir($dirPath);
                    foreach ($files as $file) {
                        if ($file !== '.' && $file !== '..') {
                            echo "<li>$file</li>";
                        }
                    }
                    echo "</ul>";
                } else {
                    echo "<p>❌ Directory does not exist: $dirPath</p>";
                }
            }
        } else {
            echo "<p>⚠️ Relative URL detected - may need full URL</p>";
        }
    } else {
        echo "<p>⚠️ No profile photo URL in database</p>";
    }
    
    // Test 3: Check upload directory permissions
    echo "<h3>Test 3: Upload Directory Check</h3>";
    $uploadDir = $_SERVER['DOCUMENT_ROOT'] . '/DriverDocs/uploads/' . $userId . '/';
    echo "<p>Upload directory: <code>$uploadDir</code></p>";
    
    if (is_dir($uploadDir)) {
        echo "<p>✅ Upload directory exists</p>";
        echo "<p>Directory permissions: " . substr(sprintf('%o', fileperms($uploadDir)), -4) . "</p>";
        
        $files = scandir($uploadDir);
        $profileFiles = array_filter($files, function($file) {
            return strpos($file, 'profile_') === 0;
        });
        
        echo "<p>Profile files found: " . count($profileFiles) . "</p>";
        if (!empty($profileFiles)) {
            echo "<ul>";
            foreach ($profileFiles as $file) {
                echo "<li>$file</li>";
            }
            echo "</ul>";
        }
    } else {
        echo "<p>⚠️ Upload directory does not exist</p>";
        echo "<p>Creating directory...</p>";
        
        if (mkdir($uploadDir, 0755, true)) {
            echo "<p>✅ Upload directory created</p>";
        } else {
            echo "<p>❌ Failed to create upload directory</p>";
        }
    }
    
    // Test 4: Test API endpoint
    echo "<h3>Test 4: API Endpoint Test</h3>";
    $apiStmt = $conn->prepare("
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
    
    $apiStmt->bind_param("s", $userId);
    $apiStmt->execute();
    $apiResult = $apiStmt->get_result();
    $apiData = $apiResult->fetch_assoc();
    $apiStmt->close();
    
    if ($apiData) {
        echo "<p>✅ API query successful</p>";
        echo "<p>Profile Photo in API response: <code>" . ($apiData['profile_photo'] ?? 'NULL') . "</code></p>";
        
        // Test JSON response
        $jsonResponse = [
            'status' => 'ok',
            'profile' => $apiData
        ];
        
        echo "<h4>JSON Response Preview:</h4>";
        echo "<pre>" . json_encode($jsonResponse, JSON_PRETTY_PRINT) . "</pre>";
    } else {
        echo "<p>❌ API query failed</p>";
    }
    
    // Test 5: Compare with working supervisor (ID 8 - arunkumar)
    echo "<h3>Test 5: Compare with Working Supervisor (ID 8)</h3>";
    $compareStmt = $conn->prepare("SELECT id, username, driver_id, profile_photo FROM users WHERE id = 8 LIMIT 1");
    $compareStmt->execute();
    $compareUser = $compareStmt->get_result()->fetch_assoc();
    $compareStmt->close();
    
    if ($compareUser) {
        echo "<table border='1' style='border-collapse: collapse;'>";
        echo "<tr><th>Field</th><th>User 5 (Problem)</th><th>User 8 (Working)</th><th>Difference</th></tr>";
        
        $fields = ['id', 'username', 'driver_id', 'profile_photo'];
        foreach ($fields as $field) {
            $value5 = $user[$field] ?? 'NULL';
            $value8 = $compareUser[$field] ?? 'NULL';
            $diff = ($value5 === $value8) ? 'Same' : 'Different';
            $color = ($diff === 'Same') ? 'background-color: #90EE90;' : 'background-color: #FFB6C1;';
            
            echo "<tr style='$color'>";
            echo "<td>" . htmlspecialchars($field) . "</td>";
            echo "<td>" . htmlspecialchars($value5) . "</td>";
            echo "<td>" . htmlspecialchars($value8) . "</td>";
            echo "<td>" . $diff . "</td>";
            echo "</tr>";
        }
        echo "</table>";
    }
    
} catch (Exception $e) {
    echo "<h3 style='color: red;'>❌ Error</h3>";
    echo "<p>Error: " . $e->getMessage() . "</p>";
}

echo "<h3>📝 Summary</h3>";
echo "<ul>";
echo "<li>User ID 5: " . ($user['username'] ?? 'Unknown') . "</li>";
echo "<li>Has Driver ID: " . (!empty($user['driver_id']) ? 'YES' : 'NO') . "</li>";
echo "<li>Profile Photo URL: " . ($user['profile_photo'] ?? 'NULL') . "</li>";
echo "<li>Upload Directory: " . (is_dir($_SERVER['DOCUMENT_ROOT'] . '/DriverDocs/uploads/' . $userId . '/') ? 'EXISTS' : 'MISSING') . "</li>";
echo "</ul>";

echo "<h3>🔧 Recommended Actions:</h3>";
echo "<ol>";
echo "<li>If profile photo URL is NULL or incomplete, upload a new photo through the mobile app</li>";
echo "<li>If upload directory is missing, it will be created automatically</li>";
echo "<li>If file exists but URL is wrong, update the database with correct URL</li>";
echo "<li>Test profile photo upload functionality</li>";
echo "</ol>";
?>
