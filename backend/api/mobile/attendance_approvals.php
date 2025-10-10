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

$supervisorUserId = apiSanitizeInt($_GET['supervisorUserId'] ?? null);
$statusFilter     = trim($_GET['status'] ?? 'Pending');
$dateFilter       = trim($_GET['date'] ?? date('Y-m-d'));
$plantFilter      = apiSanitizeInt($_GET['plantId'] ?? null);
$rangeDays        = apiSanitizeInt($_GET['rangeDays'] ?? null);

if ($rangeDays !== null && $rangeDays <= 0) {
    $rangeDays = null;
}

if (!$supervisorUserId) {
    apiRespond(400, ['status' => 'error', 'error' => 'supervisorUserId is required']);
}

try {
    /**
     * Resolve plants assigned to supervisor.
     */
    $plantIds = [];

    $plantStmt = $conn->prepare('SELECT plant_id FROM supervisor_plants WHERE user_id = ?');
    $plantStmt->bind_param('i', $supervisorUserId);
    $plantStmt->execute();
    $plantResult = $plantStmt->get_result();
    while ($row = $plantResult->fetch_assoc()) {
        if (!empty($row['plant_id'])) {
            $plantIds[] = (int) $row['plant_id'];
        }
    }
    $plantStmt->close();

    // If the supervisor also has a driver record, include any plant they supervise via drivers table.
    $userStmt = $conn->prepare('SELECT driver_id FROM users WHERE id = ? LIMIT 1');
    $userStmt->bind_param('i', $supervisorUserId);
    $userStmt->execute();
    $userRow = $userStmt->get_result()->fetch_assoc();
    $userStmt->close();

    if ($userRow && !empty($userRow['driver_id'])) {
        $driverId = (int) $userRow['driver_id'];
        $driverStmt = $conn->prepare('SELECT supervisor_of_plant_id FROM drivers WHERE id = ? LIMIT 1');
        $driverStmt->bind_param('i', $driverId);
        $driverStmt->execute();
        $driverRow = $driverStmt->get_result()->fetch_assoc();
        $driverStmt->close();
        if ($driverRow && !empty($driverRow['supervisor_of_plant_id'])) {
            $plantIds[] = (int) $driverRow['supervisor_of_plant_id'];
        }
    }

    $plantIds = array_values(array_unique(array_filter($plantIds)));

    if (empty($plantIds)) {
        apiRespond(200, [
            'status' => 'ok',
            'plants' => [],
            'approvals' => [],
        ]);
    }

    // If plant filter provided, ensure it's in the allowed list.
    if ($plantFilter && !in_array($plantFilter, $plantIds, true)) {
        apiRespond(200, [
            'status' => 'ok',
            'plants' => [],
            'approvals' => [],
        ]);
    }

    // Fetch plant metadata for dropdown.
    $placeholders = implode(',', array_fill(0, count($plantIds), '?'));
    $types = str_repeat('i', count($plantIds));
    $plantMetaStmt = $conn->prepare(
        sprintf('SELECT id, plant_name FROM plants WHERE id IN (%s) ORDER BY plant_name', $placeholders)
    );
    apiBindParams($plantMetaStmt, $types, $plantIds);
    $plantMetaStmt->execute();
    $plantMetaResult = $plantMetaStmt->get_result();
    $plantMeta = [];
    while ($row = $plantMetaResult->fetch_assoc()) {
        $plantMeta[] = [
            'plantId' => (int) $row['id'],
            'plantName' => $row['plant_name'],
        ];
    }
    $plantMetaStmt->close();

    $sql = sprintf(
        'SELECT a.id,
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
          WHERE a.plant_id IN (%s)',
        $placeholders
    );

    $sql .= ' AND (d.role IS NULL OR d.role <> "supervisor")';

    $bindValues = $plantIds;
    $bindTypes = $types;

    if ($statusFilter !== '' && strcasecmp($statusFilter, 'All') !== 0) {
        $sql .= ' AND a.approval_status = ?';
        $bindTypes .= 's';
        $bindValues[] = $statusFilter;
    }

    if ($rangeDays !== null) {
        $toDate = date('Y-m-d');
        $fromDate = (new DateTime($toDate))->modify(sprintf('-%d days', max(0, $rangeDays - 1)))->format('Y-m-d');
        $sql .= ' AND DATE(a.in_time) BETWEEN ? AND ?';
        $bindTypes .= 'ss';
        $bindValues[] = $fromDate;
        $bindValues[] = $toDate;
    } elseif ($dateFilter !== '') {
        $sql .= ' AND DATE(a.in_time) = ?';
        $bindTypes .= 's';
        $bindValues[] = $dateFilter;
    }

    if ($plantFilter) {
        $sql .= ' AND a.plant_id = ?';
        $bindTypes .= 'i';
        $bindValues[] = $plantFilter;
    }

    $sql .= ' ORDER BY a.in_time DESC LIMIT 200';

    $approvalStmt = $conn->prepare($sql);
    apiBindParams($approvalStmt, $bindTypes, $bindValues);
    $approvalStmt->execute();
    $result = $approvalStmt->get_result();

    $approvals = [];
    while ($row = $result->fetch_assoc()) {
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
    $approvalStmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'plants' => $plantMeta,
        'approvals' => $approvals,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
