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

$adminUserId = apiSanitizeInt($_GET['adminUserId'] ?? null);
$statusFilter = trim($_GET['status'] ?? 'Pending');
$dateFilter = trim($_GET['date'] ?? date('Y-m-d'));
$plantFilter = apiSanitizeInt($_GET['plantId'] ?? null);
$rangeDays = apiSanitizeInt($_GET['rangeDays'] ?? null);

if ($rangeDays !== null && $rangeDays <= 0) {
    $rangeDays = null;
}

if (!$adminUserId) {
    apiRespond(400, ['status' => 'error', 'error' => 'adminUserId is required']);
}

try {
    $userStmt = $conn->prepare('SELECT role FROM users WHERE id = ? LIMIT 1');
    $userStmt->bind_param('i', $adminUserId);
    $userStmt->execute();
    $userRow = $userStmt->get_result()->fetch_assoc();
    $userStmt->close();

    if (!$userRow || $userRow['role'] !== 'admin') {
        apiRespond(403, ['status' => 'error', 'error' => 'User is not authorized']);
    }

    $conditions = ["COALESCE(d.role, 'driver') IN ('supervisor', 'driver')"];
    $bindTypes = '';
    $bindValues = [];

    if ($statusFilter !== '' && strcasecmp($statusFilter, 'All') !== 0) {
        $conditions[] = 'a.approval_status = ?';
        $bindTypes .= 's';
        $bindValues[] = $statusFilter;
    }

    $fromDate = null;
    $toDate = null;

    if ($rangeDays !== null) {
        $toDate = date('Y-m-d');
        $fromDate = (new DateTime($toDate))->modify(sprintf('-%d days', max(0, $rangeDays - 1)))->format('Y-m-d');
        $conditions[] = 'DATE(a.in_time) BETWEEN ? AND ?';
        $bindTypes .= 'ss';
        $bindValues[] = $fromDate;
        $bindValues[] = $toDate;
    } elseif ($dateFilter !== '') {
        $fromDate = $dateFilter;
        $toDate = $dateFilter;
        $conditions[] = 'DATE(a.in_time) = ?';
        $bindTypes .= 's';
        $bindValues[] = $dateFilter;
    }

    if ($fromDate === null || $toDate === null) {
        $fromDate = date('Y-m-d');
        $toDate = $fromDate;
        $conditions[] = 'DATE(a.in_time) = ?';
        $bindTypes .= 's';
        $bindValues[] = $fromDate;
    }

    if ($plantFilter) {
        $conditions[] = 'a.plant_id = ?';
        $bindTypes .= 'i';
        $bindValues[] = $plantFilter;
    }

    $sql = 'SELECT a.id,
                   a.driver_id,
                   d.name AS driver_name,
                   a.plant_id,
                   p.plant_name,
                   a.vehicle_id,
                   v.vehicle_no,
                   a.in_time,
                   a.out_time,
                   a.in_photo_url,
                   a.out_photo_url,
                   a.approval_status,
                   a.source,
                   a.notes,
                   a.created_at
              FROM attendance a
         LEFT JOIN drivers d ON d.id = a.driver_id
         LEFT JOIN plants p  ON p.id = a.plant_id
         LEFT JOIN vehicles v ON v.id = a.vehicle_id
             WHERE ' . implode(' AND ', $conditions) . '
          ORDER BY a.in_time DESC
             LIMIT 200';

    $stmt = $conn->prepare($sql);
    if ($bindTypes !== '') {
        apiBindParams($stmt, $bindTypes, $bindValues);
    }
    $stmt->execute();
    $result = $stmt->get_result();

    $plantMap = [];
    $plantMeta = [];
    $approvals = [];

    while ($row = $result->fetch_assoc()) {
        if (!empty($row['plant_id']) && !isset($plantMap[$row['plant_id']])) {
            $plantMap[$row['plant_id']] = true;
            $plantMeta[] = [
                'plantId' => (int) $row['plant_id'],
                'plantName' => $row['plant_name'],
            ];
        }

        $approvals[] = [
            'attendanceId' => (int) $row['id'],
            'driverId' => (int) $row['driver_id'],
            'driverName' => $row['driver_name'],
            'plantId' => (int) $row['plant_id'],
            'plantName' => $row['plant_name'],
            'vehicleId' => $row['vehicle_id'],
            'vehicleNumber' => $row['vehicle_no'],
            'inTime' => $row['in_time'],
            'outTime' => $row['out_time'],
            'inPhotoUrl' => $row['in_photo_url'],
            'outPhotoUrl' => $row['out_photo_url'],
            'status' => $row['approval_status'],
            'source' => $row['source'],
            'notes' => $row['notes'],
            'createdAt' => $row['created_at'],
        ];
    }
    $stmt->close();

    usort($plantMeta, static fn(array $a, array $b): int => strcmp($a['plantName'], $b['plantName']));

    $missingSql = "SELECT d.id,
                          d.name,
                          COALESCE(d.role, 'driver') AS role,
                          d.plant_id,
                          p.plant_name
                     FROM drivers d
                LEFT JOIN plants p ON p.id = d.plant_id
                    WHERE d.status = 'Active'
                      AND COALESCE(d.role, 'driver') IN ('supervisor', 'driver')";

    $missingTypes = '';
    $missingParams = [];

    if ($plantFilter) {
        $missingSql .= ' AND d.plant_id = ?';
        $missingTypes .= 'i';
        $missingParams[] = $plantFilter;
    }

    $missingSql .= ' AND NOT EXISTS (
        SELECT 1 FROM attendance a
         WHERE a.driver_id = d.id
           AND DATE(a.in_time) BETWEEN ? AND ?';
    $missingTypes .= 'ss';
    $missingParams[] = $fromDate;
    $missingParams[] = $toDate;

    if ($plantFilter) {
        $missingSql .= ' AND a.plant_id = ?';
        $missingTypes .= 'i';
        $missingParams[] = $plantFilter;
    }

    $missingSql .= ' )
     ORDER BY p.plant_name ASC, d.name ASC';

    $missingStmt = $conn->prepare($missingSql);
    if ($missingTypes !== '') {
        $missingStmt->bind_param($missingTypes, ...$missingParams);
    }
    $missingStmt->execute();
    $missingResult = $missingStmt->get_result();
    $missingPeople = [];
    while ($row = $missingResult->fetch_assoc()) {
        $missingPeople[] = [
            'driverId' => (int) $row['id'],
            'name' => $row['name'],
            'role' => $row['role'],
            'plantId' => $row['plant_id'] !== null ? (int) $row['plant_id'] : null,
            'plantName' => $row['plant_name'],
        ];
    }
    $missingStmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'plants' => $plantMeta,
        'approvals' => $approvals,
        'missingAttendance' => $missingPeople,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
