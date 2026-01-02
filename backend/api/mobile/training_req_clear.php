<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Accept, Origin');

require __DIR__ . '/common.php';

apiEnsurePost();

$data = apiRequireJson();
$userId = apiSanitizeInt($data['userId'] ?? $data['id'] ?? null);
$username = trim((string)($data['username'] ?? ''));

if ((!$userId || $userId <= 0) && $username === '') {
    apiRespond(400, ['status' => 'error', 'error' => 'userId or username is required']);
}

try {
    if ($userId && $userId > 0) {
        $stmt = $conn->prepare('UPDATE users SET training_req = \'N\' WHERE id = ?');
        if (!$stmt) {
            throw new RuntimeException('Failed to prepare statement');
        }
        $stmt->bind_param('i', $userId);
    } else {
        $stmt = $conn->prepare('UPDATE users SET training_req = \'N\' WHERE username = ?');
        if (!$stmt) {
            throw new RuntimeException('Failed to prepare statement');
        }
        $stmt->bind_param('s', $username);
    }
    $stmt->execute();
    $affected = $stmt->affected_rows;
    $stmt->close();

    if ($affected <= 0) {
        // Either user not found, or already N; verify user exists.
        $check = ($userId && $userId > 0)
            ? $conn->prepare('SELECT id, training_req FROM users WHERE id = ? LIMIT 1')
            : $conn->prepare('SELECT id, training_req FROM users WHERE username = ? LIMIT 1');
        if (!$check) {
            throw new RuntimeException('Failed to prepare check statement');
        }
        if ($userId && $userId > 0) {
            $check->bind_param('i', $userId);
        } else {
            $check->bind_param('s', $username);
        }
        $check->execute();
        $row = $check->get_result()->fetch_assoc();
        $check->close();
        if (!$row) {
            apiRespond(404, ['status' => 'error', 'error' => 'User not found']);
        }
    }

    apiRespond(200, [
        'status' => 'ok',
        'userId' => $userId,
        'training_req' => 'N',
        'trainingRequired' => false,
    ]);
} catch (Throwable $e) {
    apiRespond(500, ['status' => 'error', 'error' => $e->getMessage()]);
}

