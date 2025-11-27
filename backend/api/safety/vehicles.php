<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

if (!isset($conn) || !$conn instanceof mysqli) {
    apiRespond(500, ['ok' => false, 'error' => 'Database connection not available']);
}

$context = safety_user_context();
$role = $context['role'];
$driverId = $context['driver_id'];

$scopeRaw = strtolower(trim((string)($_GET['scope'] ?? 'mine')));
$scope = in_array($scopeRaw, ['mine', 'plant'], true) ? $scopeRaw : 'mine';
$requestedPlantId = apiSanitizeInt($_GET['plantId'] ?? $_GET['plant_id'] ?? null);

$plants = safety_allowed_plants($conn, $scope);
if ($requestedPlantId && !in_array($requestedPlantId, $plants, true)) {
    $plants[] = $requestedPlantId;
}

$tyreCountExpr = 'COALESCE(NULLIF(v.tyre_count, 0), 6)';
$latestStatusExpr = "(SELECT ti.status FROM tyre_inspections ti WHERE ti.vehicle_id = v.id ORDER BY ti.updated_at DESC LIMIT 1)";
$latestUpdatedExpr = "(SELECT ti.updated_at FROM tyre_inspections ti WHERE ti.vehicle_id = v.id ORDER BY ti.updated_at DESC LIMIT 1)";
$latestSubmittedExpr = "(SELECT ti.submitted_at FROM tyre_inspections ti WHERE ti.vehicle_id = v.id AND ti.submitted_at IS NOT NULL ORDER BY ti.submitted_at DESC LIMIT 1)";

if (empty($plants)) {
    $sql = "SELECT v.id,
                   v.vehicle_no,
                   v.plant_id,
                   {$tyreCountExpr} AS tyre_count,
                   p.plant_name,
                   {$latestStatusExpr} AS latest_status,
                   {$latestUpdatedExpr} AS latest_updated_at,
                   {$latestSubmittedExpr} AS latest_submitted_at
              FROM vehicles v
              LEFT JOIN plants p ON p.id = v.plant_id
             ORDER BY v.vehicle_no ASC
             LIMIT 100";
    $result = $conn->query($sql);
    $vehicles = [];
    if ($result) {
        while ($row = $result->fetch_assoc()) {
            $vehicles[] = [
                'id' => (int)$row['id'],
                'vehicle_no' => $row['vehicle_no'],
                'plant_id' => (int)$row['plant_id'],
                'tyre_count' => max(1, (int)$row['tyre_count']),
                'plant_name' => $row['plant_name'],
                'latest_status' => $row['latest_status'],
                'latest_updated_at' => $row['latest_updated_at'],
                'latest_submitted_at' => $row['latest_submitted_at'],
            ];
        }
    }
    apiRespond(200, ['ok' => true, 'vehicles' => $vehicles]);
}

$vehicles = [];

if ($role === 'driver' && $driverId) {
    $assignmentSql = "
        SELECT v.id,
               v.vehicle_no,
               v.plant_id,
               {$tyreCountExpr} AS tyre_count,
               p.plant_name,
               {$latestStatusExpr} AS latest_status,
               {$latestUpdatedExpr} AS latest_updated_at,
               {$latestSubmittedExpr} AS latest_submitted_at
          FROM assignments a
          JOIN vehicles v ON v.id = a.vehicle_id
          LEFT JOIN plants p ON p.id = v.plant_id
         WHERE a.driver_id = ?
         GROUP BY v.id, v.vehicle_no, v.plant_id, v.tyre_count, p.plant_name
         ORDER BY v.vehicle_no ASC
    ";
    $assignStmt = $conn->prepare($assignmentSql);
    if ($assignStmt) {
        $assignStmt->bind_param('i', $driverId);
        $assignStmt->execute();
        $assignResult = $assignStmt->get_result();
        while ($row = $assignResult->fetch_assoc()) {
            if ($requestedPlantId && (int)$row['plant_id'] !== $requestedPlantId) {
                continue;
            }
            $vehicles[] = [
                'id' => (int)$row['id'],
                'vehicle_no' => $row['vehicle_no'],
                'plant_id' => (int)$row['plant_id'],
                'tyre_count' => max(1, (int)$row['tyre_count']),
                'plant_name' => $row['plant_name'],
                'latest_status' => $row['latest_status'],
                'latest_updated_at' => $row['latest_updated_at'],
                'latest_submitted_at' => $row['latest_submitted_at'],
            ];
        }
        $assignStmt->close();
    }

    if (!empty($vehicles)) {
        apiRespond(200, ['ok' => true, 'vehicles' => $vehicles]);
    }
}

if ($requestedPlantId) {
    $sql = "
        SELECT v.id,
               v.vehicle_no,
               v.plant_id,
               {$tyreCountExpr} AS tyre_count,
               p.plant_name,
               {$latestStatusExpr} AS latest_status,
               {$latestUpdatedExpr} AS latest_updated_at,
               {$latestSubmittedExpr} AS latest_submitted_at
          FROM vehicles v
          LEFT JOIN plants p ON p.id = v.plant_id
         WHERE v.plant_id = ?
         ORDER BY v.vehicle_no ASC
    ";
    $stmt = $conn->prepare($sql);
    if ($stmt) {
        $stmt->bind_param('i', $requestedPlantId);
        $stmt->execute();
        $result = $stmt->get_result();
        while ($row = $result->fetch_assoc()) {
            $vehicles[] = [
                'id' => (int)$row['id'],
                'vehicle_no' => $row['vehicle_no'],
                'plant_id' => (int)$row['plant_id'],
                'tyre_count' => max(1, (int)$row['tyre_count']),
                'plant_name' => $row['plant_name'],
                'latest_status' => $row['latest_status'],
                'latest_updated_at' => $row['latest_updated_at'],
                'latest_submitted_at' => $row['latest_submitted_at'],
            ];
        }
        $stmt->close();
    }
} else {
    $placeholders = implode(',', array_fill(0, count($plants), '?'));
    $types = str_repeat('i', count($plants));
    $sql = "
        SELECT v.id,
               v.vehicle_no,
               v.plant_id,
               {$tyreCountExpr} AS tyre_count,
               p.plant_name,
               {$latestStatusExpr} AS latest_status,
               {$latestUpdatedExpr} AS latest_updated_at,
               {$latestSubmittedExpr} AS latest_submitted_at
          FROM vehicles v
          LEFT JOIN plants p ON p.id = v.plant_id
         WHERE v.plant_id IN ($placeholders)
         ORDER BY v.vehicle_no ASC
    ";
    $stmt = $conn->prepare($sql);
    if ($stmt) {
        $bind = [$types];
        foreach ($plants as $index => $plantId) {
            $bind[] = &$plants[$index];
        }
        call_user_func_array([$stmt, 'bind_param'], $bind);
        $stmt->execute();

        $result = $stmt->get_result();
        while ($row = $result->fetch_assoc()) {
            $vehicles[] = [
                'id' => (int)$row['id'],
                'vehicle_no' => $row['vehicle_no'],
                'plant_id' => (int)$row['plant_id'],
                'tyre_count' => max(1, (int)$row['tyre_count']),
                'plant_name' => $row['plant_name'],
                'latest_status' => $row['latest_status'],
                'latest_updated_at' => $row['latest_updated_at'],
                'latest_submitted_at' => $row['latest_submitted_at'],
            ];
        }
        $stmt->close();
    }
}

apiRespond(200, ['ok' => true, 'vehicles' => $vehicles]);
