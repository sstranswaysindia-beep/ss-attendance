<?php
declare(strict_types=1);

$configCandidates = [
    dirname(__DIR__, 2) . '/conf/config.php',
    dirname(__DIR__, 3) . '/conf/config.php',
];

$configLoaded = false;
foreach ($configCandidates as $configPath) {
    if (is_file($configPath)) {
        require_once $configPath;
        $configLoaded = true;
        break;
    }
}

if (!$configLoaded) {
    throw new RuntimeException(
        'Unable to locate conf/config.php. Tried paths: ' . implode(', ', $configCandidates)
    );
}

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

function apiSanitizeFloat($value): ?float {
    if ($value === null) {
        return null;
    }
    if (is_numeric($value)) {
        return (float) $value;
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

function apiSaveUploadedFile(string $field, int $driverId, string $prefix, ?string $customPath = null, ?string $customFilename = null): ?string {
    if (empty($_FILES[$field]) || $_FILES[$field]['error'] !== UPLOAD_ERR_OK) {
        return null;
    }

    $baseDir = realpath(__DIR__ . '/../../DriverDocs/uploads');
    if ($baseDir === false) {
        throw new RuntimeException('Upload base directory not found.');
    }

    // Use custom path if provided, otherwise use default driver ID folder
    if ($customPath !== null) {
        // Extract driver ID and date from custom path like "public_html/DriverDocs/uploads/169/2024-10-10/"
        $pathParts = explode('/', trim($customPath, '/'));
        $driverDir = $baseDir;
        foreach ($pathParts as $part) {
            if ($part && $part !== 'public_html' && $part !== 'DriverDocs' && $part !== 'uploads') {
                $driverDir .= '/' . $part;
            }
        }
    } else {
        $driverDir = $baseDir . '/' . $driverId;
    }

    if (!is_dir($driverDir)) {
        if (!mkdir($driverDir, 0755, true) && !is_dir($driverDir)) {
            throw new RuntimeException('Unable to create upload directory: ' . $driverDir);
        }
    }

    // Use custom filename if provided, otherwise generate default
    if ($customFilename !== null) {
        $fileName = $customFilename;
    } else {
        $extension = pathinfo($_FILES[$field]['name'], PATHINFO_EXTENSION) ?: 'jpg';
        $extension = preg_replace('/[^a-zA-Z0-9]+/', '', $extension) ?: 'jpg';
        $fileName = sprintf('%s_%d_%d.%s', $prefix, $driverId, time(), strtolower($extension));
    }
    
    $targetPath = $driverDir . '/' . $fileName;

    if (!move_uploaded_file($_FILES[$field]['tmp_name'], $targetPath)) {
        throw new RuntimeException('Failed to move uploaded file to: ' . $targetPath);
    }

    // Return relative path from uploads directory
    $relativePath = str_replace($baseDir, '', $driverDir) . '/' . $fileName;
    return "/DriverDocs/uploads" . $relativePath;
}

function apiBindParams(mysqli_stmt $stmt, string $types, array $values): void {
    if (strlen($types) !== count($values)) {
        throw new InvalidArgumentException('Parameter count does not match type definition.');
    }

    $references = [];
    foreach ($values as $index => $value) {
        $references[$index] = &$values[$index];
    }

    $stmt->bind_param($types, ...$references);
}
