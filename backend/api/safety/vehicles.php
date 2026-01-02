<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

if (!isset($conn) || !$conn instanceof mysqli) {
    apiRespond(500, ['ok' => false, 'error' => 'Database connection not available']);
}

$context = safety_user_context();
$role = $context['role'];
$driverId = $context['driver_id'];

$disableWhere = '';
$disableCheck = $conn->query("SHOW COLUMNS FROM vehicles LIKE 'disable_flag'");
if ($disableCheck && $disableCheck->num_rows > 0) {
    $disableWhere = " AND (v.disable_flag = 'Y' OR v.disable_flag IS NULL)";
}

$scopeRaw = strtolower(trim((string)($_GET['scope'] ?? 'all')));
$scope = in_array($scopeRaw, ['all', 'mine', 'plant'], true) ? $scopeRaw : 'all';
$requestedPlantId = apiSanitizeInt($_GET['plantId'] ?? $_GET['plant_id'] ?? null);

$plants = ($scope === 'all') ? [] : safety_allowed_plants($conn, $scope);
if ($requestedPlantId && !in_array($requestedPlantId, $plants, true)) {
    $plants[] = $requestedPlantId;
}

$plantsList = [];
if (empty($plants)) {
    $sql = "SELECT v.id,
                   v.vehicle_no,
                   v.plant_id,
                   COALESCE(NULLIF(v.tyre_count, 0), 6) AS tyre_count,
                   p.plant_name,
                   (SELECT ti.status
                      FROM tyre_inspections ti
                     WHERE ti.vehicle_id = v.id
                     ORDER BY ti.updated_at DESC, ti.id DESC
                     LIMIT 1) AS latest_status,
                   (SELECT ti.updated_at
                      FROM tyre_inspections ti
                     WHERE ti.vehicle_id = v.id
                     ORDER BY ti.updated_at DESC, ti.id DESC
                     LIMIT 1) AS latest_updated_at,
                   (SELECT ti.submitted_at
                      FROM tyre_inspections ti
                     WHERE ti.vehicle_id = v.id
                     ORDER BY ti.submitted_at DESC, ti.id DESC
                     LIMIT 1) AS latest_submitted_at
              FROM vehicles v
              LEFT JOIN plants p ON p.id = v.plant_id
             WHERE 1=1 {$disableWhere}
             ORDER BY v.vehicle_no ASC";
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
                'latest_status' => $row['latest_status'] ?? null,
                'latest_updated_at' => $row['latest_updated_at'] ?? null,
                'latest_submitted_at' => $row['latest_submitted_at'] ?? null,
            ];
        }
    }
    $plantsList = [];
    $plantsResult = $conn->query("SELECT DISTINCT p.id, p.plant_name FROM vehicles v LEFT JOIN plants p ON p.id = v.plant_id WHERE 1=1 {$disableWhere} ORDER BY p.plant_name ASC");
    if ($plantsResult) {
        while ($p = $plantsResult->fetch_assoc()) {
            $pid = (int)($p['id'] ?? 0);
            if ($pid > 0) {
                $plantsList[] = ['id' => $pid, 'plant_name' => $p['plant_name'] ?? ''];
            }
        }
    }
    apiRespond(200, ['ok' => true, 'vehicles' => $vehicles, 'plants' => $plantsList]);
}

$vehicles = [];

if ($requestedPlantId) {
    $sql = "
        SELECT v.id,
               v.vehicle_no,
               v.plant_id,
               COALESCE(NULLIF(v.tyre_count, 0), 6) AS tyre_count,
               p.plant_name,
               (SELECT ti.status
                  FROM tyre_inspections ti
                 WHERE ti.vehicle_id = v.id
                 ORDER BY ti.updated_at DESC, ti.id DESC
                 LIMIT 1) AS latest_status,
               (SELECT ti.updated_at
                  FROM tyre_inspections ti
                 WHERE ti.vehicle_id = v.id
                 ORDER BY ti.updated_at DESC, ti.id DESC
                 LIMIT 1) AS latest_updated_at,
               (SELECT ti.submitted_at
                  FROM tyre_inspections ti
                 WHERE ti.vehicle_id = v.id
                 ORDER BY ti.submitted_at DESC, ti.id DESC
                 LIMIT 1) AS latest_submitted_at
          FROM vehicles v
          LEFT JOIN plants p ON p.id = v.plant_id
         WHERE v.plant_id = ?
           {$disableWhere}
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
                'latest_status' => $row['latest_status'] ?? null,
                'latest_updated_at' => $row['latest_updated_at'] ?? null,
                'latest_submitted_at' => $row['latest_submitted_at'] ?? null,
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
               COALESCE(NULLIF(v.tyre_count, 0), 6) AS tyre_count,
               p.plant_name,
               (SELECT ti.status
                  FROM tyre_inspections ti
                 WHERE ti.vehicle_id = v.id
                 ORDER BY ti.updated_at DESC, ti.id DESC
                 LIMIT 1) AS latest_status,
               (SELECT ti.updated_at
                  FROM tyre_inspections ti
                 WHERE ti.vehicle_id = v.id
                 ORDER BY ti.updated_at DESC, ti.id DESC
                 LIMIT 1) AS latest_updated_at,
               (SELECT ti.submitted_at
                  FROM tyre_inspections ti
                 WHERE ti.vehicle_id = v.id
                 ORDER BY ti.submitted_at DESC, ti.id DESC
                 LIMIT 1) AS latest_submitted_at
          FROM vehicles v
          LEFT JOIN plants p ON p.id = v.plant_id
         WHERE v.plant_id IN ($placeholders)
           {$disableWhere}
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
                'latest_status' => $row['latest_status'] ?? null,
                'latest_updated_at' => $row['latest_updated_at'] ?? null,
                'latest_submitted_at' => $row['latest_submitted_at'] ?? null,
            ];
        }
        $stmt->close();
    }
}

if (empty($plantsList)) {
    // Derive plants from gathered vehicles
    $seen = [];
    foreach ($vehicles as $veh) {
        $pid = $veh['plant_id'] ?? null;
        $pname = $veh['plant_name'] ?? '';
        if ($pid && !isset($seen[$pid])) {
            $seen[$pid] = ['id' => (int)$pid, 'plant_name' => $pname];
        }
    }
    $plantsList = array_values($seen);

    if (empty($plantsList)) {
        $plantsResult = $conn->query("SELECT DISTINCT p.id, p.plant_name FROM vehicles v LEFT JOIN plants p ON p.id = v.plant_id WHERE 1=1 {$disableWhere} ORDER BY p.plant_name ASC");
        if ($plantsResult) {
            while ($p = $plantsResult->fetch_assoc()) {
                $pid = (int)($p['id'] ?? 0);
                if ($pid > 0) {
                    $plantsList[] = ['id' => $pid, 'plant_name' => $p['plant_name'] ?? ''];
                }
            }
        }
    }
}

apiRespond(200, ['ok' => true, 'vehicles' => $vehicles, 'plants' => $plantsList]);
