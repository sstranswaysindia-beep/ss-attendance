<?php
declare(strict_types=1);

require __DIR__ . '/../../../conf/config.php';

function apiRespond(int $status, array $payload): void {
    http_response_code($status);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function apiSanitizeInt($value): ?int {
    if ($value === null) {
        return null;
    }
    if (is_numeric($value)) {
        return (int) $value;
    }
    return null;
}

function apiRequireJson(): array {
    $raw = file_get_contents('php://input');
    $data = json_decode($raw ?: '', true);
    if (!is_array($data)) {
        $data = $_POST;
    }
    return $data;
}

function apiEnsurePost(): void {
    if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
        http_response_code(204);
        exit;
    }
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        apiRespond(405, ['status' => 'error', 'error' => 'Method not allowed']);
    }
}

function apiSaveUploadedFile(string $field, int $driverId, string $prefix): ?string {
    if (empty($_FILES[$field]) || $_FILES[$field]['error'] !== UPLOAD_ERR_OK) {
        return null;
    }

    $baseDir = realpath(__DIR__ . '/../../DriverDocs/uploads');
    if ($baseDir === false) {
        throw new RuntimeException('Upload base directory not found.');
    }

    $driverDir = $baseDir . '/' . $driverId;
    if (!is_dir($driverDir)) {
        if (!mkdir($driverDir, 0755, true) && !is_dir($driverDir)) {
            throw new RuntimeException('Unable to create upload directory.');
        }
    }

    $extension = pathinfo($_FILES[$field]['name'], PATHINFO_EXTENSION) ?: 'jpg';
    $extension = preg_replace('/[^a-zA-Z0-9]+/', '', $extension) ?: 'jpg';
    $fileName = sprintf('%s_%d_%d.%s', $prefix, $driverId, time(), strtolower($extension));
    $targetPath = $driverDir . '/' . $fileName;

    if (!move_uploaded_file($_FILES[$field]['tmp_name'], $targetPath)) {
        throw new RuntimeException('Failed to move uploaded file.');
    }

    return "/DriverDocs/uploads/{$driverId}/{$fileName}";
}
