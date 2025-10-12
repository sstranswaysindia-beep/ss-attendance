<?php
require_once 'common.php';

header('Content-Type: text/html; charset=utf-8');

// Get user ID from request
$userId = $_GET['userId'] ?? $_POST['userId'] ?? '1';

echo "<h2>Profile Photo Debug for User ID: $userId</h2>";

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
        echo "<p>❌ User not found with ID: $userId</p>";
        echo "<p><a href='list_all_users.php'>📋 View All Users</a> to find valid user IDs</p>";
        
        // Show some sample user IDs
        $sampleStmt = $conn->prepare("SELECT id, username, role FROM users ORDER BY id ASC LIMIT 5");
        if ($sampleStmt) {
            $sampleStmt->execute();
            $sampleResult = $sampleStmt->get_result();
            $samples = [];
            while ($row = $sampleResult->fetch_assoc()) {
                $samples[] = $row;
            }
            $sampleStmt->close();
            
            if (!empty($samples)) {
                echo "<h4>Available User IDs:</h4>";
                echo "<ul>";
                foreach ($samples as $sample) {
                    echo "<li>ID: {$sample['id']} - {$sample['username']} ({$sample['role']})</li>";
                }
                echo "</ul>";
            }
        }
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
    
    // Test 3: Test the API endpoint
    echo "<h3>Test 3: API Endpoint Test</h3>";
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
    
    // Test 4: Check upload directory permissions
    echo "<h3>Test 4: Upload Directory Check</h3>";
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
    
} catch (Exception $e) {
    echo "<h3 style='color: red;'>❌ Error</h3>";
    echo "<p>Error: " . $e->getMessage() . "</p>";
}

echo "<h3>📝 Instructions</h3>";
echo "<ol>";
echo "<li>Replace 'userId' parameter with actual supervisor user ID</li>";
echo "<li>Check all test results above</li>";
echo "<li>If profile photo URL is NULL, upload a new photo</li>";
echo "<li>If file doesn't exist, check upload directory and permissions</li>";
echo "</ol>";
?>
