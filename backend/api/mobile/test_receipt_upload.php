<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require __DIR__ . '/common.php';

// Test endpoint to check receipt upload functionality
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    // Return test information
    apiRespond(200, [
        'status' => 'ok',
        'message' => 'Receipt upload test API is working',
        'endpoints' => [
            'POST /test_receipt_upload.php' => 'Test file upload',
            'GET /test_receipt_upload.php' => 'This information'
        ],
        'supported_formats' => ['JPEG', 'PNG', 'GIF', 'PDF'],
        'max_file_size' => '5MB',
        'test_data' => [
            'transactionId' => '123',
            'driverId' => '169'
        ]
    ]);
}

// Test file upload
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Check if file was uploaded
    if (!isset($_FILES['receipt']) || $_FILES['receipt']['error'] !== UPLOAD_ERR_OK) {
        apiRespond(400, [
            'status' => 'error', 
            'error' => 'No file uploaded or upload error',
            'debug' => [
                'files_received' => $_FILES,
                'post_data' => $_POST
            ]
        ]);
    }

    $transactionId = $_POST['transactionId'] ?? 'test_123';
    $driverId = $_POST['driverId'] ?? '169';

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
        apiRespond(400, [
            'status' => 'error', 
            'error' => 'Invalid file type. Only JPEG, PNG, GIF, and PDF are allowed.',
            'debug' => [
                'detected_mime_type' => $fileType,
                'detected_extension' => $fileExtension,
                'allowed_mime_types' => $allowedMimeTypes,
                'allowed_extensions' => $allowedExtensions
            ]
        ]);
    }

    // Validate file size (max 5MB)
    $maxSize = 5 * 1024 * 1024; // 5MB
    if ($_FILES['receipt']['size'] > $maxSize) {
        apiRespond(400, [
            'status' => 'error', 
            'error' => 'File size too large. Maximum 5MB allowed',
            'debug' => [
                'file_size' => $_FILES['receipt']['size'],
                'max_size' => $maxSize
            ]
        ]);
    }

    try {
        // Create test directory structure
        $date = date('Y-m-d');
        $uploadDir = $_SERVER['DOCUMENT_ROOT'] . "/DriverDocs/uploads/receipts/{$driverId}/{$date}";
        
        if (!is_dir($uploadDir)) {
            if (!mkdir($uploadDir, 0755, true)) {
                apiRespond(500, [
                    'status' => 'error', 
                    'error' => 'Failed to create upload directory',
                    'debug' => [
                        'upload_dir' => $uploadDir,
                        'document_root' => $_SERVER['DOCUMENT_ROOT']
                    ]
                ]);
            }
        }

        // Generate unique filename
        $fileExtension = pathinfo($_FILES['receipt']['name'], PATHINFO_EXTENSION);
        $fileName = 'test_receipt_' . $transactionId . '_' . time() . '.' . $fileExtension;
        $filePath = $uploadDir . '/' . $fileName;
        $relativePath = "/DriverDocs/uploads/receipts/{$driverId}/{$date}/{$fileName}";

        // Move uploaded file
        if (!move_uploaded_file($_FILES['receipt']['tmp_name'], $filePath)) {
            apiRespond(500, [
                'status' => 'error', 
                'error' => 'Failed to save file',
                'debug' => [
                    'source' => $_FILES['receipt']['tmp_name'],
                    'destination' => $filePath,
                    'file_exists' => file_exists($_FILES['receipt']['tmp_name']),
                    'is_uploaded_file' => is_uploaded_file($_FILES['receipt']['tmp_name'])
                ]
            ]);
        }

        // Return success with detailed information
        apiRespond(200, [
            'status' => 'ok',
            'message' => 'Test receipt uploaded successfully',
            'data' => [
                'transactionId' => $transactionId,
                'driverId' => $driverId,
                'originalFileName' => $_FILES['receipt']['name'],
                'savedFileName' => $fileName,
                'filePath' => $filePath,
                'relativePath' => $relativePath,
                'fileSize' => $_FILES['receipt']['size'],
                'fileType' => $fileType,
                'fileExtension' => $fileExtension,
                'uploadTime' => date('Y-m-d H:i:s'),
                'url' => 'https://sstranswaysindia.com' . $relativePath
            ],
            'debug' => [
                'upload_dir_exists' => is_dir($uploadDir),
                'file_exists' => file_exists($filePath),
                'file_readable' => is_readable($filePath),
                'file_size_after_upload' => filesize($filePath)
            ]
        ]);

    } catch (Throwable $error) {
        apiRespond(500, [
            'status' => 'error', 
            'error' => $error->getMessage(),
            'debug' => [
                'error_type' => get_class($error),
                'error_file' => $error->getFile(),
                'error_line' => $error->getLine(),
                'trace' => $error->getTraceAsString()
            ]
        ]);
    }
}
?>
