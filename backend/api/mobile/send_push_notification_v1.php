<?php
require_once 'common.php';

// Firebase Cloud Messaging v1 API Configuration
const SERVICE_ACCOUNT_JSON_PATH = __DIR__ . '/firebase-adminsdk.json';
const FCM_V1_URL = 'https://fcm.googleapis.com/v1/projects/sstranswaysindia-26d47/messages:send';
const PROJECT_ID = 'sstranswaysindia-26d47';
const MOBILE_NOTIFICATION_TABLE = 'mobile_notification_inbox';

function ensureNotificationInboxTableExists() {
    global $conn;

    static $checked = false;
    if ($checked) {
        return;
    }

    $sql = "
        CREATE TABLE IF NOT EXISTS `" . MOBILE_NOTIFICATION_TABLE . "` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `recipient_user_id` VARCHAR(64) NOT NULL,
            `title` VARCHAR(255) NOT NULL DEFAULT '',
            `body` TEXT NOT NULL,
            `data_json` LONGTEXT NULL,
            `source` VARCHAR(64) NOT NULL DEFAULT 'push_api',
            `scope` VARCHAR(32) NOT NULL DEFAULT 'direct',
            `status` VARCHAR(32) NOT NULL DEFAULT 'queued',
            `sender_username` VARCHAR(100) NULL,
            `fcm_message_name` VARCHAR(255) NULL,
            `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `dismissed_at` DATETIME NULL DEFAULT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_mobile_notification_recipient` (`recipient_user_id`, `dismissed_at`, `created_at`),
            KEY `idx_mobile_notification_status` (`status`, `created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ";

    $conn->query($sql);
    $checked = true;
}

function normalizeNotificationData($data) {
    if (!is_array($data)) {
        return [];
    }

    $normalized = [];
    foreach ($data as $key => $value) {
        if (!is_scalar($value) && $value !== null) {
            $normalized[(string) $key] = json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            continue;
        }
        $normalized[(string) $key] = $value === null ? '' : (string) $value;
    }

    return $normalized;
}

function queueNotificationInbox($recipientUserId, $title, $body, $data = [], $scope = 'direct', $source = 'push_api', $senderUsername = null) {
    global $conn;

    ensureNotificationInboxTableExists();

    $dataJson = empty($data)
        ? null
        : json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

    $stmt = $conn->prepare(
        "INSERT INTO `" . MOBILE_NOTIFICATION_TABLE . "`
            (recipient_user_id, title, body, data_json, source, scope, status, sender_username)
         VALUES (?, ?, ?, ?, ?, ?, 'queued', ?)"
    );
    $stmt->bind_param(
        'sssssss',
        $recipientUserId,
        $title,
        $body,
        $dataJson,
        $source,
        $scope,
        $senderUsername
    );
    $stmt->execute();
    $id = (int) $stmt->insert_id;
    $stmt->close();

    return $id;
}

function updateNotificationInboxStatus($notificationId, $status, $fcmMessageName = null) {
    global $conn;

    ensureNotificationInboxTableExists();

    $stmt = $conn->prepare(
        "UPDATE `" . MOBILE_NOTIFICATION_TABLE . "`
         SET status = ?, fcm_message_name = ?
         WHERE id = ?
         LIMIT 1"
    );
    $stmt->bind_param('ssi', $status, $fcmMessageName, $notificationId);
    $stmt->execute();
    $stmt->close();
}

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
        $data = normalizeNotificationData($data);
        
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
function sendBroadcastNotification($title, $body, $data = [], $source = 'push_api', $senderUsername = null) {
    global $conn;
    
    try {
        // Get all FCM tokens
        $result = $conn->query("SELECT user_id, fcm_token FROM user_fcm_tokens WHERE platform = 'mobile' AND fcm_token IS NOT NULL AND fcm_token != ''");
        
        if ($result->num_rows === 0) {
            throw new Exception('No FCM tokens found');
        }
        
        $responses = [];
        $accessToken = getAccessToken();
        $baseData = normalizeNotificationData($data);
        
        while ($row = $result->fetch_assoc()) {
            $fcmToken = $row['fcm_token'];
            $recipientUserId = (string) ($row['user_id'] ?? '');
            if ($recipientUserId === '') {
                continue;
            }
            $notificationId = queueNotificationInbox(
                $recipientUserId,
                $title,
                $body,
                $baseData,
                'broadcast',
                $source,
                $senderUsername
            );
            $messageData = $baseData;
            $messageData['server_notification_id'] = (string) $notificationId;
            $messageData['notification_source'] = (string) $source;
            
            $message = [
                'message' => [
                    'token' => $fcmToken,
                    'notification' => [
                        'title' => $title,
                        'body' => $body
                    ],
                    'data' => $messageData,
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
                $decoded = json_decode($response, true);
                $responses[] = $decoded;
                updateNotificationInboxStatus(
                    $notificationId,
                    'sent',
                    (string) ($decoded['name'] ?? '')
                );
            } else {
                updateNotificationInboxStatus($notificationId, 'failed');
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
    $senderUsername = isset($data['senderUsername']) ? (string) $data['senderUsername'] : null;
    $source = isset($data['source']) && $data['source'] !== ''
        ? (string) $data['source']
        : 'push_api';
    
    if ($broadcast) {
        // Send broadcast notification
        if (empty($body)) {
            apiRespond(400, ['status' => 'error', 'error' => 'Missing required field: body']);
        }
        
        try {
            $response = sendBroadcastNotification($title, $body, $notificationData, $source, $senderUsername);
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
            $notificationId = queueNotificationInbox(
                (string) $userId,
                $title,
                $body,
                $notificationData,
                'direct',
                $source,
                $senderUsername
            );
            $messageData = normalizeNotificationData($notificationData);
            $messageData['server_notification_id'] = (string) $notificationId;
            $messageData['notification_source'] = (string) $source;

            // Get the latest valid FCM token for the user. If none exists,
            // keep the inbox entry so the app can still pick it up via polling.
            $stmt = $conn->prepare(
                "SELECT fcm_token
                 FROM user_fcm_tokens
                 WHERE user_id = ?
                   AND platform = 'mobile'
                   AND fcm_token IS NOT NULL
                   AND fcm_token <> ''
                 ORDER BY id DESC
                 LIMIT 1"
            );
            $stmt->bind_param("s", $userId);
            $stmt->execute();
            $result = $stmt->get_result();
            
            if ($result->num_rows === 0) {
                updateNotificationInboxStatus($notificationId, 'inbox_only');
                apiRespond(200, [
                    'status' => 'ok',
                    'message' => 'Notification queued in inbox; FCM token not found for user',
                    'notification_id' => $notificationId,
                    'delivery_mode' => 'inbox_only'
                ]);
            }
            
            $row = $result->fetch_assoc();
            $fcmToken = $row['fcm_token'];
            
            // Send notification
            $response = sendPushNotification($fcmToken, $title, $body, $messageData);
            updateNotificationInboxStatus(
                $notificationId,
                'sent',
                (string) ($response['name'] ?? '')
            );
            
            apiRespond(200, [
                'status' => 'ok',
                'message' => 'Push notification sent successfully',
                'notification_id' => $notificationId,
                'delivery_mode' => 'push',
                'fcm_response' => $response
            ]);
            
        } catch (Exception $e) {
            if (isset($notificationId) && (int) $notificationId > 0) {
                updateNotificationInboxStatus((int) $notificationId, 'failed');
            }
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
