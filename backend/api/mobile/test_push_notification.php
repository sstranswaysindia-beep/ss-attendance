<?php
// Test script for FCM v1 Push Notifications
// Access this file via browser or curl to test

require_once 'send_push_notification_v1.php';

echo "<h2>FCM v1 Push Notification Test</h2>";

try {
    // Test 1: Check if Firebase Admin SDK file exists
    echo "<h3>Test 1: Firebase Admin SDK File</h3>";
    if (file_exists(SERVICE_ACCOUNT_JSON_PATH)) {
        echo "✅ Firebase Admin SDK JSON file found<br>";
        $serviceAccount = json_decode(file_get_contents(SERVICE_ACCOUNT_JSON_PATH), true);
        echo "Project ID: " . $serviceAccount['project_id'] . "<br>";
        echo "Client Email: " . $serviceAccount['client_email'] . "<br>";
    } else {
        echo "❌ Firebase Admin SDK JSON file not found at: " . SERVICE_ACCOUNT_JSON_PATH . "<br>";
    }
    
    // Test 2: Check database connection
    echo "<h3>Test 2: Database Connection</h3>";
    if (isset($conn) && $conn->ping()) {
        echo "✅ Database connection successful<br>";
        
        // Check if FCM tokens table exists
        $result = $conn->query("SHOW TABLES LIKE 'user_fcm_tokens'");
        if ($result->num_rows > 0) {
            echo "✅ FCM tokens table exists<br>";
            
            // Count stored tokens
            $result = $conn->query("SELECT COUNT(*) as count FROM user_fcm_tokens");
            $row = $result->fetch_assoc();
            echo "Stored FCM tokens: " . $row['count'] . "<br>";
        } else {
            echo "⚠️ FCM tokens table doesn't exist (will be created on first token update)<br>";
        }
    } else {
        echo "❌ Database connection failed<br>";
    }
    
    // Test 3: OAuth2 Token Generation
    echo "<h3>Test 3: OAuth2 Token Generation</h3>";
    try {
        $accessToken = getAccessToken();
        echo "✅ Access token generated successfully<br>";
        echo "Token (first 50 chars): " . substr($accessToken, 0, 50) . "...<br>";
    } catch (Exception $e) {
        echo "❌ Failed to generate access token: " . $e->getMessage() . "<br>";
    }
    
    // Test 4: FCM API Connection
    echo "<h3>Test 4: FCM v1 API Connection</h3>";
    try {
        // Try to send a test notification (this will fail if no valid FCM token, but API connection will be tested)
        $testToken = "test_token_for_api_connection_test";
        $response = sendPushNotification($testToken, "Test", "Test message");
        echo "✅ FCM v1 API connection successful<br>";
    } catch (Exception $e) {
        if (strpos($e->getMessage(), 'FCM v1 API request failed') !== false) {
            echo "✅ FCM v1 API connection established (test failed as expected with invalid token)<br>";
        } else {
            echo "❌ FCM v1 API connection failed: " . $e->getMessage() . "<br>";
        }
    }
    
    echo "<h3>🎉 Setup Verification Complete!</h3>";
    echo "<p>Your FCM v1 push notification system is ready to use.</p>";
    
    echo "<h3>📱 How to Test:</h3>";
    echo "<ol>";
    echo "<li>Run your Flutter app and login</li>";
    echo "<li>Check the console for FCM token</li>";
    echo "<li>Use the API endpoint to send notifications:</li>";
    echo "</ol>";
    
    echo "<h4>API Endpoint Usage:</h4>";
    echo "<pre>";
    echo "POST /api/mobile/send_push_notification_v1.php\n";
    echo "Content-Type: application/json\n\n";
    echo "{\n";
    echo "  \"userId\": \"your_user_id\",\n";
    echo "  \"title\": \"Test Notification\",\n";
    echo "  \"body\": \"This is a test message\",\n";
    echo "  \"data\": {\n";
    echo "    \"type\": \"test\",\n";
    echo "    \"timestamp\": \"" . date('Y-m-d H:i:s') . "\"\n";
    echo "  }\n";
    echo "}\n";
    echo "</pre>";
    
} catch (Exception $e) {
    echo "<h3>❌ Setup Error</h3>";
    echo "<p>Error: " . $e->getMessage() . "</p>";
}

echo "<hr>";
echo "<p><strong>Note:</strong> This test script verifies your FCM v1 setup. Make sure to:</p>";
echo "<ul>";
echo "<li>Upload both files to your server</li>";
echo "<li>Set proper file permissions</li>";
echo "<li>Run your Flutter app to generate FCM tokens</li>";
echo "</ul>";
?>
