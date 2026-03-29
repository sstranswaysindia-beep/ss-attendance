<?php
declare(strict_types=1);

require_once __DIR__ . '/common.php';

const MOBILE_NOTIFICATION_TABLE = 'mobile_notification_inbox';

function notificationInboxEnsureTable(): void {
    global $conn;

    static $checked = false;
    if ($checked) {
        return;
    }

    $conn->query(
        "CREATE TABLE IF NOT EXISTS `" . MOBILE_NOTIFICATION_TABLE . "` (
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
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"
    );

    $checked = true;
}

function notificationInboxDecodeData(?string $raw): array {
    if ($raw === null || trim($raw) === '') {
        return [];
    }

    $decoded = json_decode($raw, true);
    return is_array($decoded) ? $decoded : [];
}

apiEnsurePost();
notificationInboxEnsureTable();

$data = apiRequireJson();
$action = strtolower(trim((string) ($data['action'] ?? 'list')));
$userId = trim((string) ($data['userId'] ?? ''));
$notificationId = apiSanitizeInt($data['notificationId'] ?? null);
$limit = apiSanitizeInt($data['limit'] ?? 50) ?? 50;
$limit = max(1, min($limit, 100));

if ($userId === '') {
    apiRespond(400, ['status' => 'error', 'error' => 'Missing required field: userId']);
}

if ($action === 'list') {
    $stmt = $conn->prepare(
        "SELECT id, title, body, data_json, source, scope, status, sender_username, created_at
         FROM `" . MOBILE_NOTIFICATION_TABLE . "`
         WHERE recipient_user_id = ?
           AND dismissed_at IS NULL
           AND status = 'sent'
         ORDER BY id DESC
         LIMIT ?"
    );
    $stmt->bind_param('si', $userId, $limit);
    $stmt->execute();
    $result = $stmt->get_result();

    $notifications = [];
    while ($row = $result->fetch_assoc()) {
        $notifications[] = [
            'id' => (string) $row['id'],
            'title' => (string) ($row['title'] ?? ''),
            'body' => (string) ($row['body'] ?? ''),
            'data' => notificationInboxDecodeData($row['data_json'] ?? null),
            'source' => (string) ($row['source'] ?? ''),
            'scope' => (string) ($row['scope'] ?? ''),
            'status' => (string) ($row['status'] ?? ''),
            'senderUsername' => (string) ($row['sender_username'] ?? ''),
            'createdAt' => (string) ($row['created_at'] ?? ''),
        ];
    }
    $stmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'notifications' => $notifications,
    ]);
}

if ($action === 'remove') {
    if ($notificationId === null || $notificationId <= 0) {
        apiRespond(400, ['status' => 'error', 'error' => 'Missing required field: notificationId']);
    }

    $stmt = $conn->prepare(
        "UPDATE `" . MOBILE_NOTIFICATION_TABLE . "`
         SET dismissed_at = NOW()
         WHERE id = ?
           AND recipient_user_id = ?
         LIMIT 1"
    );
    $stmt->bind_param('is', $notificationId, $userId);
    $stmt->execute();
    $affected = $stmt->affected_rows;
    $stmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'removed' => $affected > 0,
    ]);
}

if ($action === 'clear') {
    $stmt = $conn->prepare(
        "UPDATE `" . MOBILE_NOTIFICATION_TABLE . "`
         SET dismissed_at = NOW()
         WHERE recipient_user_id = ?
           AND dismissed_at IS NULL"
    );
    $stmt->bind_param('s', $userId);
    $stmt->execute();
    $affected = $stmt->affected_rows;
    $stmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'cleared' => $affected,
    ]);
}

apiRespond(400, ['status' => 'error', 'error' => 'Unsupported action']);
