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

// ── Auto-create table if missing ─────────────────────────────────────────
$conn->query("
    CREATE TABLE IF NOT EXISTS trip_sheets (
        id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        user_id         INT UNSIGNED NOT NULL,
        driver_id       INT UNSIGNED NULL,
        plant_id        INT UNSIGNED NOT NULL,
        plant_name      VARCHAR(255) NOT NULL DEFAULT '',
        vehicle_id      INT UNSIGNED NOT NULL,
        vehicle_number  VARCHAR(50) NOT NULL DEFAULT '',
        user_role       VARCHAR(30) NOT NULL DEFAULT 'driver',
        image_path      VARCHAR(500) NOT NULL DEFAULT '',
        notes           TEXT NULL,
        created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_user_date (user_id, created_at),
        INDEX idx_plant_date (plant_id, created_at),
        INDEX idx_vehicle_date (vehicle_id, created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
");

// ── Validate file upload ─────────────────────────────────────────────────
if (!isset($_FILES['trip_sheet']) || $_FILES['trip_sheet']['error'] !== UPLOAD_ERR_OK) {
    apiRespond(400, ['status' => 'error', 'error' => 'No image uploaded or upload error.']);
}

$allowedMimeTypes = ['image/jpeg', 'image/jpg', 'image/png'];
$allowedExtensions = ['jpg', 'jpeg', 'png'];

$fileType = $_FILES['trip_sheet']['type'];
$fileName = $_FILES['trip_sheet']['name'];
$fileExtension = strtolower(pathinfo($fileName, PATHINFO_EXTENSION));

if (!in_array($fileType, $allowedMimeTypes, true) && !in_array($fileExtension, $allowedExtensions, true)) {
    apiRespond(400, ['status' => 'error', 'error' => 'Invalid file type. Only JPEG and PNG images are allowed.']);
}

$maxSize = 10 * 1024 * 1024; // 10 MB
if ($_FILES['trip_sheet']['size'] > $maxSize) {
    apiRespond(400, ['status' => 'error', 'error' => 'File too large. Maximum 10 MB allowed.']);
}

// ── Validate required fields ─────────────────────────────────────────────
$userId        = apiSanitizeInt($_POST['user_id'] ?? null);
$driverId      = apiSanitizeInt($_POST['driver_id'] ?? null);
$plantId       = apiSanitizeInt($_POST['plant_id'] ?? null);
$plantName     = trim($_POST['plant_name'] ?? '');
$vehicleId     = apiSanitizeInt($_POST['vehicle_id'] ?? null);
$vehicleNumber = trim($_POST['vehicle_number'] ?? '');
$userRole      = trim($_POST['user_role'] ?? 'driver');
$captureDate   = trim($_POST['capture_date'] ?? '');
$notes         = trim($_POST['notes'] ?? '');

if (!$userId || $userId <= 0) {
    apiRespond(400, ['status' => 'error', 'error' => 'user_id is required.']);
}
if (!$plantId || $plantId <= 0) {
    apiRespond(400, ['status' => 'error', 'error' => 'plant_id is required.']);
}
if (!$vehicleId || $vehicleId <= 0) {
    apiRespond(400, ['status' => 'error', 'error' => 'vehicle_id is required.']);
}

$createdAt = date('Y-m-d H:i:s');
if ($captureDate !== '') {
    $captureDateObj = DateTimeImmutable::createFromFormat('Y-m-d', $captureDate);
    $captureErrors = DateTimeImmutable::getLastErrors();
    $hasDateError = $captureDateObj === false
        || ($captureErrors !== false && (($captureErrors['warning_count'] ?? 0) > 0 || ($captureErrors['error_count'] ?? 0) > 0));
    if ($hasDateError) {
        apiRespond(400, ['status' => 'error', 'error' => 'Invalid capture_date. Use YYYY-MM-DD format.']);
    }

    $createdAt = $captureDateObj->format('Y-m-d') . ' ' . date('H:i:s');
}

// ── Store file ───────────────────────────────────────────────────────────
$folderMonth = substr($createdAt, 0, 7);
$safeVehicleFolder = preg_replace('/[^a-zA-Z0-9_-]+/', '_', $vehicleNumber);
$safeVehicleFolder = trim((string)$safeVehicleFolder, '_');
if ($safeVehicleFolder === '') {
    $safeVehicleFolder = 'vehicle_' . $vehicleId;
}

$uploadBase = $_SERVER['DOCUMENT_ROOT'] . '/uploads/trip_sheets';
$uploadDir  = $uploadBase . '/' . $folderMonth . '/' . $safeVehicleFolder;

if (!is_dir($uploadDir)) {
    if (!mkdir($uploadDir, 0755, true) && !is_dir($uploadDir)) {
        apiRespond(500, ['status' => 'error', 'error' => 'Failed to create upload directory.']);
    }
}

$ext = pathinfo($_FILES['trip_sheet']['name'], PATHINFO_EXTENSION) ?: 'jpg';
$ext = preg_replace('/[^a-zA-Z0-9]+/', '', $ext) ?: 'jpg';
$savedName    = 'tripsheet_' . $vehicleId . '_' . time() . '.' . strtolower($ext);
$targetPath   = $uploadDir . '/' . $savedName;
$relativePath = '/uploads/trip_sheets/' . $folderMonth . '/' . $safeVehicleFolder . '/' . $savedName;

if (!move_uploaded_file($_FILES['trip_sheet']['tmp_name'], $targetPath)) {
    apiRespond(500, ['status' => 'error', 'error' => 'Failed to save uploaded file.']);
}

// ── Insert DB record ─────────────────────────────────────────────────────
try {
    $notesVal = $notes === '' ? null : $notes;
    $stmt = $conn->prepare(
        'INSERT INTO trip_sheets (user_id, driver_id, plant_id, plant_name, vehicle_id, vehicle_number, user_role, image_path, notes, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    );
    $stmt->bind_param(
        'iiisisssss',
        $userId,
        $driverId,
        $plantId,
        $plantName,
        $vehicleId,
        $vehicleNumber,
        $userRole,
        $relativePath,
        $notesVal,
        $createdAt
    );
    $stmt->execute();
    $insertId = $conn->insert_id;
    $stmt->close();

    $imageUrl = 'https://sstranswaysindia.com' . $relativePath;

    apiRespond(200, [
        'status'    => 'ok',
        'message'   => 'Trip sheet uploaded successfully.',
        'id'        => $insertId,
        'image_url' => $imageUrl,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
