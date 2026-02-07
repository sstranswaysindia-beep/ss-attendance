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

$driverId = apiSanitizeInt($data['driverId'] ?? null);
if (!$driverId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId is required']);
}

try {
    $stmt = $conn->prepare(
        'SELECT
            id,
            driver_id,
            document_type,
            document_name,
            file_path,
            local_path,
            google_drive_link,
            expiry_date,
            mime_type
         FROM driver_documents
         WHERE driver_id = ? AND is_active = 1
         ORDER BY upload_date DESC, id DESC'
    );
    $stmt->bind_param('i', $driverId);
    $stmt->execute();
    $result = $stmt->get_result();
    $rows = $result ? $result->fetch_all(MYSQLI_ASSOC) : [];
    $stmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'documents' => $rows,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
