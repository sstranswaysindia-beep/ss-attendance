<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/common.php';

apiEnsurePost();

$data = $_POST;
if (!$data || !isset($data['driverId'])) {
    $data = apiRequireJson();
}

$driverId = apiSanitizeInt($data['driverId'] ?? null);
$amount   = isset($data['amount']) ? (float)$data['amount'] : null;
$purpose  = trim((string)($data['purpose'] ?? ''));
$notes    = trim((string)($data['notes'] ?? ''));

if (!$driverId || $driverId <= 0) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId is required']);
}

if ($amount === null || $amount <= 0) {
    apiRespond(400, ['status' => 'error', 'error' => 'amount must be greater than zero']);
}

if ($purpose === '') {
    apiRespond(400, ['status' => 'error', 'error' => 'purpose is required']);
}

try {
    $driverStmt = $conn->prepare('SELECT id FROM drivers WHERE id = ? LIMIT 1');
    $driverStmt->bind_param('i', $driverId);
    $driverStmt->execute();
    if (!$driverStmt->get_result()->fetch_assoc()) {
        $driverStmt->close();
        apiRespond(404, ['status' => 'error', 'error' => 'Driver not found']);
    }
    $driverStmt->close();

$requestedAt = date('Y-m-d H:i:s');

    $stmt = $conn->prepare(
        'INSERT INTO advance_requests (
            driver_id,
            amount,
            purpose,
            status,
            requested_at,
            remarks
         ) VALUES (?, ?, ?, "Pending", ?, ?)' 
    );
    $stmt->bind_param('idsss', $driverId, $amount, $purpose, $requestedAt, $notes);
    $stmt->execute();
    $requestId = $stmt->insert_id;
    $stmt->close();

    apiRespond(201, [
        'status' => 'ok',
        'advanceRequestId' => (int)$requestId,
        'driverId' => $driverId,
        'amount' => $amount,
        'purpose' => $purpose,
        'notes' => $notes !== '' ? $notes : null,
        'requestedAt' => $requestedAt,
        'recordStatus' => 'Pending',
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
