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

$leaveRequestId = apiSanitizeInt($data['leaveRequestId'] ?? null);
$requestedById = apiSanitizeInt($data['requestedById'] ?? null);

if (!$leaveRequestId || !$requestedById) {
    apiRespond(400, [
        'status' => 'error',
        'error' => 'leaveRequestId and requestedById are required',
    ]);
}

try {
    $stmt = $conn->prepare(
        'SELECT id, status, requested_by_id
         FROM leave_requests
         WHERE id = ?
         LIMIT 1'
    );
    $stmt->bind_param('i', $leaveRequestId);
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$row) {
        apiRespond(404, ['status' => 'error', 'error' => 'Leave request not found']);
    }

    $ownerId = (int)($row['requested_by_id'] ?? 0);
    if ($ownerId !== $requestedById) {
        apiRespond(403, ['status' => 'error', 'error' => 'Not allowed to delete this request']);
    }

    $status = strtolower(trim((string)($row['status'] ?? '')));
    if (!in_array($status, ['draft', 'pending'], true)) {
        apiRespond(409, [
            'status' => 'error',
            'error' => 'Only draft or pending requests can be deleted',
        ]);
    }

    $del = $conn->prepare('DELETE FROM leave_requests WHERE id = ? LIMIT 1');
    $del->bind_param('i', $leaveRequestId);
    $del->execute();
    $del->close();

    apiRespond(200, [
        'status' => 'ok',
        'leaveRequestId' => $leaveRequestId,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
