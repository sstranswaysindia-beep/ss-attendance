<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/common.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
$action = strtolower(trim($_REQUEST['action'] ?? ($method === 'POST' ? ($_POST['action'] ?? '') : ($_GET['action'] ?? ''))));
if ($action === '') {
    $action = 'status';
}

/**
 * @return array{today: DateTimeImmutable, monthKey: string, windowLabel: string, isOpen: bool, targetMonth: DateTimeImmutable, reason: string|null}
 */
function meterCurrentWindow(): array {
    $tz = new DateTimeZone('Asia/Kolkata');
    $today = new DateTimeImmutable('now', $tz);
    $day = (int) $today->format('j');
    $lastDay = (int) $today->format('t');

    $windowLabel = 'closed';
    $isOpen = false;
    $targetMonth = $today;
    $reason = null;

    if ($day === 1) {
        $windowLabel = 'first_day';
        $isOpen = true;
        $targetMonth = $today->modify('-1 month');
    } elseif ($day === $lastDay) {
        $windowLabel = 'last_day';
        $isOpen = true;
        $targetMonth = $today;
    } else {
        $windowLabel = 'closed';
        $isOpen = false;
        $targetMonth = $today->modify('-1 month');
        $reason = 'Submissions are allowed only on the last day of the month or the first day of next month.';
    }

    $monthKey = $targetMonth->format('Y-m');

    return [
        'today' => $today,
        'monthKey' => $monthKey,
        'windowLabel' => $windowLabel,
        'isOpen' => $isOpen,
        'targetMonth' => $targetMonth,
        'reason' => $reason,
    ];
}

/**
 * @param array<string, mixed> $userRow
 * @return array<int, array<string, mixed>>
 */
