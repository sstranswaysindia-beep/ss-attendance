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

function apiBuildProfileUrl(?string $path): string {
    if ($path === null) {
        return '';
    }
    $trimmed = trim($path);
    if ($trimmed === '') {
        return '';
    }
    if (stripos($trimmed, 'http://') === 0 || stripos($trimmed, 'https://') === 0) {
        return $trimmed;
    }
    $trimmed = ltrim($trimmed, '/');
    return 'https://sstranswaysindia.com/' . $trimmed;
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

function geofenceHaversineDistanceMeters(float $lat1, float $lng1, float $lat2, float $lng2): float {
    $earthRadius = 6371000.0; // meters
    $latFrom = deg2rad($lat1);
    $latTo = deg2rad($lat2);
    $latDelta = deg2rad($lat2 - $lat1);
    $lngDelta = deg2rad($lng2 - $lng1);

    $a = sin($latDelta / 2) * sin($latDelta / 2) +
        cos($latFrom) * cos($latTo) *
        sin($lngDelta / 2) * sin($lngDelta / 2);
    $c = 2 * atan2(sqrt($a), sqrt(1 - $a));
    return $earthRadius * $c;
}

/**
 * @param array<int, array{lat: float, lng: float}> $points
 */
function geofencePointInPolygon(float $lat, float $lng, array $points): bool {
    $numPoints = count($points);
    if ($numPoints < 3) {
        return false;
    }

    $inside = false;
    $x = $lng;
    $y = $lat;
    for ($i = 0, $j = $numPoints - 1; $i < $numPoints; $j = $i++) {
        $xi = $points[$i]['lng'];
        $yi = $points[$i]['lat'];
        $xj = $points[$j]['lng'];
        $yj = $points[$j]['lat'];

        $intersect = (($yi > $y) !== ($yj > $y)) &&
            ($x < ($xj - $xi) * ($y - $yi) / (($yj - $yi) ?: 1e-9) + $xi);
        if ($intersect) {
            $inside = !$inside;
        }
    }
    return $inside;
}

/**
 * @param mixed $rawPoints
 * @return array<int, array{lat: float, lng: float}>
 */
function geofenceNormalizePolygonPoints($rawPoints): array {
    if (!is_array($rawPoints)) {
        return [];
    }
    $normalized = [];
    foreach ($rawPoints as $point) {
        $lat = null;
        $lng = null;
        if (is_array($point)) {
            if (isset($point['lat'], $point['lng'])) {
                $lat = $point['lat'];
                $lng = $point['lng'];
            } elseif (count($point) >= 2) {
                $values = array_values($point);
                $lat = $values[0];
                $lng = $values[1];
            }
        }
        if ($lat !== null && $lng !== null && is_numeric($lat) && is_numeric($lng)) {
            $normalized[] = ['lat' => (float) $lat, 'lng' => (float) $lng];
        }
    }
    return $normalized;
}

/**
 * @return array<int, array<string, mixed>>
 */
function geofenceFetchActive(mysqli $conn, int $plantId): array {
    $stmt = $conn->prepare('SELECT id, fence_type, center_lat, center_lng, radius_m, polygon_json FROM plant_geofences WHERE plant_id = ? AND is_active = 1');
    if (!$stmt) {
        return [];
    }
    $stmt->bind_param('i', $plantId);
    $stmt->execute();
    $result = $stmt->get_result();
    $geofences = [];
    while ($row = $result->fetch_assoc()) {
        $fenceType = strtolower((string) ($row['fence_type'] ?? 'circle'));
        $radius = isset($row['radius_m']) ? (float) $row['radius_m'] : 120.0;
        $polygonRaw = $row['polygon_json'] ?? null;
        $polygonPoints = [];
        if ($polygonRaw !== null && $polygonRaw !== '') {
            $decoded = json_decode((string) $polygonRaw, true);
            $polygonPoints = geofenceNormalizePolygonPoints($decoded);
        }
        $geofences[] = [
            'id' => (int) $row['id'],
            'fence_type' => $fenceType,
            'center_lat' => isset($row['center_lat']) ? (float) $row['center_lat'] : null,
            'center_lng' => isset($row['center_lng']) ? (float) $row['center_lng'] : null,
            'radius' => $radius > 0 ? $radius : 120.0,
            'polygon_points' => $polygonPoints,
        ];
    }
    $stmt->close();
    return $geofences;
}

/**
 * @param array<string, mixed>|null $location
 * @return array{status: string, out_of_geofence: bool, message?: string}
 */
function geofenceEvaluate(
    mysqli $conn,
    int $plantId,
    ?array $location,
    bool $enforce
): array {
    $geofences = geofenceFetchActive($conn, $plantId);
    if ($enforce && empty($geofences)) {
        return [
            'status' => 'error',
            'out_of_geofence' => false,
            'message' => 'Geofence not configured for this plant. Contact administrator.',
        ];
    }

    if ($location === null) {
        if ($enforce) {
            return [
                'status' => 'error',
                'out_of_geofence' => false,
                'message' => 'Location is required for geofenced attendance. Enable GPS and try again.',
            ];
        }
        return ['status' => 'ok', 'out_of_geofence' => false];
    }

    if (!isset($location['latitude'], $location['longitude'])) {
        if ($enforce) {
            return [
                'status' => 'error',
                'out_of_geofence' => false,
                'message' => 'Invalid location payload received. Please retry.',
            ];
        }
        return ['status' => 'ok', 'out_of_geofence' => false];
    }

    $lat = (float) $location['latitude'];
    $lng = (float) $location['longitude'];
    $inside = false;

    foreach ($geofences as $geofence) {
        $type = $geofence['fence_type'];
        if ($type === 'circle') {
            if ($geofence['center_lat'] === null || $geofence['center_lng'] === null) {
                continue;
            }
            $distance = geofenceHaversineDistanceMeters(
                $lat,
                $lng,
                $geofence['center_lat'],
                $geofence['center_lng']
            );
            if ($distance <= $geofence['radius']) {
                $inside = true;
                break;
            }
        } elseif ($type === 'polygon') {
            if (empty($geofence['polygon_points'])) {
                continue;
            }
            if (geofencePointInPolygon($lat, $lng, $geofence['polygon_points'])) {
                $inside = true;
                break;
            }
        }
    }

    if (!$inside && $enforce) {
        return [
            'status' => 'error',
            'out_of_geofence' => true,
            'message' => 'You are outside the allowed geofence for this plant. Move closer to the site boundary and try again.',
        ];
    }

    return [
        'status' => 'ok',
        'out_of_geofence' => !$inside,
    ];
}
