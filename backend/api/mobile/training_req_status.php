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
        $stmt = $conn->prepare('SELECT id, training_req FROM users WHERE id = ? LIMIT 1');
        if (!$stmt) {
            throw new RuntimeException('Failed to prepare statement');
        }
        $stmt->bind_param('i', $userId);
    } else {
        $stmt = $conn->prepare('SELECT id, training_req FROM users WHERE username = ? LIMIT 1');
        if (!$stmt) {
            throw new RuntimeException('Failed to prepare statement');
        }
        $stmt->bind_param('s', $username);
    }
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$row) {
        apiRespond(404, ['status' => 'error', 'error' => 'User not found']);
    }

    $resolvedUserId = (int)($row['id'] ?? 0);
    $flag = strtoupper(trim((string)($row['training_req'] ?? 'N')));
    if ($flag !== 'Y' && $flag !== 'N') {
        $flag = 'N';
    }

    apiRespond(200, [
        'status' => 'ok',
        'userId' => $resolvedUserId > 0 ? $resolvedUserId : $userId,
        'training_req' => $flag,
        'trainingRequired' => ($flag === 'Y'),
    ]);
} catch (Throwable $e) {
    apiRespond(500, ['status' => 'error', 'error' => $e->getMessage()]);
}

