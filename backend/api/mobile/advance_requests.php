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

$driverId = apiSanitizeInt($_GET['driverId'] ?? null);
$status   = trim($_GET['status'] ?? '');

if (!$driverId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId is required']);
}

$allowedStatuses = ['', 'Pending', 'Approved', 'Rejected', 'Disbursed'];
if (!in_array($status, $allowedStatuses, true)) {
    apiRespond(400, ['status' => 'error', 'error' => 'Invalid status filter']);
}

try {
    if ($status === '') {
        $stmt = $conn->prepare(
            'SELECT id, amount, purpose, status, requested_at, approval_by_id, approval_at, disbursed_at, remarks
               FROM advance_requests
              WHERE driver_id = ?
           ORDER BY requested_at DESC, id DESC'
        );
        $stmt->bind_param('i', $driverId);
    } else {
        $stmt = $conn->prepare(
            'SELECT id, amount, purpose, status, requested_at, approval_by_id, approval_at, disbursed_at, remarks
               FROM advance_requests
              WHERE driver_id = ? AND status = ?
           ORDER BY requested_at DESC, id DESC'
        );
        $stmt->bind_param('is', $driverId, $status);
    }

    $stmt->execute();
    $result = $stmt->get_result();
    $items = [];
    while ($row = $result->fetch_assoc()) {
        $items[] = [
            'advanceRequestId' => (int)$row['id'],
            'amount'           => (float)$row['amount'],
            'purpose'          => $row['purpose'],
            'status'           => $row['status'],
            'requestedAt'      => $row['requested_at'],
            'approvalById'     => $row['approval_by_id'],
            'approvalAt'       => $row['approval_at'],
            'disbursedAt'      => $row['disbursed_at'],
            'remarks'          => $row['remarks'],
        ];
    }
    $stmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'driverId' => $driverId,
        'filterStatus' => $status ?: null,
        'advanceRequests' => $items,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
