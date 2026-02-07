<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require __DIR__ . '/common.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    apiRespond(405, ['status' => 'error', 'error' => 'Method not allowed']);
}

$userId = apiSanitizeInt($_GET['userId'] ?? null);
if (!$userId) {
    apiRespond(400, ['status' => 'error', 'error' => 'userId is required']);
}

$stmt = $conn->prepare('SELECT advance_entry FROM users WHERE id = ? LIMIT 1');
if (!$stmt) {
    apiRespond(500, ['status' => 'error', 'error' => 'Failed to prepare query']);
}
$stmt->bind_param('i', $userId);
$stmt->execute();
$row = $stmt->get_result()->fetch_assoc();
$stmt->close();

if (!$row) {
    apiRespond(404, ['status' => 'error', 'error' => 'user_not_found']);
}

apiRespond(200, [
    'status' => 'ok',
    'advance_entry' => $row['advance_entry'] ?? null,
]);
