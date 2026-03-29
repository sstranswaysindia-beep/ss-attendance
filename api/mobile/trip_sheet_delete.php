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

$userId = apiSanitizeInt($data['user_id'] ?? null);
$recordId = apiSanitizeInt($data['record_id'] ?? null);

if (!$userId || $userId <= 0) {
    apiRespond(400, ['status' => 'error', 'error' => 'user_id is required.']);
}

if (!$recordId || $recordId <= 0) {
    apiRespond(400, ['status' => 'error', 'error' => 'record_id is required.']);
}

$tableCheck = $conn->query("SHOW TABLES LIKE 'trip_sheets'");
if ($tableCheck->num_rows === 0) {
    apiRespond(404, ['status' => 'error', 'error' => 'Trip sheet records not found.']);
}

try {
    $select = $conn->prepare(
        'SELECT id, user_id, image_path, created_at FROM trip_sheets WHERE id = ? LIMIT 1'
    );
    $select->bind_param('i', $recordId);
    $select->execute();
    $result = $select->get_result();
    $record = $result->fetch_assoc();
    $select->close();

    if (!$record) {
        apiRespond(404, ['status' => 'error', 'error' => 'Trip sheet record not found.']);
    }

    $createdAt = DateTime::createFromFormat('Y-m-d H:i:s', (string) $record['created_at']);
    if (!$createdAt) {
        $createdAt = new DateTime((string) $record['created_at']);
    }

    $now = new DateTime('now');
    $deleteCutoff = new DateTime(sprintf('%04d-%02d-01 00:00:00', (int) $now->format('Y'), (int) $now->format('n')));
    $deleteCutoff->modify('-1 month');

    if ($createdAt < $deleteCutoff) {
        apiRespond(403, [
            'status' => 'error',
            'error' => 'Only current month and previous month trip sheet images can be deleted.',
        ]);
    }

    $delete = $conn->prepare('DELETE FROM trip_sheets WHERE id = ? LIMIT 1');
    $delete->bind_param('i', $recordId);
    $delete->execute();
    $affectedRows = $delete->affected_rows;
    $delete->close();

    if ($affectedRows < 1) {
        apiRespond(500, ['status' => 'error', 'error' => 'Unable to delete trip sheet record.']);
    }

    $imagePath = trim((string) ($record['image_path'] ?? ''));
    if ($imagePath !== '' && str_starts_with($imagePath, '/')) {
        $fullPath = rtrim((string) ($_SERVER['DOCUMENT_ROOT'] ?? ''), '/') . $imagePath;
        if ($fullPath !== '' && is_file($fullPath)) {
            @unlink($fullPath);
        }
    }

    apiRespond(200, ['status' => 'ok', 'message' => 'Trip sheet deleted.']);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
