<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require __DIR__ . '/common.php';

apiEnsurePost();

$data = apiRequireJson();
$taskId = apiSanitizeInt($data['taskId'] ?? null);
$userId = apiSanitizeInt($data['userId'] ?? null);
$statusRaw = trim((string)($data['status'] ?? ''));

if (!$taskId || !$userId) {
    apiRespond(400, ['status' => 'error', 'error' => 'taskId and userId are required']);
}

$statusKey = strtolower(trim($statusRaw));
if ($statusKey === 'completed') {
    $statusKey = 'closed';
}

$allowed = ['in-progress', 'closed'];
if (!in_array($statusKey, $allowed, true)) {
    apiRespond(400, ['status' => 'error', 'error' => 'Invalid status']);
}

try {
    $driverIdStmt = $conn->prepare('SELECT driver_id FROM users WHERE id = ?');
    $driverIdStmt->bind_param('i', $userId);
    $driverIdStmt->execute();
    $driverIdRow = $driverIdStmt->get_result()->fetch_assoc();
    $driverIdStmt->close();
    $driverId = (int)($driverIdRow['driver_id'] ?? 0);

    $taskStmt = $conn->prepare(
        'SELECT id, responsible_user_id, driver_id, starting_date, actual_end_date
         FROM driver_tasks WHERE id = ? LIMIT 1'
    );
    $taskStmt->bind_param('i', $taskId);
    $taskStmt->execute();
    $taskRow = $taskStmt->get_result()->fetch_assoc();
    $taskStmt->close();

    if (!$taskRow) {
        apiRespond(404, ['status' => 'error', 'error' => 'Task not found']);
    }

    $taskResponsible = (int)($taskRow['responsible_user_id'] ?? 0);
    $taskDriver = (int)($taskRow['driver_id'] ?? 0);
    $authorized = ($taskResponsible === $userId) || ($driverId > 0 && $taskDriver === $driverId);
    if (!$authorized) {
        apiRespond(403, ['status' => 'error', 'error' => 'Not allowed']);
    }

    $updates = ['status = ?'];
    $params = [$statusKey === 'closed' ? 'Closed' : 'In-Progress'];
    $types = 's';

    if ($statusKey === 'in-progress') {
        $updates[] = 'starting_date = CURDATE()';
    }
    if ($statusKey === 'closed') {
        $updates[] = 'actual_end_date = COALESCE(actual_end_date, CURDATE())';
    }

    $sql = 'UPDATE driver_tasks SET ' . implode(', ', $updates) . ' WHERE id = ? LIMIT 1';
    $params[] = $taskId;
    $types .= 'i';

    $updateStmt = $conn->prepare($sql);
    $updateStmt->bind_param($types, ...$params);
    $updateStmt->execute();
    $updateStmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'taskId' => $taskId,
        'taskStatus' => $params[0],
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
