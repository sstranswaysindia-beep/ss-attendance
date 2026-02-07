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
$userId = apiSanitizeInt($data['userId'] ?? null);
$limit = apiSanitizeInt($data['limit'] ?? 50);
$limit = $limit && $limit > 0 ? min($limit, 200) : 50;

if (!$userId) {
    apiRespond(400, ['status' => 'error', 'error' => 'userId is required']);
}

function column_exists(mysqli $db, string $table, string $column): bool {
    $tableEsc = $db->real_escape_string($table);
    $columnEsc = $db->real_escape_string($column);
    $sql = "
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = '{$tableEsc}'
          AND COLUMN_NAME = '{$columnEsc}'
        LIMIT 1
    ";
    $res = $db->query($sql);
    $exists = $res && $res->num_rows > 0;
    if ($res instanceof mysqli_result) {
        $res->free();
    }
    return $exists;
}

try {
    $hasFullName = column_exists($conn, 'users', 'full_name');
    $hasNameCol = column_exists($conn, 'users', 'name');
    if ($hasFullName && $hasNameCol) {
        $assignedLabel = 'COALESCE(ua.full_name, ua.name, ua.username)';
        $responsibleLabel = 'COALESCE(ur.full_name, ur.name, ur.username)';
    } elseif ($hasFullName) {
        $assignedLabel = 'COALESCE(ua.full_name, ua.username)';
        $responsibleLabel = 'COALESCE(ur.full_name, ur.username)';
    } elseif ($hasNameCol) {
        $assignedLabel = 'COALESCE(ua.name, ua.username)';
        $responsibleLabel = 'COALESCE(ur.name, ur.username)';
    } else {
        $assignedLabel = 'ua.username';
        $responsibleLabel = 'ur.username';
    }

    $driverIdStmt = $conn->prepare('SELECT driver_id FROM users WHERE id = ?');
    $driverIdStmt->bind_param('i', $userId);
    $driverIdStmt->execute();
    $driverIdRow = $driverIdStmt->get_result()->fetch_assoc();
    $driverIdStmt->close();
    $driverId = (int)($driverIdRow['driver_id'] ?? 0);

    $countStmt = $conn->prepare("
        SELECT COUNT(*) AS cnt
        FROM driver_tasks
        WHERE (responsible_user_id = ? OR (driver_id = ? AND ? > 0))
          AND LOWER(status) <> 'closed'
    ");
    $countStmt->bind_param('iii', $userId, $driverId, $driverId);
    $countStmt->execute();
    $countRow = $countStmt->get_result()->fetch_assoc();
    $countStmt->close();
    $openCount = (int)($countRow['cnt'] ?? 0);

    $sql = "
        SELECT
            t.id,
            t.task_date,
            t.status,
            t.priority,
            t.task_description,
            t.vehicle_number,
            t.location,
            t.starting_date,
            t.scheduled_end_date,
            t.actual_end_date,
            t.tasker_remarks,
            t.driver_id,
            d.name AS driver_name,
            d.empid AS driver_empid,
            v.vehicle_no AS vehicle_no,
            ua.username AS assigned_by_username,
            {$assignedLabel} AS assigned_by_label,
            ur.username AS responsible_username,
            {$responsibleLabel} AS responsible_label
        FROM driver_tasks t
        LEFT JOIN users ua ON ua.id = t.assigned_by_user_id
        LEFT JOIN users ur ON ur.id = t.responsible_user_id
        LEFT JOIN drivers d ON d.id = t.driver_id
        LEFT JOIN vehicles v ON v.id = t.vehicle_id
        WHERE (t.responsible_user_id = ? OR (t.driver_id = ? AND ? > 0))
          AND LOWER(t.status) <> 'closed'
        ORDER BY t.task_date DESC, t.id DESC
        LIMIT {$limit}
    ";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param('iii', $userId, $driverId, $driverId);
    $stmt->execute();
    $rows = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'count' => $openCount,
        'tasks' => $rows,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
