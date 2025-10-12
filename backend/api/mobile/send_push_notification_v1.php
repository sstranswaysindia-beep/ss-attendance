<?php
require_once 'common.php';

// Firebase Cloud Messaging v1 API Configuration
const SERVICE_ACCOUNT_JSON_PATH = __DIR__ . '/firebase-adminsdk.json';
const FCM_V1_URL = 'https://fcm.googleapis.com/v1/projects/sstranswaysindia-26d47/messages:send';
const PROJECT_ID = 'sstranswaysindia-26d47';

/**
 * Get OAuth2 Access Token using Service Account
 */
function getAccessToken() {
    if (!file_exists(SERVICE_ACCOUNT_JSON_PATH)) {
        throw new Exception('Firebase Admin SDK JSON file not found: ' . SERVICE_ACCOUNT_JSON_PATH);
    }
    
    $serviceAccount = json_decode(file_get_contents(SERVICE_ACCOUNT_JSON_PATH), true);
    
    $jwtHeader = json_encode(['typ' => 'JWT', 'alg' => 'RS256']);
    $jwtClaim = json_encode([
        'iss' => $serviceAccount['client_email'],
        'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
        'aud' => 'https://oauth2.googleapis.com/token',
        'exp' => time() + 3600,
        'iat' => time()
    ]);
    
    $jwtHeaderEncoded = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($jwtHeader));
    $jwtClaimEncoded = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($jwtClaim));
    $jwtSignature = '';
    
    $signatureData = $jwtHeaderEncoded . '.' . $jwtClaimEncoded;
    
    $privateKey = openssl_pkey_get_private($serviceAccount['private_key']);
    if (!$privateKey) {
        throw new Exception('Invalid private key');
    }
    
    openssl_sign($signatureData, $jwtSignature, $privateKey, OPENSSL_ALGO_SHA256);
    openssl_free_key($privateKey);
    
    $jwtSignatureEncoded = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($jwtSignature));
    $jwt = $signatureData . '.' . $jwtSignatureEncoded;
    
    // Request access token
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, 'https://oauth2.googleapis.com/token');
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query([
        'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion' => $jwt
    ]));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/x-www-form-urlencoded']);
    
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    
    if ($httpCode !== 200) {
        throw new Exception('Failed to get access token: ' . $response);
    }
    
    $tokenData = json_decode($response, true);
    return $tokenData['access_token'];
}

/**
 * Send Push Notification using FCM v1 API
 */
function sendPushNotification($fcmToken, $title, $body, $data = []) {
    try {
        $accessToken = getAccessToken();
        
        $message = [
            'message' => [
                'token' => $fcmToken,
                'notification' => [
                    'title' => $title,
                    'body' => $body
                ],
                'data' => $data,
                'android' => [
                    'notification' => [
                        'icon' => 'ic_launcher',
                        'sound' => 'default',
                        'channel_id' => 'trip_notifications'
                    ]
                ],
                'apns' => [
                    'payload' => [
                        'aps' => [
                            'sound' => 'default',
                            'badge' => 1
                        ]
                    ]
                ]
            ]
        ];
        
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, FCM_V1_URL);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Authorization: Bearer ' . $accessToken,
            'Content-Type: application/json'
        ]);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($message));
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        if ($httpCode !== 200) {
            throw new Exception('FCM v1 API request failed with HTTP code: ' . $httpCode . ' Response: ' . $response);
        }
        
        return json_decode($response, true);
        
    } catch (Exception $e) {
        throw new Exception('Failed to send push notification: ' . $e->getMessage());
    }
}

/**
 * Send notification to multiple users (broadcast)
 */
function sendBroadcastNotification($title, $body, $data = []) {
    global $conn;
    
    try {
        // Get all FCM tokens
        $result = $conn->query("SELECT fcm_token FROM user_fcm_tokens WHERE platform = 'mobile' AND fcm_token IS NOT NULL AND fcm_token != ''");
        
        if ($result->num_rows === 0) {
            throw new Exception('No FCM tokens found');
        }
        
        $responses = [];
        $accessToken = getAccessToken();
        
        while ($row = $result->fetch_assoc()) {
            $fcmToken = $row['fcm_token'];
            
            $message = [
                'message' => [
                    'token' => $fcmToken,
                    'notification' => [
                        'title' => $title,
                        'body' => $body
                    ],
                    'data' => $data,
                    'android' => [
                        'notification' => [
                            'icon' => 'ic_launcher',
                            'sound' => 'default',
                            'channel_id' => 'trip_notifications'
                        ]
                    ],
                    'apns' => [
                        'payload' => [
                            'aps' => [
                                'sound' => 'default',
                                'badge' => 1
                            ]
                        ]
                    ]
                ]
            ];
            
            $ch = curl_init();
            curl_setopt($ch, CURLOPT_URL, FCM_V1_URL);
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_HTTPHEADER, [
                'Authorization: Bearer ' . $accessToken,
                'Content-Type: application/json'
            ]);
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($message));
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            
            $response = curl_exec($ch);
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);
            
            if ($httpCode === 200) {
                $responses[] = json_decode($response, true);
            }
        }
        
        return $responses;
        
    } catch (Exception $e) {
        throw new Exception('Broadcast notification failed: ' . $e->getMessage());
    }
}

// API Endpoint for sending notifications
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $data = apiRequireJson();
    
    $userId = $data['userId'] ?? '';
    $title = $data['title'] ?? 'SS Transways India';
    $body = $data['body'] ?? '';
    $notificationData = $data['data'] ?? [];
    $broadcast = $data['broadcast'] ?? false;
    
    if ($broadcast) {
        // Send broadcast notification
        if (empty($body)) {
            apiRespond(400, ['status' => 'error', 'error' => 'Missing required field: body']);
        }
        
        try {
            $response = sendBroadcastNotification($title, $body, $notificationData);
            apiRespond(200, [
                'status' => 'ok',
                'message' => 'Broadcast notification sent successfully',
                'sent_to' => count($response),
                'responses' => $response
            ]);
        } catch (Exception $e) {
            apiRespond(500, ['status' => 'error', 'error' => $e->getMessage()]);
        }
    } else {
        // Send to specific user
        if (empty($userId) || empty($body)) {
            apiRespond(400, ['status' => 'error', 'error' => 'Missing required fields: userId and body']);
        }
        
        try {
            // Get FCM token for user
            $stmt = $conn->prepare("SELECT fcm_token FROM user_fcm_tokens WHERE user_id = ? AND platform = 'mobile'");
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
            apiRespond(500, ['status' => 'error', 'error' => $e->getMessage()]);
        }
    }
}

// Helper functions for specific notification types

/**
 * Send trip notification
 */
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

/**
 * Send attendance notification
 */
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

/**
 * Send salary notification
 */
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

/**
 * Get user FCM token
 */
function getUserFCMToken($userId) {
    global $conn;
    
    $stmt = $conn->prepare("SELECT fcm_token FROM user_fcm_tokens WHERE user_id = ? AND platform = 'mobile'");
    $stmt->bind_param("s", $userId);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows > 0) {
        $row = $result->fetch_assoc();
        return $row['fcm_token'];
    }
    
    throw new Exception('FCM token not found for user: ' . $userId);
}

// Example usage:
// To send a trip notification: sendTripNotification('user123', 'ABC123', 'started', '1000');
// To send attendance notification: sendAttendanceNotification('user123', 'check-in');
// To send salary notification: sendSalaryNotification('user123', '25000', 'credit');
?>
