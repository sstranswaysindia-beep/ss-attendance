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

$driverId = apiSanitizeInt($_POST['driverId'] ?? null);

if (!$driverId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId is required']);
}

if (empty($_FILES['photo']) || $_FILES['photo']['error'] !== UPLOAD_ERR_OK) {
    apiRespond(400, ['status' => 'error', 'error' => 'photo file is required']);
}

try {
    // Get current profile photo URL to delete old image
    $stmt = $conn->prepare('SELECT profile_photo_url FROM drivers WHERE id = ?');
    $stmt->bind_param('i', $driverId);
    $stmt->execute();
    $result = $stmt->get_result();
    $oldPhotoUrl = null;
    if ($row = $result->fetch_assoc()) {
        $oldPhotoUrl = $row['profile_photo_url'];
    }
    $stmt->close();

    // Delete old profile photo if it exists
    if ($oldPhotoUrl && !empty($oldPhotoUrl)) {
        $oldPhotoPath = $_SERVER['DOCUMENT_ROOT'] . $oldPhotoUrl;
        if (file_exists($oldPhotoPath)) {
            unlink($oldPhotoPath);
        }
    }

    $photoUrl = apiSaveUploadedFile('photo', $driverId, 'profile');
    if (!$photoUrl) {
        throw new RuntimeException('Unable to store uploaded photo');
    }

    $stmt = $conn->prepare('UPDATE drivers SET profile_photo_url = ? WHERE id = ?');
    $stmt->bind_param('si', $photoUrl, $driverId);
    $stmt->execute();
    $stmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'photoUrl' => $photoUrl,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
