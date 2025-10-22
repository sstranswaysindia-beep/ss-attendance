<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require __DIR__ . '/common.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    apiRespond(405, ['status' => 'error', 'error' => 'Method not allowed']);
}

/**
 * Normalize boolean-like columns coming from database (Y/N, 1/0, etc).
 */
function normalizeFlag($raw): bool {
    if ($raw === null) {
        return false;
    }
    if (is_bool($raw)) {
        return $raw;
    }
    $string = strtolower(trim((string) $raw));
    return $string === 'y' || $string === 'yes' || $string === 'true' || $string === '1';
}

/**
 * Compute document status label based on expiry date.
 *
 * @return array{status: string, label: string, daysUntilExpiry: ?int}
 */
function computeDocumentStatus(
    ?string $expiryDate,
    DateTimeImmutable $today,
    DateTimeImmutable $dueSoonCutoff
): array {
    if ($expiryDate === null) {
        return ['status' => 'active', 'label' => 'Active', 'daysUntilExpiry' => null];
    }

    $trimmed = trim($expiryDate);
    if ($trimmed === '' || $trimmed === '0000-00-00') {
        return ['status' => 'active', 'label' => 'Active', 'daysUntilExpiry' => null];
    }

    try {
        $expiry = new DateTimeImmutable($trimmed);
    } catch (Throwable $error) {
        return ['status' => 'active', 'label' => 'Active', 'daysUntilExpiry' => null];
    }

    $diff = (int) $today->diff($expiry)->format('%r%a');
    if ($expiry < $today) {
        return ['status' => 'expired', 'label' => 'Expired', 'daysUntilExpiry' => $diff];
    }
    if ($expiry <= $dueSoonCutoff) {
        return ['status' => 'dueSoon', 'label' => 'Due Soon', 'daysUntilExpiry' => $diff];
    }

    return ['status' => 'active', 'label' => 'Active', 'daysUntilExpiry' => $diff];
}

/**
 * Add or update plant entry in lookup map.
 *
 * @param array<int, array<string, mixed>> $plantsById
 */
function registerPlant(array &$plantsById, ?int $plantId, ?string $plantName): void {
    if ($plantId === null) {
        return;
    }
    if (isset($plantsById[$plantId])) {
        if ($plantName !== null && $plantName !== '' && ($plantsById[$plantId]['plantName'] ?? '') === '') {
            $plantsById[$plantId]['plantName'] = $plantName;
        }
        return;
    }
    $plantsById[$plantId] = [
        'plantId' => $plantId,
        'plantName' => $plantName ?? '',
    ];
}

$userId = apiSanitizeInt($_GET['userId'] ?? $_GET['user_id'] ?? null);

if (!$userId) {
    apiRespond(400, ['status' => 'error', 'error' => 'userId is required']);
}

