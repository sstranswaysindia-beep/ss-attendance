<?php
require_once 'common.php';

// Handle file upload for user profile photos (supervisors without driver_id)
apiEnsurePost();

$userId = $_POST['userId'] ?? '';

if (empty($userId)) {
    apiRespond(400, ['status' => 'error', 'error' => 'Missing userId']);
}

// Check if user exists and is a supervisor
$userStmt = $conn->prepare("SELECT id, username, role FROM users WHERE id = ? LIMIT 1");
$userStmt->bind_param("s", $userId);
$userStmt->execute();
$userResult = $userStmt->get_result();

if ($userResult->num_rows === 0) {
    apiRespond(404, ['status' => 'error', 'error' => 'User not found']);
}

$user = $userResult->fetch_assoc();
$userStmt->close();

if ($user['role'] !== 'supervisor') {
    apiRespond(403, ['status' => 'error', 'error' => 'Only supervisors can upload profile photos here']);
}

// Handle file upload
if (!isset($_FILES['photo']) || $_FILES['photo']['error'] !== UPLOAD_ERR_OK) {
    apiRespond(400, ['status' => 'error', 'error' => 'No photo file uploaded or upload error']);
}

$uploadedFile = $_FILES['photo'];

// Validate file type - more comprehensive checking
$allowedTypes = ['image/jpeg', 'image/jpg', 'image/png'];
$allowedExtensions = ['jpg', 'jpeg', 'png'];
$fileType = $uploadedFile['type'];
$fileName = $uploadedFile['name'];
$fileExtension = strtolower(pathinfo($fileName, PATHINFO_EXTENSION));

// Check both MIME type and file extension
$isValidMimeType = in_array($fileType, $allowedTypes);
$isValidExtension = in_array($fileExtension, $allowedExtensions);

if (!$isValidMimeType && !$isValidExtension) {
    apiRespond(400, ['status' => 'error', 'error' => 'Invalid file type. Only JPEG and PNG allowed. Detected type: ' . $fileType . ', extension: ' . $fileExtension]);
}

// Validate file size (max 5MB)
$maxSize = 5 * 1024 * 1024; // 5MB
if ($uploadedFile['size'] > $maxSize) {
    apiRespond(400, ['status' => 'error', 'error' => 'File too large. Maximum size is 5MB']);
}

try {
    // Use the same directory structure as drivers for consistency
    $baseDir = realpath(__DIR__ . '/../../DriverDocs/uploads');
    if ($baseDir === false) {
        $baseDir = __DIR__ . '/../../DriverDocs/uploads';
        if (!is_dir($baseDir)) {
            mkdir($baseDir, 0755, true);
        }
    }
    
    $userDir = $baseDir . '/' . $userId;
    if (!is_dir($userDir)) {
        mkdir($userDir, 0755, true);
    }
    
    // Generate filename with same format as drivers
    $extension = pathinfo($uploadedFile['name'], PATHINFO_EXTENSION) ?: 'jpg';
    $extension = preg_replace('/[^a-zA-Z0-9]+/', '', $extension) ?: 'jpg';
    $fileName = sprintf('profile_%s_%d.%s', $userId, time(), strtolower($extension));
    
    $targetPath = $userDir . '/' . $fileName;
    
    // Move uploaded file
    if (!move_uploaded_file($uploadedFile['tmp_name'], $targetPath)) {
        throw new Exception('Failed to move uploaded file');
    }
    
    // Return relative path from uploads directory (same as drivers)
    $relativePath = "/DriverDocs/uploads/$userId/$fileName";
    $fullUrl = "https://sstranswaysindia.com$relativePath";
    
    // Update user record with profile photo URL
    $updateStmt = $conn->prepare("UPDATE users SET profile_photo = ? WHERE id = ?");
    if (!$updateStmt) {
        throw new Exception('Failed to prepare update statement: ' . $conn->error);
    }
    
    $updateStmt->bind_param("si", $fullUrl, $userId);
    if (!$updateStmt->execute()) {
        throw new Exception('Failed to update profile photo in database: ' . $updateStmt->error);
    }
    $updateStmt->close();
    
    apiRespond(200, [
        'status' => 'ok',
        'message' => 'Profile photo uploaded successfully',
        'photoUrl' => $fullUrl,
        'userId' => $userId
    ]);
    
} catch (Exception $e) {
    error_log("User profile photo upload error: " . $e->getMessage());
    apiRespond(500, ['status' => 'error', 'error' => 'Failed to upload profile photo: ' . $e->getMessage()]);
}
?>
