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

// Check if file was uploaded
if (!isset($_FILES['receipt']) || $_FILES['receipt']['error'] !== UPLOAD_ERR_OK) {
    apiRespond(400, ['status' => 'error', 'error' => 'No file uploaded or upload error']);
}

$transactionId = apiSanitizeInt($_POST['transactionId'] ?? null);
$driverId = apiSanitizeInt($_POST['driverId'] ?? null);

if (!$transactionId || $transactionId <= 0) {
    apiRespond(400, ['status' => 'error', 'error' => 'transactionId is required']);
}

if (!$driverId || $driverId <= 0) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId is required']);
}

// Validate file type - check both MIME type and file extension
$allowedMimeTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'application/pdf'];
$allowedExtensions = ['jpg', 'jpeg', 'png', 'gif', 'pdf'];

$fileType = $_FILES['receipt']['type'];
$fileName = $_FILES['receipt']['name'];
$fileExtension = strtolower(pathinfo($fileName, PATHINFO_EXTENSION));

// Check MIME type
$validMimeType = in_array($fileType, $allowedMimeTypes, true);
// Check file extension
$validExtension = in_array($fileExtension, $allowedExtensions, true);

if (!$validMimeType && !$validExtension) {
    apiRespond(400, ['status' => 'error', 'error' => 'Invalid file type. Only JPEG, PNG, GIF, and PDF are allowed. Detected: ' . $fileType . ' / ' . $fileExtension]);
}

// Validate file size (max 5MB)
$maxSize = 5 * 1024 * 1024; // 5MB
if ($_FILES['receipt']['size'] > $maxSize) {
    apiRespond(400, ['status' => 'error', 'error' => 'File size too large. Maximum 5MB allowed']);
}

try {
    // Verify transaction exists and belongs to driver
    $stmt = $conn->prepare('SELECT id FROM advance_transactions WHERE id = ? AND driver_id = ? LIMIT 1');
    $stmt->bind_param('ii', $transactionId, $driverId);
    $stmt->execute();
    if (!$stmt->get_result()->fetch_assoc()) {
        $stmt->close();
        apiRespond(404, ['status' => 'error', 'error' => 'Transaction not found or access denied']);
    }
    $stmt->close();

    // Create directory structure: public_html/DriverDocs/uploads/receipts/<driverid>/<date>
    $date = date('Y-m-d');
    $uploadDir = $_SERVER['DOCUMENT_ROOT'] . "/DriverDocs/uploads/receipts/{$driverId}/{$date}";
    
    if (!is_dir($uploadDir)) {
        if (!mkdir($uploadDir, 0755, true)) {
            apiRespond(500, ['status' => 'error', 'error' => 'Failed to create upload directory']);
        }
    }

    // Generate unique filename
    $fileExtension = pathinfo($_FILES['receipt']['name'], PATHINFO_EXTENSION);
    $fileName = 'receipt_' . $transactionId . '_' . time() . '.' . $fileExtension;
    $filePath = $uploadDir . '/' . $fileName;
    $relativePath = "/DriverDocs/uploads/receipts/{$driverId}/{$date}/{$fileName}";

    // Move uploaded file
    if (!move_uploaded_file($_FILES['receipt']['tmp_name'], $filePath)) {
        apiRespond(500, ['status' => 'error', 'error' => 'Failed to save file']);
    }

    // Update transaction with receipt path
    $updateStmt = $conn->prepare('UPDATE advance_transactions SET receipt_path = ? WHERE id = ?');
    $updateStmt->bind_param('si', $relativePath, $transactionId);
    $updateStmt->execute();
    $updateStmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'message' => 'Receipt uploaded successfully',
        'receiptPath' => $relativePath,
        'transactionId' => $transactionId
    ]);

} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