try {
    $userStmt = $conn->prepare('SELECT id, role, driver_id, view_document FROM users WHERE id = ? LIMIT 1');
    if (!$userStmt) {
        throw new RuntimeException('Failed to prepare user lookup statement.');
    }
    $userStmt->bind_param('i', $userId);
    $userStmt->execute();
    $userRow = $userStmt->get_result()->fetch_assoc();
    $userStmt->close();

    if (!$userRow) {
        apiRespond(404, ['status' => 'error', 'error' => 'User not found']);
    }

    if (!normalizeFlag($userRow['view_document'] ?? null)) {
        apiRespond(403, ['status' => 'error', 'error' => 'Documents access not permitted for this user']);
    }

    $role = strtolower(trim((string) ($userRow['role'] ?? '')));
    $driverIdFromUser = isset($userRow['driver_id']) ? (int) $userRow['driver_id'] : null;

    $plantsById = [];
    $plantIds = [];

    $plantsResult = $conn->query('SELECT id, plant_name FROM plants ORDER BY plant_name ASC');
    if ($plantsResult) {
        while ($plant = $plantsResult->fetch_assoc()) {
            $plantId = (int) $plant['id'];
            $plantName = $plant['plant_name'] ?? '';
            $plantsById[$plantId] = [
                'plantId' => $plantId,
                'plantName' => $plantName,
            ];
            $plantIds[] = $plantId;
        }
        $plantsResult->close();
    }

    $plantIds = array_values(array_unique(array_filter(array_map(
        static fn($value) => is_numeric($value) ? (int) $value : null,
        $plantIds
    ))));

    $vehicles = [];
    $vehicleIds = [];

    $vehicleStmt = $conn->prepare(
        'SELECT v.id,
                v.vehicle_no,
                v.plant_id,
                p.plant_name
           FROM vehicles v
      LEFT JOIN plants p ON p.id = v.plant_id
       ORDER BY p.plant_name ASC, v.vehicle_no ASC'
    );
    if ($vehicleStmt) {
        $vehicleStmt->execute();
        $vehicleResult = $vehicleStmt->get_result();
        while ($vehicle = $vehicleResult->fetch_assoc()) {
            $vehicleId = (int) $vehicle['id'];
            $plantId = isset($vehicle['plant_id']) ? (int) $vehicle['plant_id'] : null;
            $vehicleNumber = $vehicle['vehicle_no'] ?? '';
            $plantName = $vehicle['plant_name'] ?? '';
            registerPlant($plantsById, $plantId, $plantName);

            $vehicles[$vehicleId] = [
                'vehicleId' => $vehicleId,
                'vehicleNumber' => $vehicleNumber,
                'plantId' => $plantId,
                'plantName' => $plantName,
                'documents' => [],
            ];
            $vehicleIds[] = $vehicleId;
        }
        $vehicleStmt->close();
    }

    $drivers = [];
    $driverIds = [];
    $driverRolesAvailable = [];

    $driverStmt = $conn->prepare(
        "SELECT d.id,
                d.name,
                d.role,
                d.plant_id,
                d.docs_plant_id,
                d.status,
                p.plant_name
           FROM drivers d
      LEFT JOIN plants p ON p.id = d.plant_id
       ORDER BY p.plant_name ASC, d.name ASC"
    );
    if ($driverStmt) {
        $driverStmt->execute();
        $driverResult = $driverStmt->get_result();
        while ($driverRow = $driverResult->fetch_assoc()) {
            $driverId = (int) $driverRow['id'];
            $driverName = $driverRow['name'] ?? '';
            $driverRole = strtolower(trim((string) ($driverRow['role'] ?? 'driver')));
            $primaryPlantId = isset($driverRow['docs_plant_id']) && $driverRow['docs_plant_id'] !== null
                ? (int) $driverRow['docs_plant_id']
                : (isset($driverRow['plant_id']) ? (int) $driverRow['plant_id'] : null);
            $plantName = $driverRow['plant_name'] ?? '';

            registerPlant($plantsById, $primaryPlantId, $plantName);
            $driverRolesAvailable[$driverRole] = true;

            $drivers[$driverId] = [
                'driverId' => $driverId,
                'driverName' => $driverName,
                'role' => $driverRole,
                'plantId' => $primaryPlantId,
                'plantName' => $plantName,
                'documents' => [],
            ];
            $driverIds[] = $driverId;
        }
        $driverStmt->close();
    }

    $vehicleIds = array_values(array_unique(array_filter(array_map(
        static fn($value) => is_numeric($value) ? (int) $value : null,
        $vehicleIds
    ))));

    $driverIds = array_values(array_unique(array_filter(array_map(
        static fn($value) => is_numeric($value) ? (int) $value : null,
        $driverIds
    ))));

    $today = new DateTimeImmutable('today');
    $dueSoonCutoff = $today->modify('+30 days');

    $vehicleCounts = ['active' => 0, 'dueSoon' => 0, 'expired' => 0, 'notApplicable' => 0];
    $driverCounts = ['active' => 0, 'dueSoon' => 0, 'expired' => 0, 'notApplicable' => 0];
    $vehicleDocTypes = [];
    $driverDocTypes = [];

    if (!empty($vehicleIds)) {
        $placeholders = implode(',', array_fill(0, count($vehicleIds), '?'));
        $vehicleDocStmt = $conn->prepare(
            "SELECT vd.*,
                    v.vehicle_no,
                    v.plant_id,
                    p.plant_name
               FROM vehicle_documents vd
               JOIN vehicles v ON v.id = vd.vehicle_id
          LEFT JOIN plants p ON p.id = v.plant_id
              WHERE vd.vehicle_id IN ($placeholders)
                AND COALESCE(vd.is_active, 1) = 1
           ORDER BY v.plant_id ASC, v.vehicle_no ASC, vd.document_name ASC"
        );
        if ($vehicleDocStmt) {
            $types = str_repeat('i', count($vehicleIds));
            $vehicleDocStmt->bind_param($types, ...$vehicleIds);
            $vehicleDocStmt->execute();
            $vehicleDocResult = $vehicleDocStmt->get_result();
            while ($row = $vehicleDocResult->fetch_assoc()) {
                $vehicleId = isset($row['vehicle_id']) ? (int) $row['vehicle_id'] : null;
                if ($vehicleId === null) {
                    continue;
                }
                $documentId = isset($row['id']) ? (int) $row['id'] : null;
                if ($documentId === null) {
                    continue;
                }
                $documentName = $row['document_name'] ?? ($row['doc_name'] ?? '');
                $documentType = $row['document_type'] ?? ($row['doc_type'] ?? '');
                $documentTypeNormalized = strtolower(trim((string) $documentType));
                $expiryDate = $row['expiry_date'] ?? null;
                $statusKey = 'active';
                $statusLabel = 'Active';
                $daysUntilExpiry = null;

                if ($documentTypeNormalized === 'registration') {
                    $statusKey = 'notApplicable';
                    $statusLabel = 'Not Applicable';
                    $expiryDate = null;
                    $daysUntilExpiry = null;
                } else {
                    $statusInfo = computeDocumentStatus($expiryDate, $today, $dueSoonCutoff);
                    $statusKey = $statusInfo['status'];
                    $statusLabel = $statusInfo['label'];
                    $daysUntilExpiry = $statusInfo['daysUntilExpiry'];
                }

                $vehicleDocTypes[$documentTypeNormalized] = $documentType;

                $vehicleCounts[$statusKey] = ($vehicleCounts[$statusKey] ?? 0) + 1;

                $document = [
                    'documentId' => $documentId,
                    'name' => $documentName,
                    'type' => $documentType,
                    'expiryDate' => $expiryDate,
                    'status' => $statusKey,
                    'statusLabel' => $statusLabel,
                    'daysUntilExpiry' => $daysUntilExpiry,
                    'googleDriveLink' => $row['google_drive_link'] ?? null,
                    'filePath' => $row['file_path'] ?? ($row['file_url'] ?? null),
                    'fileName' => $row['file_name'] ?? null,
                    'mimeType' => $row['mime_type'] ?? ($row['file_mime'] ?? null),
                    'fileSize' => isset($row['file_size']) ? (int) $row['file_size'] : null,
                    'uploadedAt' => $row['upload_date'] ?? ($row['created_at'] ?? null),
                    'updatedAt' => $row['updated_at'] ?? null,
                    'notes' => $row['notes'] ?? null,
                    'isActive' => normalizeFlag($row['is_active'] ?? true),
                    'naReason' => null,
                ];

                if (!isset($vehicles[$vehicleId])) {
                    $vehicles[$vehicleId] = [
                        'vehicleId' => $vehicleId,
                        'vehicleNumber' => $row['vehicle_no'] ?? '',
                        'plantId' => isset($row['plant_id']) ? (int) $row['plant_id'] : null,
                        'plantName' => $row['plant_name'] ?? '',
                        'documents' => [],
                    ];
                }
                $vehicles[$vehicleId]['documents'][] = $document;
            }
            $vehicleDocStmt->close();
        }
    }

    if (!empty($driverIds)) {
        $placeholders = implode(',', array_fill(0, count($driverIds), '?'));
        $driverDocStmt = $conn->prepare(
            "SELECT dd.*,
                    d.name,
                    d.role,
                    d.plant_id,
                    d.docs_plant_id,
                    p.plant_name
               FROM driver_documents dd
               JOIN drivers d ON d.id = dd.driver_id
          LEFT JOIN plants p ON p.id = d.plant_id
              WHERE dd.driver_id IN ($placeholders)
                AND COALESCE(dd.is_active, 1) = 1
           ORDER BY p.plant_name ASC, d.name ASC, dd.document_name ASC"
        );
        if ($driverDocStmt) {
            $types = str_repeat('i', count($driverIds));
            $driverDocStmt->bind_param($types, ...$driverIds);
            $driverDocStmt->execute();
            $driverDocResult = $driverDocStmt->get_result();
            while ($row = $driverDocResult->fetch_assoc()) {
                $driverId = isset($row['driver_id']) ? (int) $row['driver_id'] : null;
                if ($driverId === null) {
                    continue;
                }
                $documentId = isset($row['id']) ? (int) $row['id'] : null;
                if ($documentId === null) {
                    continue;
                }

                $documentName = $row['document_name'] ?? ($row['doc_name'] ?? '');
                $documentType = $row['document_type'] ?? ($row['doc_type'] ?? '');
                $documentTypeNormalized = strtolower(trim((string) $documentType));
                $expiryDate = $row['expiry_date'] ?? null;
                $naReasonRaw = $row['na_reson'] ?? ($row['na_reason'] ?? null);
                $normalizedNaReason = is_string($naReasonRaw)
                    ? trim((string) $naReasonRaw)
                    : null;
                $isNotApplicableReason = $normalizedNaReason !== null
                    ? strcasecmp($normalizedNaReason, 'Not Applicable') === 0
                    : false;
                $statusKey = 'active';
                $statusLabel = 'Active';
                $daysUntilExpiry = null;

                if (
                    $documentTypeNormalized === 'registration' ||
                    in_array($documentTypeNormalized, ['aadhar', 'photo', 'signature'], true) ||
                    $isNotApplicableReason
                ) {
                    $statusKey = 'notApplicable';
                    $statusLabel = 'Not Applicable';
                    $expiryDate = null;
                    $daysUntilExpiry = null;
                } else {
                    $statusInfo = computeDocumentStatus($expiryDate, $today, $dueSoonCutoff);
                    $statusKey = $statusInfo['status'];
                    $statusLabel = $statusInfo['label'];
                    $daysUntilExpiry = $statusInfo['daysUntilExpiry'];
                }

                $driverDocTypes[$documentTypeNormalized] = $documentType;
                $driverCounts[$statusKey] = ($driverCounts[$statusKey] ?? 0) + 1;

                $driverRole = strtolower(trim((string) ($row['role'] ?? 'driver')));
                $driverRolesAvailable[$driverRole] = true;

                $document = [
                    'documentId' => $documentId,
                    'name' => $documentName,
                    'type' => $documentType,
                    'expiryDate' => $expiryDate,
                    'status' => $statusKey,
                    'statusLabel' => $statusLabel,
                    'daysUntilExpiry' => $daysUntilExpiry,
                    'googleDriveLink' => $row['google_drive_link'] ?? null,
                    'filePath' => $row['file_path'] ?? ($row['file_url'] ?? null),
                    'fileName' => $row['file_name'] ?? null,
                    'mimeType' => $row['mime_type'] ?? ($row['file_mime'] ?? null),
                    'fileSize' => isset($row['file_size']) ? (int) $row['file_size'] : null,
                    'uploadedAt' => $row['upload_date'] ?? ($row['created_at'] ?? null),
                    'updatedAt' => $row['updated_at'] ?? null,
                    'notes' => $row['notes'] ?? null,
                    'isActive' => normalizeFlag($row['is_active'] ?? true),
                    'naReason' => $normalizedNaReason,
                ];

                if (!isset($drivers[$driverId])) {
                    $primaryPlantId = isset($row['docs_plant_id']) && $row['docs_plant_id'] !== null
                        ? (int) $row['docs_plant_id']
                        : (isset($row['plant_id']) ? (int) $row['plant_id'] : null);
                    $plantName = $row['plant_name'] ?? '';
                    registerPlant($plantsById, $primaryPlantId, $plantName);

                    $drivers[$driverId] = [
                        'driverId' => $driverId,
                        'driverName' => $row['name'] ?? '',
                        'role' => $driverRole,
                        'plantId' => $primaryPlantId,
                        'plantName' => $plantName,
                        'documents' => [],
                    ];
                }

                $drivers[$driverId]['documents'][] = $document;
            }
            $driverDocStmt->close();
        }
    }

    $plants = array_values($plantsById);
    usort(
        $plants,
        static fn(array $a, array $b): int => strcasecmp($a['plantName'] ?? '', $b['plantName'] ?? '')
    );

    foreach ($vehicles as &$vehicleItem) {
        if (!isset($vehicleItem['documents'])) {
            $vehicleItem['documents'] = [];
        }
        usort(
            $vehicleItem['documents'],
            static fn(array $a, array $b): int => strcasecmp($a['name'] ?? '', $b['name'] ?? '')
        );
    }
    unset($vehicleItem);

    foreach ($drivers as &$driverItem) {
        if (!isset($driverItem['documents'])) {
            $driverItem['documents'] = [];
        }
        usort(
            $driverItem['documents'],
            static fn(array $a, array $b): int => strcasecmp($a['name'] ?? '', $b['name'] ?? '')
        );
    }
    unset($driverItem);

    $vehicleList = array_values($vehicles);
    usort(
        $vehicleList,
        static fn(array $a, array $b): int => strcasecmp($a['vehicleNumber'] ?? '', $b['vehicleNumber'] ?? '')
    );

    $driverList = array_values($drivers);
    usort(
        $driverList,
        static fn(array $a, array $b): int => strcasecmp($a['driverName'] ?? '', $b['driverName'] ?? '')
    );

    $roleFilters = [];
    foreach (array_keys($driverRolesAvailable) as $roleKey) {
        $normalizedRole = trim((string) $roleKey);
        if ($normalizedRole === '') {
            continue;
        }
        $roleFilters[] = $normalizedRole;
    }
    sort($roleFilters);

    $vehicleDocTypes = array_values(array_unique(array_filter($vehicleDocTypes)));
    sort($vehicleDocTypes, SORT_NATURAL | SORT_FLAG_CASE);

    $driverDocTypes = array_values(array_unique(array_filter($driverDocTypes)));
    sort($driverDocTypes, SORT_NATURAL | SORT_FLAG_CASE);

    $summary = [
        'vehicles' => $vehicleCounts,
        'drivers' => $driverCounts,
        'total' => [
            'active' => ($vehicleCounts['active'] ?? 0) + ($driverCounts['active'] ?? 0),
            'dueSoon' => ($vehicleCounts['dueSoon'] ?? 0) + ($driverCounts['dueSoon'] ?? 0),
            'expired' => ($vehicleCounts['expired'] ?? 0) + ($driverCounts['expired'] ?? 0),
            'notApplicable' =>
                ($vehicleCounts['notApplicable'] ?? 0) + ($driverCounts['notApplicable'] ?? 0),
        ],
    ];

    apiRespond(200, [
        'status' => 'ok',
        'userId' => $userId,
        'role' => $role,
        'summary' => $summary,
        'filters' => [
            'plants' => $plants,
            'roles' => $roleFilters,
            'documentTypes' => [
                'vehicle' => $vehicleDocTypes,
                'driver' => $driverDocTypes,
            ],
        ],
        'vehicles' => $vehicleList,
        'drivers' => $driverList,
        'statusWindowDays' => 30,
        'generatedAt' => (new DateTimeImmutable('now'))->format(DateTimeInterface::ATOM),
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
