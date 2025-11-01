<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

try {
    if (!isset($conn) || !$conn instanceof \mysqli) {
        apiRespond(500, ['ok' => false, 'error' => 'Database connection not available']);
    }

    $context = safety_user_context();
    $role = $context['role'];
    $driverId = $context['driver_id'];

    $scopeRaw = strtolower(trim((string)($_GET['scope'] ?? 'mine')));
    $scope = in_array($scopeRaw, ['mine', 'plant'], true) ? $scopeRaw : 'mine';
    $requestedPlantId = apiSanitizeInt($_GET['plantId'] ?? $_GET['plant_id'] ?? null);

    error_log(sprintf(
        '[safety/vehicles] role=%s driver_id=%s scope=%s requestedPlantId=%s plants_session=%s',
        $role ?: 'unset',
        $driverId !== null ? (string)$driverId : 'null',
        $scope,
        $requestedPlantId !== null ? (string)$requestedPlantId : 'null',
        json_encode($context['supervised_plant_ids'])
    ));

    $plants = safety_allowed_plants($conn, $scope);
    if ($requestedPlantId && !in_array($requestedPlantId, $plants, true)) {
        $plants[] = $requestedPlantId;
    }

    $tyreExpr = safety_vehicle_tyre_expression($conn);

    if (empty($plants)) {
        $sql = "SELECT v.id,
                       v.vehicle_no,
                       v.plant_id,
                       {$tyreExpr} AS tyre_count,
                       p.plant_name
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
                ];
            }
        }
        apiRespond(200, ['ok' => true, 'vehicles' => $vehicles]);
    }

    $vehicles = [];

    if ($role === 'driver' && $driverId) {
        if (safety_table_exists($conn, 'assignments')) {
            $assignmentSql = "
                SELECT v.id,
                       v.vehicle_no,
                       v.plant_id,
                       {$tyreExpr} AS tyre_count,
                       p.plant_name
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
                    ];
                }
                $assignStmt->close();
            }

            if (!empty($vehicles)) {
                error_log(sprintf('[safety/vehicles] driver %s assignment vehicles=%d', (string)$driverId, count($vehicles)));
                apiRespond(200, ['ok' => true, 'vehicles' => $vehicles]);
            }
        }
    }

    if ($requestedPlantId) {
        $sql = "
            SELECT v.id,
                   v.vehicle_no,
                   v.plant_id,
                   {$tyreExpr} AS tyre_count,
                   p.plant_name
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
                   {$tyreExpr} AS tyre_count,
                   p.plant_name
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
                ];
            }
            $stmt->close();
        }
    }

    error_log(sprintf('[safety/vehicles] returning vehicles=%d (role=%s)', count($vehicles), $role ?: 'unset'));
    apiRespond(200, ['ok' => true, 'vehicles' => $vehicles]);
} catch (Throwable $e) {
    error_log('[safety/vehicles] ' . $e->getMessage());
    apiRespond(500, [
        'ok' => false,
        'error' => 'Unable to load vehicles',
        'detail' => $e->getMessage(),
    ]);
}