function meterFetchAccessibleVehicles(mysqli $conn, array $userRow): array {
    $role = strtolower(trim((string) ($userRow['role'] ?? '')));
    $vehicles = [];

    if ($role === 'driver' && !empty($userRow['driver_id'])) {
        $driverId = (int) $userRow['driver_id'];
        // Determine active assignment(s) for driver
        $assignmentStmt = $conn->prepare(
            'SELECT plant_id, vehicle_id FROM assignments WHERE driver_id = ? ORDER BY assigned_date DESC'
        );
        $plantId = null;
        $assignmentVehicleIds = [];
        if ($assignmentStmt) {
            $assignmentStmt->bind_param('i', $driverId);
            $assignmentStmt->execute();
            $assignmentResult = $assignmentStmt->get_result();
            while ($row = $assignmentResult->fetch_assoc()) {
                if (!empty($row['plant_id']) && $plantId === null) {
                    $plantId = (int) $row['plant_id'];
                }
                if (!empty($row['vehicle_id'])) {
                    $assignmentVehicleIds[] = (int) $row['vehicle_id'];
                }
            }
            $assignmentStmt->close();
        }

        if ($plantId === null) {
            $driverStmt = $conn->prepare('SELECT plant_id FROM drivers WHERE id = ? LIMIT 1');
            if ($driverStmt) {
                $driverStmt->bind_param('i', $driverId);
                $driverStmt->execute();
                $plantValue = $driverStmt->get_result()->fetch_column();
                $driverStmt->close();
                if ($plantValue) {
                    $plantId = (int) $plantValue;
                }
            }
        }

        if ($plantId !== null) {
            $vehicleStmt = $conn->prepare('SELECT id, vehicle_no, plant_id, plant_name FROM (
                    SELECT v.id, v.vehicle_no, v.plant_id, p.plant_name
                      FROM vehicles v
                 LEFT JOIN plants p ON p.id = v.plant_id
                     WHERE v.plant_id = ?
                 ) AS plant_vehicles
                 WHERE plant_id = ?
                 ORDER BY vehicle_no ASC');
            if ($vehicleStmt) {
                $vehicleStmt->bind_param('ii', $plantId, $plantId);
                $vehicleStmt->execute();
                $result = $vehicleStmt->get_result();
                while ($row = $result->fetch_assoc()) {
                    $vehicles[] = [
                        'vehicle_id' => (int) $row['id'],
                        'vehicle_no' => (string) ($row['vehicle_no'] ?? ''),
                        'plant_id' => isset($row['plant_id']) ? (int) $row['plant_id'] : null,
                        'plant_name' => (string) ($row['plant_name'] ?? ''),
                        'is_primary' => in_array((int) $row['id'], $assignmentVehicleIds, true),
                    ];
                }
                $vehicleStmt->close();
            }
        }
    } elseif ($role === 'supervisor') {
        $supervisedPlantIds = [];
        $plantStmt = $conn->prepare("
            SELECT DISTINCT p.id, p.plant_name
              FROM plants p
         LEFT JOIN supervisor_plants sp ON sp.plant_id = p.id
             WHERE p.supervisor_user_id = ? OR sp.user_id = ?
          ORDER BY p.plant_name ASC
        ");
        if ($plantStmt) {
            $plantStmt->bind_param('ii', $userRow['id'], $userRow['id']);
            $plantStmt->execute();
            $result = $plantStmt->get_result();
            while ($row = $result->fetch_assoc()) {
                $plantId = (int) $row['id'];
                $supervisedPlantIds[] = $plantId;
            }
            $plantStmt->close();
        }

        if (!empty($supervisedPlantIds)) {
            $placeholders = implode(',', array_fill(0, count($supervisedPlantIds), '?'));
            $types = str_repeat('i', count($supervisedPlantIds));
            $vehicleStmt = $conn->prepare(
                "SELECT v.id,
                        v.vehicle_no,
                        v.plant_id,
                        p.plant_name
                   FROM vehicles v
              LEFT JOIN plants p ON p.id = v.plant_id
                  WHERE v.plant_id IN ($placeholders)
               ORDER BY p.plant_name ASC, v.vehicle_no ASC"
            );
            if ($vehicleStmt) {
                $vehicleStmt->bind_param($types, ...$supervisedPlantIds);
                $vehicleStmt->execute();
                $result = $vehicleStmt->get_result();
                while ($row = $result->fetch_assoc()) {
                    $vehicles[] = [
                        'vehicle_id' => (int) $row['id'],
                        'vehicle_no' => (string) ($row['vehicle_no'] ?? ''),
                        'plant_id' => isset($row['plant_id']) ? (int) $row['plant_id'] : null,
                        'plant_name' => (string) ($row['plant_name'] ?? ''),
                    ];
                }
                $vehicleStmt->close();
            }
        }
    } else {
        // Admin or fallback: expose all vehicles
        $vehicleStmt = $conn->prepare('SELECT v.id, v.vehicle_no, v.plant_id, p.plant_name FROM vehicles v LEFT JOIN plants p ON p.id = v.plant_id ORDER BY p.plant_name ASC, v.vehicle_no ASC');
        if ($vehicleStmt) {
            $vehicleStmt->execute();
            $result = $vehicleStmt->get_result();
            while ($row = $result->fetch_assoc()) {
                $vehicles[] = [
                    'vehicle_id' => (int) $row['id'],
                    'vehicle_no' => (string) ($row['vehicle_no'] ?? ''),
                    'plant_id' => isset($row['plant_id']) ? (int) $row['plant_id'] : null,
                    'plant_name' => (string) ($row['plant_name'] ?? ''),
                ];
            }
            $vehicleStmt->close();
        }
    }

    // Filter out entries without plant_id (cannot categorise)
    $vehicles = array_values(array_filter($vehicles, static function (array $vehicle): bool {
        return isset($vehicle['vehicle_id'], $vehicle['vehicle_no']) && $vehicle['vehicle_id'] > 0;
    }));

    return $vehicles;
}

/**
 * @param array<int, array<string, mixed>> $vehicles
 * @return array<int, array<string, mixed>>
 */
function meterEnsureMonthlyStatus(mysqli $conn, array $vehicles, string $monthKey): array {
    if (empty($vehicles)) {
        return [];
    }

    $dueDate = DateTimeImmutable::createFromFormat('Y-m', $monthKey);
    if ($dueDate === false) {
        $dueDate = new DateTimeImmutable('first day of this month');
    }
    $dueDate = $dueDate->modify('last day of this month');
    $dueDateSql = $dueDate->format('Y-m-d');

    $insertStmt = $conn->prepare(
        'INSERT INTO meter_monthly_status (vehicle_id, plant_id, month_key, due_date, window)
         VALUES (?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE plant_id = VALUES(plant_id)'
    );

    if ($insertStmt) {
        foreach ($vehicles as $vehicle) {
            $vehicleId = (int) $vehicle['vehicle_id'];
            $plantId = isset($vehicle['plant_id']) ? (int) $vehicle['plant_id'] : 0;
            $window = 'both';
            $insertStmt->bind_param('iisss', $vehicleId, $plantId, $monthKey, $dueDateSql, $window);
            $insertStmt->execute();
        }
        $insertStmt->close();
    }

    $ids = array_column($vehicles, 'vehicle_id');
    $placeholders = implode(',', array_fill(0, count($ids), '?'));
    $types = str_repeat('i', count($ids));

    $statusStmt = $conn->prepare("
        SELECT mms.vehicle_id,
               mms.plant_id,
               mms.month_key,
               mms.due_date,
               mms.window,
               mms.status,
               mms.submission_id,
               mrl.reading_km,
               mrl.photo_url,
               mrl.notes,
               mrl.driver_id,
               mrl.submitted_at,
               mrl.status AS submission_status,
               d.name AS driver_name
          FROM meter_monthly_status mms
     LEFT JOIN meter_reading_logs mrl ON mrl.id = mms.submission_id
     LEFT JOIN drivers d ON d.id = mrl.driver_id
         WHERE mms.month_key = ?
           AND mms.vehicle_id IN ($placeholders)
      ORDER BY mms.vehicle_id ASC
    ");

    $rows = [];
    if ($statusStmt) {
        $statusStmt->bind_param('s' . $types, $monthKey, ...$ids);
        $statusStmt->execute();
        $rows = $statusStmt->get_result()->fetch_all(MYSQLI_ASSOC);
        $statusStmt->close();
    }

    $rowsByVehicle = [];
    foreach ($rows as $row) {
        $rowsByVehicle[(int) $row['vehicle_id']] = $row;
    }

    $result = [];
    foreach ($vehicles as $vehicle) {
        $vehicleId = (int) $vehicle['vehicle_id'];
        $stored = $rowsByVehicle[$vehicleId] ?? null;
        $result[] = [
            'vehicle_id' => $vehicleId,
            'vehicle_no' => $vehicle['vehicle_no'],
            'plant_id' => $vehicle['plant_id'] ?? null,
            'plant_name' => $vehicle['plant_name'] ?? '',
            'status' => $stored['status'] ?? 'due',
            'due_date' => $stored['due_date'] ?? $dueDateSql,
            'window' => $stored['window'] ?? 'both',
            'reading_km' => $stored['reading_km'] ?? null,
            'photo_url' => $stored['photo_url'] ?? null,
            'notes' => $stored['notes'] ?? null,
            'driver_id' => isset($stored['driver_id']) ? (int) $stored['driver_id'] : null,
            'driver_name' => $stored['driver_name'] ?? null,
            'submitted_at' => $stored['submitted_at'] ?? null,
            'submission_status' => $stored['submission_status'] ?? null,
            'submission_id' => isset($stored['submission_id']) ? (int) $stored['submission_id'] : null,
        ];
    }

    return $result;
}

/**
 * @param array<int, array<string, mixed>> $rows
 * @return array<int, array<string, mixed>>
 */
function meterGroupByPlant(array $rows): array {
    $grouped = [];
    foreach ($rows as $row) {
        $plantId = $row['plant_id'] ?? 0;
        if (!isset($grouped[$plantId])) {
            $grouped[$plantId] = [
                'plantId' => $plantId,
                'plantName' => $row['plant_name'] ?? '',
                'vehicles' => [],
            ];
        }
        $status = strtolower((string) ($row['status'] ?? 'due'));
        $statusLabel = match ($status) {
            'submitted' => 'Submitted',
            'late' => 'Late',
            'missed' => 'Missed',
            'pending' => 'Pending',
            default => 'Pending',
        };
        $grouped[$plantId]['vehicles'][] = [
            'vehicleId' => $row['vehicle_id'],
            'vehicleNumber' => $row['vehicle_no'],
            'status' => $status,
            'statusLabel' => $statusLabel,
            'readingKm' => $row['reading_km'],
            'submittedAt' => $row['submitted_at'],
            'photoUrl' => $row['photo_url'],
            'notes' => $row['notes'],
            'driverId' => $row['driver_id'],
            'driverName' => $row['driver_name'],
            'submissionStatus' => $row['submission_status'],
            'submissionId' => $row['submission_id'],
        ];
    }

    return array_values($grouped);
}

/**
 * @return array{path: string, url: string}
 */
function meterSavePhoto(string $field): array {
    if (empty($_FILES[$field]) || $_FILES[$field]['error'] !== UPLOAD_ERR_OK) {
        throw new RuntimeException('Photo upload is required');
    }

    $baseDir = realpath(__DIR__ . '/../../DriverDocs/uploads');
    if ($baseDir === false) {
        throw new RuntimeException('Upload base directory not found.');
    }

    $tz = new DateTimeZone('Asia/Kolkata');
    $dateFolder = (new DateTimeImmutable('now', $tz))->format('Y-m-d');
    $meterDir = $baseDir . '/meter/' . $dateFolder;
    if (!is_dir($meterDir)) {
        if (!mkdir($meterDir, 0755, true) && !is_dir($meterDir)) {
            throw new RuntimeException('Unable to create directory: ' . $meterDir);
        }
    }

    $filename = bin2hex(random_bytes(10)) . '.jpg';
    $targetPath = $meterDir . '/' . $filename;

    $tmpPath = $_FILES[$field]['tmp_name'];
    $imageData = file_get_contents($tmpPath);
    if ($imageData === false) {
        throw new RuntimeException('Unable to read uploaded file');
    }

    $image = imagecreatefromstring($imageData);
    if ($image === false) {
        throw new RuntimeException('Unsupported image format');
    }

    // Handle EXIF orientation for JPEG
    if (function_exists('exif_read_data')) {
        $exif = @exif_read_data($tmpPath);
        if (!empty($exif['Orientation'])) {
            switch ($exif['Orientation']) {
                case 3:
                    $image = imagerotate($image, 180, 0);
                    break;
                case 6:
                    $image = imagerotate($image, -90, 0);
                    break;
                case 8:
                    $image = imagerotate($image, 90, 0);
                    break;
            }
        }
    }

    if (!imagejpeg($image, $targetPath, 80)) {
        imagedestroy($image);
        throw new RuntimeException('Failed to save compressed image');
    }
    imagedestroy($image);

    $relativePath = '/DriverDocs/uploads/meter/' . $dateFolder . '/' . $filename;
    return ['path' => $targetPath, 'url' => $relativePath];
}

/**
 * Respond with status payload.
 */
function meterRespondWithStatus(mysqli $conn, array $userRow, array $window): void {
    $vehicles = meterFetchAccessibleVehicles($conn, $userRow);
    $rows = meterEnsureMonthlyStatus($conn, $vehicles, $window['monthKey']);
    $grouped = meterGroupByPlant($rows);

    $pendingCount = 0;
    foreach ($grouped as $section) {
        foreach ($section['vehicles'] as $vehicle) {
            if ($vehicle['status'] === 'due' || $vehicle['status'] === 'pending') {
                $pendingCount++;
            }
        }
    }

    apiRespond(200, [
        'status' => 'ok',
        'data' => [
            'monthKey' => $window['monthKey'],
            'window' => [
                'label' => $window['windowLabel'],
                'isOpen' => $window['isOpen'],
                'reason' => $window['reason'],
                'currentDate' => $window['today']->format('Y-m-d'),
            ],
            'sections' => $grouped,
            'pendingCount' => $pendingCount,
        ],
    ]);
}

if (!isset($conn) || !$conn instanceof mysqli) {
    apiRespond(500, ['status' => 'error', 'error' => 'Database connection not available']);
}

$userId = apiSanitizeInt($_REQUEST['userId'] ?? $_POST['userId'] ?? null);
if (!$userId) {
    apiRespond(400, ['status' => 'error', 'error' => 'userId is required']);
}

$userStmt = $conn->prepare('SELECT id, role, driver_id, full_name FROM users WHERE id = ? LIMIT 1');
if (!$userStmt) {
    apiRespond(500, ['status' => 'error', 'error' => 'Unable to prepare user lookup']);
}
$userStmt->bind_param('i', $userId);
$userStmt->execute();
$userRow = $userStmt->get_result()->fetch_assoc();
$userStmt->close();

if (!$userRow) {
    apiRespond(404, ['status' => 'error', 'error' => 'User not found']);
}

$window = meterCurrentWindow();

switch ($action) {
    case 'status':
        meterRespondWithStatus($conn, $userRow, $window);
        break;

    case 'history':
        $vehicleId = apiSanitizeInt($_GET['vehicleId'] ?? $_POST['vehicleId'] ?? null);
        if (!$vehicleId) {
            apiRespond(400, ['status' => 'error', 'error' => 'vehicleId is required']);
        }
        $monthKey = $_GET['monthKey'] ?? $_POST['monthKey'] ?? $window['monthKey'];
        $limit = apiSanitizeInt($_GET['limit'] ?? $_POST['limit'] ?? 10) ?? 10;
        $limit = max(1, min($limit, 50));

        $historyStmt = $conn->prepare("
            SELECT mrl.id,
                   mrl.month_key,
                   mrl.reading_km,
                   mrl.photo_url,
                   mrl.notes,
                   mrl.status,
                   mrl.submitted_at,
                   mrl.reviewed_at,
                   mrl.review_note,
                   d.name AS driver_name,
                   mrl.source
              FROM meter_reading_logs mrl
         LEFT JOIN drivers d ON d.id = mrl.driver_id
             WHERE mrl.vehicle_id = ?
               AND mrl.month_key <= ?
          ORDER BY mrl.submitted_at DESC
             LIMIT ?
        ");
        if (!$historyStmt) {
            apiRespond(500, ['status' => 'error', 'error' => 'Unable to fetch history']);
        }
        $historyStmt->bind_param('isi', $vehicleId, $monthKey, $limit);
        $historyStmt->execute();
        $history = $historyStmt->get_result()->fetch_all(MYSQLI_ASSOC);
        $historyStmt->close();

        apiRespond(200, [
            'status' => 'ok',
            'data' => $history,
        ]);
        break;

    case 'submit':
        if ($method !== 'POST') {
            apiRespond(405, ['status' => 'error', 'error' => 'Method not allowed']);
        }

        if (!$window['isOpen']) {
            apiRespond(403, [
                'status' => 'error',
                'error' => 'window_closed',
                'message' => $window['reason'] ?? 'Submission window is closed',
            ]);
        }

        $driverId = apiSanitizeInt($_POST['driverId'] ?? $userRow['driver_id'] ?? null);
        if (!$driverId) {
            apiRespond(400, ['status' => 'error', 'error' => 'driverId is required']);
        }

        $vehicleId = apiSanitizeInt($_POST['vehicleId'] ?? null);
        if (!$vehicleId) {
            apiRespond(400, ['status' => 'error', 'error' => 'vehicleId is required']);
        }

        $readingKm = apiSanitizeFloat($_POST['readingKm'] ?? null);
        if ($readingKm === null || $readingKm < 0) {
            apiRespond(400, ['status' => 'error', 'error' => 'Valid readingKm is required']);
        }

        $notes = trim((string) ($_POST['notes'] ?? ''));

        $vehicles = meterFetchAccessibleVehicles($conn, $userRow);
        $vehicleMap = [];
        foreach ($vehicles as $vehicle) {
            $vehicleMap[(int) $vehicle['vehicle_id']] = $vehicle;
        }

        if (!isset($vehicleMap[$vehicleId])) {
            apiRespond(403, ['status' => 'error', 'error' => 'Vehicle not permitted for this user']);
        }

        $photo = meterSavePhoto('photo');

        $plantId = isset($vehicleMap[$vehicleId]['plant_id']) ? (int) $vehicleMap[$vehicleId]['plant_id'] : null;
        if (!$plantId) {
            // Best effort fetch
            $plantStmt = $conn->prepare('SELECT plant_id FROM vehicles WHERE id = ? LIMIT 1');
            if ($plantStmt) {
                $plantStmt->bind_param('i', $vehicleId);
                $plantStmt->execute();
                $plantId = $plantStmt->get_result()->fetch_column();
                $plantStmt->close();
            }
        }
        if (!$plantId) {
            $plantId = 0;
        }

        $conn->begin_transaction();
        try {
            $statusMonthKey = $window['monthKey'];
            $stmt = $conn->prepare("
                INSERT INTO meter_reading_logs (
                    vehicle_id,
                    driver_id,
                    month_key,
                    reading_km,
                    photo_url,
                    notes,
                    status,
                    submitted_at,
                    source
                ) VALUES (?, ?, ?, ?, ?, ?, 'submitted', NOW(), 'android')
            ");
            if (!$stmt) {
                throw new RuntimeException('Unable to prepare insert statement');
            }
            $stmt->bind_param(
                'iisdss',
                $vehicleId,
                $driverId,
                $statusMonthKey,
                $readingKm,
                $photo['url'],
                $notes
            );
            $stmt->execute();
            $submissionId = $stmt->insert_id;
            $stmt->close();

            $dueDate = DateTimeImmutable::createFromFormat('Y-m', $statusMonthKey) ?: new DateTimeImmutable();
            $dueDate = $dueDate->modify('last day of this month');
            $dueDateSql = $dueDate->format('Y-m-d');

            $statusStmt = $conn->prepare("
                INSERT INTO meter_monthly_status (
                    vehicle_id,
                    plant_id,
                    month_key,
                    due_date,
                    window,
                    submission_id,
                    status
                ) VALUES (?, ?, ?, ?, 'both', ?, 'submitted')
                ON DUPLICATE KEY UPDATE
                    plant_id = VALUES(plant_id),
                    submission_id = VALUES(submission_id),
                    status = 'submitted'
            ");
            if (!$statusStmt) {
                throw new RuntimeException('Unable to prepare status upsert');
            }
            $statusStmt->bind_param('iissi', $vehicleId, $plantId, $statusMonthKey, $dueDateSql, $submissionId);
            $statusStmt->execute();
            $statusStmt->close();

            $maintenanceStmt = $conn->prepare('UPDATE vehicle_maintenance SET current_km = ?, updated_at = NOW() WHERE vehicle_id = ?');
            if ($maintenanceStmt) {
                $maintenanceStmt->bind_param('di', $readingKm, $vehicleId);
                $maintenanceStmt->execute();
                $maintenanceStmt->close();
            }

            $conn->commit();

            meterRespondWithStatus($conn, $userRow, $window);
        } catch (Throwable $error) {
            $conn->rollback();
            apiRespond(500, [
                'status' => 'error',
                'error' => 'Unable to record meter reading',
                'message' => $error->getMessage(),
            ]);
        }
        break;

    default:
        apiRespond(400, ['status' => 'error', 'error' => 'Unsupported action']);
}
