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

if (!$driverId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId is required']);
}

try {
    $stmt = $conn->prepare(
        'SELECT id, amount, credited_on, reference_no, notes, created_at
           FROM salary_credits
          WHERE driver_id = ?
       ORDER BY credited_on DESC, id DESC'
    );
    $stmt->bind_param('i', $driverId);
    $stmt->execute();
    $result = $stmt->get_result();
    $entries = [];
    while ($row = $result->fetch_assoc()) {
        $entries[] = [
            'salaryCreditId' => (int)$row['id'],
            'amount'         => (float)$row['amount'],
            'creditedOn'     => $row['credited_on'],
            'referenceNo'    => $row['reference_no'],
            'notes'          => $row['notes'],
            'createdAt'      => $row['created_at'],
        ];
    }
    $stmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'driverId' => $driverId,
        'salaryCredits' => $entries,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
