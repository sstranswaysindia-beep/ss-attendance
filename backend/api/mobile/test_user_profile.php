<?php
require_once 'common.php';

header('Content-Type: text/html; charset=utf-8');

// Test with a specific user ID - replace with actual supervisor user ID
$testUserId = $_GET['userId'] ?? '1';

echo "<h2>Testing User Profile API</h2>";
echo "<p>Testing with User ID: $testUserId</p>";

try {
    // Test the API endpoint
    $stmt = $conn->prepare("
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
    
    $stmt->bind_param("s", $testUserId);
    $stmt->execute();
    $result = $stmt->get_result();
    $userProfile = $result->fetch_assoc();
    $stmt->close();

    if (!$userProfile) {
        echo "<h3>❌ User not found</h3>";
        echo "<p>No user found with ID: $testUserId</p>";
    } else {
        echo "<h3>✅ User found!</h3>";
        echo "<table border='1' style='border-collapse: collapse; width: 100%;'>";
        echo "<tr><th>Field</th><th>Value</th></tr>";
        
        foreach ($userProfile as $field => $value) {
            $highlight = $field === 'profile_photo' ? ' style="background-color: #90EE90;"' : '';
            echo "<tr$highlight>";
            echo "<td>" . htmlspecialchars($field) . "</td>";
            echo "<td>" . htmlspecialchars($value ?? 'NULL') . "</td>";
            echo "</tr>";
        }
        echo "</table>";
        
        if (!empty($userProfile['profile_photo'])) {
            echo "<h3>🖼️ Profile Photo Preview</h3>";
            echo "<img src='" . htmlspecialchars($userProfile['profile_photo']) . "' style='max-width: 200px; max-height: 200px; border: 1px solid #ccc;' alt='Profile Photo'>";
        } else {
            echo "<h3>⚠️ No Profile Photo</h3>";
            echo "<p>The user doesn't have a profile photo set.</p>";
        }
    }
    
} catch (Exception $e) {
    echo "<h3>❌ Database Error</h3>";
    echo "<p>Error: " . $e->getMessage() . "</p>";
}

echo "<h3>📝 Instructions</h3>";
echo "<ol>";
echo "<li>Replace 'userId' parameter in URL with actual supervisor user ID</li>";
echo "<li>Check if profile_photo column exists and has data</li>";
echo "<li>If column is missing, run add_profile_photo_column.php</li>";
echo "</ol>";
?>
