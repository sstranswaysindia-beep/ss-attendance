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

// Enhanced logging for receipt upload debugging
$logFile = __DIR__ . '/../logs/receipt_upload_debug.log';
$logDir = dirname($logFile);
if (!is_dir($logDir)) {
    mkdir($logDir, 0755, true);
}

function logReceiptDebug($message, $data = null) {
    global $logFile;
    $timestamp = date('Y-m-d H:i:s');
    $logMessage = "[$timestamp] $message";
    if ($data !== null) {
        $logMessage .= " | Data: " . json_encode($data, JSON_UNESCAPED_UNICODE);
    }
    $logMessage .= "\n";
    file_put_contents($logFile, $logMessage, FILE_APPEND | LOCK_EX);
    error_log($logMessage);
}

logReceiptDebug("=== RECEIPT UPLOAD API REQUEST START ===");
logReceiptDebug("Request Method", $_SERVER['REQUEST_METHOD']);
logReceiptDebug("Content Type", $_SERVER['CONTENT_TYPE'] ?? 'Not set');
logReceiptDebug("Request Headers", getallheaders());
logReceiptDebug("POST Data", $_POST);
logReceiptDebug("FILES Data", $_FILES);

apiEnsurePost();

// Check if file was uploaded
if (!isset($_FILES['receipt']) || $_FILES['receipt']['error'] !== UPLOAD_ERR_OK) {
    logReceiptDebug("File upload error", [
        'files_set' => isset($_FILES['receipt']),
        'upload_error' => $_FILES['receipt']['error'] ?? 'No file',
        'upload_errors' => [
            UPLOAD_ERR_OK => 'UPLOAD_ERR_OK',
            UPLOAD_ERR_INI_SIZE => 'UPLOAD_ERR_INI_SIZE',
            UPLOAD_ERR_FORM_SIZE => 'UPLOAD_ERR_FORM_SIZE',
            UPLOAD_ERR_PARTIAL => 'UPLOAD_ERR_PARTIAL',
            UPLOAD_ERR_NO_FILE => 'UPLOAD_ERR_NO_FILE',
            UPLOAD_ERR_NO_TMP_DIR => 'UPLOAD_ERR_NO_TMP_DIR',
            UPLOAD_ERR_CANT_WRITE => 'UPLOAD_ERR_CANT_WRITE',
            UPLOAD_ERR_EXTENSION => 'UPLOAD_ERR_EXTENSION'
        ]
    ]);
    apiRespond(400, ['status' => 'error', 'error' => 'No file uploaded or upload error']);
}

$transactionId = apiSanitizeInt($_POST['transactionId'] ?? null);
$driverId = apiSanitizeInt($_POST['driverId'] ?? null);

logReceiptDebug("Receipt Upload Parameters", [
    'transactionId' => $transactionId,
    'driverId' => $driverId,
    'file_info' => $_FILES['receipt']
]);

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
    logReceiptDebug("File type validation failed", [
        'fileType' => $fileType,
        'fileExtension' => $fileExtension,
        'validMimeType' => $validMimeType,
        'validExtension' => $validExtension,
        'allowedMimeTypes' => $allowedMimeTypes,
        'allowedExtensions' => $allowedExtensions
    ]);
    apiRespond(400, ['status' => 'error', 'error' => 'Invalid file type. Only JPEG, PNG, GIF, and PDF are allowed. Detected: ' . $fileType . ' / ' . $fileExtension]);
}

logReceiptDebug("File validation passed", [
    'fileType' => $fileType,
    'fileExtension' => $fileExtension,
    'fileSize' => $_FILES['receipt']['size']
]);

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
    
    logReceiptDebug("Directory creation attempt", [
        'uploadDir' => $uploadDir,
        'documentRoot' => $_SERVER['DOCUMENT_ROOT'],
        'driverId' => $driverId,
        'date' => $date,
        'dirExists' => is_dir($uploadDir)
    ]);
    
    if (!is_dir($uploadDir)) {
        if (!mkdir($uploadDir, 0755, true)) {
            logReceiptDebug("Directory creation failed", [
                'uploadDir' => $uploadDir,
                'permissions' => substr(sprintf('%o', fileperms(dirname($uploadDir))), -4)
            ]);
            apiRespond(500, ['status' => 'error', 'error' => 'Failed to create upload directory']);
        }
        logReceiptDebug("Directory created successfully", ['uploadDir' => $uploadDir]);
    }

    // Generate unique filename
    $fileExtension = pathinfo($_FILES['receipt']['name'], PATHINFO_EXTENSION);
    $fileName = 'receipt_' . $transactionId . '_' . time() . '.' . $fileExtension;
    $filePath = $uploadDir . '/' . $fileName;
    $relativePath = "/DriverDocs/uploads/receipts/{$driverId}/{$date}/{$fileName}";

    // Move uploaded file
    logReceiptDebug("File move attempt", [
        'source' => $_FILES['receipt']['tmp_name'],
        'destination' => $filePath,
        'sourceExists' => file_exists($_FILES['receipt']['tmp_name']),
        'isUploadedFile' => is_uploaded_file($_FILES['receipt']['tmp_name'])
    ]);
    
    if (!move_uploaded_file($_FILES['receipt']['tmp_name'], $filePath)) {
        logReceiptDebug("File move failed", [
            'source' => $_FILES['receipt']['tmp_name'],
            'destination' => $filePath,
            'error' => error_get_last()
        ]);
        apiRespond(500, ['status' => 'error', 'error' => 'Failed to save file']);
    }

    logReceiptDebug("File moved successfully", [
        'filePath' => $filePath,
        'fileSize' => filesize($filePath)
    ]);

    // Update transaction with receipt path
    $updateStmt = $conn->prepare('UPDATE advance_transactions SET receipt_path = ? WHERE id = ?');
    $updateStmt->bind_param('si', $relativePath, $transactionId);
    $updateStmt->execute();
    $updateStmt->close();

    $response = [
        'status' => 'ok',
        'message' => 'Receipt uploaded successfully',
        'receiptPath' => $relativePath,
        'transactionId' => $transactionId
    ];
    
    logReceiptDebug("Receipt upload success", $response);
    apiRespond(200, $response);

} catch (Throwable $error) {
    logReceiptDebug("ERROR OCCURRED", [
        'message' => $error->getMessage(),
        'file' => $error->getFile(),
        'line' => $error->getLine(),
        'trace' => $error->getTraceAsString()
    ]);
    
    $errorResponse = ['status' => 'error', 'error' => $error->getMessage()];
    logReceiptDebug("Error Response", $errorResponse);
    apiRespond(500, $errorResponse);
}
