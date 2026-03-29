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

function buildInPlaceholders(int $count): string
{
    return implode(', ', array_fill(0, max(0, $count), '?'));
}

$adminUserId = apiSanitizeInt($_GET['adminUserId'] ?? null);
$statusFilter   = trim($_GET['status'] ?? 'Pending');
$dateFilter     = trim($_GET['date'] ?? '');
$fromDateParam  = trim($_GET['fromDate'] ?? '');
$toDateParam    = trim($_GET['toDate'] ?? '');
$plantFilter    = apiSanitizeInt($_GET['plantId'] ?? null);
$rangeDays      = apiSanitizeInt($_GET['rangeDays'] ?? null);

if ($dateFilter === '' && $fromDateParam === '' && $toDateParam === '') {
    $dateFilter = date('Y-m-d');
}

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

    if (
        !$userRow
        || !isset($userRow['role'])
        || !in_array(strtolower((string)$userRow['role']), ['admin', 'super_admin'], true)
    ) {
        apiRespond(403, ['status' => 'error', 'error' => 'User is not authorized']);
    }

    // ---- filters ---------------------------------------------------
    $conditions = ["COALESCE(d.role, 'driver') IN ('supervisor', 'driver')"];
    $bindTypes = '';
    $bindValues = [];

    if ($statusFilter !== '' && strcasecmp($statusFilter, 'All') !== 0) {
        $conditions[] = 'a.approval_status = ?';
        $bindTypes .= 's';
        $bindValues[] = $statusFilter;
    }

    $fromDate = null;
    $toDate   = null;

    // 1) Highest priority: explicit fromDate / toDate from UI
    if ($fromDateParam !== '' && $toDateParam !== '') {
        $fromDate = $fromDateParam;
        $toDate   = $toDateParam;
        $conditions[] = 'DATE(a.in_time) BETWEEN ? AND ?';
        $bindTypes .= 'ss';
        $bindValues[] = $fromDate;
        $bindValues[] = $toDate;

    // 2) rangeDays (e.g., last 30 days)
    } elseif ($rangeDays !== null) {
        $toDate = date('Y-m-d');
        $fromDate = (new DateTime($toDate))
            ->modify(sprintf('-%d days', max(0, $rangeDays - 1)))
            ->format('Y-m-d');
        $conditions[] = 'DATE(a.in_time) BETWEEN ? AND ?';
        $bindTypes .= 'ss';
        $bindValues[] = $fromDate;
        $bindValues[] = $toDate;

    // 3) single date
    } elseif ($dateFilter !== '') {
        $fromDate = $dateFilter;
        $toDate = $dateFilter;
        $conditions[] = 'DATE(a.in_time) = ?';
        $bindTypes .= 's';
        $bindValues[] = $dateFilter;
    }

    // 4) final fallback: today
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

    // ---- approvals list --------------------------------------------
    $sql = 'SELECT a.id,
                   a.driver_id,
                   d.name AS driver_name,
                   d.profile_photo_url,
                   COALESCE(d.role, \'driver\') AS role,
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

    $approvalRows = [];
    $driverIds = [];

    while ($row = $result->fetch_assoc()) {
        $approvalRows[] = $row;
        $driverId = (int) ($row['driver_id'] ?? 0);
        if ($driverId > 0) {
            $driverIds[$driverId] = true;
        }
    }
    $stmt->close();

    $tripMap = [];
    if (!empty($driverIds)) {
        $tripSql = '
            SELECT
                td.driver_id,
                t.id AS trip_id,
                t.start_date,
                t.end_date,
                v.id AS trip_vehicle_id,
                v.vehicle_no AS trip_vehicle_no,
                p.id AS trip_plant_id,
                p.plant_name AS trip_plant_name
            FROM trip_drivers td
            JOIN trips t ON t.id = td.trip_id
            LEFT JOIN vehicles v ON v.id = t.vehicle_id
            LEFT JOIN plants p ON p.id = v.plant_id
            WHERE td.driver_id IN (' . buildInPlaceholders(count($driverIds)) . ')
              AND t.start_date <= ?
              AND COALESCE(NULLIF(t.end_date, "0000-00-00"), t.start_date) >= ?
            ORDER BY t.start_date DESC, t.id DESC
        ';
        $tripStmt = $conn->prepare($tripSql);
        $tripTypes = str_repeat('i', count($driverIds)) . 'ss';
        $tripValues = array_map('intval', array_keys($driverIds));
        $tripValues[] = $toDate;
        $tripValues[] = $fromDate;
        apiBindParams($tripStmt, $tripTypes, $tripValues);
        $tripStmt->execute();
        $tripResult = $tripStmt->get_result();
        while ($tripRow = $tripResult->fetch_assoc()) {
            $tripDriverId = (int) ($tripRow['driver_id'] ?? 0);
            $tripStart = (string) ($tripRow['start_date'] ?? '');
            $tripEnd = (string) ($tripRow['end_date'] ?? '');
            if ($tripDriverId <= 0 || $tripStart === '') {
                continue;
            }
            $tripEnd = ($tripEnd !== '' && $tripEnd !== '0000-00-00') ? $tripEnd : $tripStart;
            $currentDate = $tripStart;
            while ($currentDate <= $tripEnd) {
                $tripKey = $tripDriverId . '|' . $currentDate;
                if (!isset($tripMap[$tripKey])) {
                    $tripMap[$tripKey] = $tripRow;
                }
                $nextTs = strtotime($currentDate . ' +1 day');
                if ($nextTs === false) {
                    break;
                }
                $currentDate = date('Y-m-d', $nextTs);
            }
        }
        $tripStmt->close();
    }

    $plantMap  = [];
    $plantMeta = [];
    $approvals = [];

    foreach ($approvalRows as $row) {
        $attendanceDate = !empty($row['in_time']) ? substr((string) $row['in_time'], 0, 10) : '';
        $driverId = (int) ($row['driver_id'] ?? 0);
        $tripKey = $driverId > 0 && $attendanceDate !== '' ? ($driverId . '|' . $attendanceDate) : '';
        $tripRow = $tripKey !== '' ? ($tripMap[$tripKey] ?? null) : null;

        $displayPlantId = $tripRow ? (int) ($tripRow['trip_plant_id'] ?? 0) : 0;
        $displayPlantName = $tripRow
            ? (string) ($tripRow['trip_plant_name'] ?? '')
            : 'No pending trip';
        $displayVehicleId = $tripRow ? (int) ($tripRow['trip_vehicle_id'] ?? 0) : 0;
        $displayVehicleNo = $tripRow
            ? (string) ($tripRow['trip_vehicle_no'] ?? '')
            : 'No pending trip';

        if ($displayPlantId > 0 && !isset($plantMap[$displayPlantId])) {
            $plantMap[$displayPlantId] = true;
            $plantMeta[] = [
                'plantId'   => $displayPlantId,
                'plantName' => $displayPlantName,
            ];
        }

        $approvals[] = [
            'attendanceId'  => (int) $row['id'],
            'driverId'      => $driverId,
            'driverName'    => $row['driver_name'],
            'role'          => $row['role'], // <-- used by UI for Supervisor / Driver toggle
            'profilePhoto'  => apiBuildProfileUrl($row['profile_photo_url'] ?? null),
            'plantId'       => $displayPlantId,
            'plantName'     => $displayPlantName,
            'vehicleId'     => $displayVehicleId,
            'vehicleNumber' => $displayVehicleNo,
            'inTime'        => $row['in_time'],
            'outTime'       => $row['out_time'],
            'inPhotoUrl'    => $row['in_photo_url'],
            'outPhotoUrl'   => $row['out_photo_url'],
            'status'        => $row['approval_status'],
            'source'        => $row['source'],
            'notes'         => $row['notes'],
            'createdAt'     => $row['created_at'],
        ];
    }

    usort($plantMeta, static fn(array $a, array $b): int => strcmp($a['plantName'], $b['plantName']));

    // ---- missing attendance ----------------------------------------
    $missingSql = "SELECT d.id,
                          d.name,
                          COALESCE(d.role, 'driver') AS role,
                          d.plant_id,
                          p.plant_name
                     FROM drivers d
                LEFT JOIN plants p ON p.id = d.plant_id
                    WHERE d.status = 'Active'
                      AND COALESCE(d.role, 'driver') IN ('supervisor', 'driver')";

    $missingTypes  = '';
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
            'driverId'  => (int) $row['id'],
            'name'      => $row['name'],
            'role'      => $row['role'],
            'plantId'   => $row['plant_id'] !== null ? (int) $row['plant_id'] : null,
            'plantName' => $row['plant_name'],
        ];
    }
    $missingStmt->close();

    apiRespond(200, [
        'status'            => 'ok',
        'plants'            => $plantMeta,
        'approvals'         => $approvals,
        'missingAttendance' => $missingPeople,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
