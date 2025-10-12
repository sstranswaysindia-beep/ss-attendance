<?php
require_once '/common.php';

// Firebase Cloud Messaging Server Key
// Get this from Firebase Console > Project Settings > Cloud Messaging > Server Key
const FCM_SERVER_KEY = 'YOUR_FCM_SERVER_KEY_HERE'; // Replace with your actual server key
const FCM_URL = 'https://fcm.googleapis.com/fcm/send';

function sendPushNotification($fcmToken, $title, $body, $data = []) {
    if (empty(FCM_SERVER_KEY) || FCM_SERVER_KEY === 'YOUR_FCM_SERVER_KEY_HERE') {
        throw new Exception('FCM Server Key not configured');
    }
    
    $notification = [
        'title' => $title,
        'body' => $body,
        'sound' => 'default',
        'icon' => 'ic_launcher'
    ];
    
    $payload = [
        'to' => $fcmToken,
        'notification' => $notification,
        'data' => $data,
        'priority' => 'high'
    ];
    
    $headers = [
        'Authorization: key=' . FCM_SERVER_KEY,
        'Content-Type: application/json'
    ];
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, FCM_URL);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
    
    $result = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    
    if ($httpCode !== 200) {
        throw new Exception("FCM request failed with HTTP code: $httpCode");
    }
    
    $response = json_decode($result, true);
    if (!$response || isset($response['error'])) {
        throw new Exception('FCM error: ' . ($response['error'] ?? 'Unknown error'));
    }
    
    return $response;
}

// API Endpoint Usage Examples:

// Send notification to specific user
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $data = apiRequireJson();
    
    $userId = $data['userId'] ?? '';
    $title = $data['title'] ?? 'SS Transways India';
    $body = $data['body'] ?? '';
    $notificationData = $data['data'] ?? [];
    
    if (empty($userId) || empty($body)) {
        apiRespond(400, ['status' => 'error', 'error' => 'Missing required fields: userId and body']);
    }
    
    try {
        // Get FCM token for user
        $stmt = $mysqli->prepare("SELECT fcm_token FROM user_fcm_tokens WHERE user_id = ? AND platform = 'mobile'");
        $stmt->bind_param("s", $userId);
        $stmt->execute();
        $result = $stmt->get_result();
        
        if ($result->num_rows === 0) {
            apiRespond(404, ['status' => 'error', 'error' => 'FCM token not found for user']);
        }
        
        $row = $result->fetch_assoc();
        $fcmToken = $row['fcm_token'];
        
        // Send notification
        $response = sendPushNotification($fcmToken, $title, $body, $notificationData);
        
        apiRespond(200, [
            'status' => 'ok',
            'message' => 'Push notification sent successfully',
            'fcm_response' => $response
        ]);
        
    } catch (Exception $e) {
        error_log("Push notification error: " . $e->getMessage());
        apiRespond(500, [
            'status' => 'error',
            'error' => 'Failed to send push notification: ' . $e->getMessage()
        ]);
    }
}

// Send notification to multiple users (broadcast)
function sendBroadcastNotification($title, $body, $data = []) {
    global $mysqli;
    
    try {
        // Get all FCM tokens
        $result = $mysqli->query("SELECT fcm_token FROM user_fcm_tokens WHERE platform = 'mobile' AND fcm_token IS NOT NULL AND fcm_token != ''");
        
        if ($result->num_rows === 0) {
            throw new Exception('No FCM tokens found');
        }
        
        $tokens = [];
        while ($row = $result->fetch_assoc()) {
            $tokens[] = $row['fcm_token'];
        }
        
        // Send to all tokens (FCM supports up to 1000 tokens per request)
        $chunks = array_chunk($tokens, 1000);
        $responses = [];
        
        foreach ($chunks as $chunk) {
            $notification = [
                'title' => $title,
                'body' => $body,
                'sound' => 'default',
                'icon' => 'ic_launcher'
            ];
            
            $payload = [
                'registration_ids' => $chunk,
                'notification' => $notification,
                'data' => $data,
                'priority' => 'high'
            ];
            
            $headers = [
                'Authorization: key=' . FCM_SERVER_KEY,
                'Content-Type: application/json'
            ];
            
            $ch = curl_init();
            curl_setopt($ch, CURLOPT_URL, FCM_URL);
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
            
            $result = curl_exec($ch);
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);
            
            if ($httpCode === 200) {
                $responses[] = json_decode($result, true);
            }
        }
        
        return $responses;
        
    } catch (Exception $e) {
        throw new Exception('Broadcast notification failed: ' . $e->getMessage());
    }
}

// Usage examples for different notification types:

// Trip notification
function sendTripNotification($userId, $vehicleNumber, $type, $kmReading = null) {
    $title = "Trip $type";
    $body = "Trip $type for vehicle $vehicleNumber";
    if ($kmReading) {
        $body .= " at KM $kmReading";
    }
    
    $data = [
        'type' => 'trip',
        'vehicle_number' => $vehicleNumber,
        'trip_type' => $type,
        'km_reading' => $kmReading ?? '',
        'timestamp' => date('Y-m-d H:i:s')
    ];
    
    return sendPushNotification(getUserFCMToken($userId), $title, $body, $data);
}

// Attendance notification
function sendAttendanceNotification($userId, $type) {
    $title = "Attendance $type";
    $body = "Your $type has been recorded successfully";
    
    $data = [
        'type' => 'attendance',
        'attendance_type' => $type,
        'timestamp' => date('Y-m-d H:i:s')
    ];
    
    return sendPushNotification(getUserFCMToken($userId), $title, $body, $data);
}

// Salary notification
function sendSalaryNotification($userId, $amount, $type = 'credit') {
    $title = "Salary $type";
    $body = "Salary of ₹$amount has been $type successfully";
    
    $data = [
        'type' => 'salary',
        'amount' => $amount,
        'salary_type' => $type,
        'timestamp' => date('Y-m-d H:i:s')
    ];
    
    return sendPushNotification(getUserFCMToken($userId), $title, $body, $data);
}

// Helper function to get user FCM token
function getUserFCMToken($userId) {
    global $mysqli;
    
    $stmt = $mysqli->prepare("SELECT fcm_token FROM user_fcm_tokens WHERE user_id = ? AND platform = 'mobile'");
    $stmt->bind_param("s", $userId);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows > 0) {
        $row = $result->fetch_assoc();
        return $row['fcm_token'];
    }
    
    throw new Exception('FCM token not found for user: ' . $userId);
}
?>
