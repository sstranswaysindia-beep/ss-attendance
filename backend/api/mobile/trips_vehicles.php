<?php
declare(strict_types=1);

require __DIR__ . '/common.php';

apiEnsurePost();

$data = apiRequireJson();

$roleRaw   = strtolower(trim((string)($data['role'] ?? 'driver')));
$userId    = apiSanitizeInt($data['userId'] ?? null);
$driverId  = apiSanitizeInt($data['driverId'] ?? null);
$plantId   = apiSanitizeInt($data['plantId'] ?? null);

if (!$plantId) {
    apiRespond(400, ['status' => 'error', 'error' => 'plantId is required']);
}

try {
    $hasAccess = false;

    if ($roleRaw === 'driver') {
        if (!$driverId) {
            apiRespond(400, ['status' => 'error', 'error' => 'driverId required for driver role']);
        }

        $driverStmt = $conn->prepare('SELECT plant_id FROM drivers WHERE id = ? LIMIT 1');
        $driverStmt->bind_param('i', $driverId);
        $driverStmt->execute();
        $driverRow = $driverStmt->get_result()->fetch_assoc();
        $driverStmt->close();

        if ($driverRow && (int)$driverRow['plant_id'] === $plantId) {
            $hasAccess = true;
        } else {
            $assignStmt = $conn->prepare('SELECT 1 FROM assignments WHERE driver_id = ? AND plant_id = ? LIMIT 1');
            $assignStmt->bind_param('ii', $driverId, $plantId);
            $assignStmt->execute();
            $assignRow = $assignStmt->get_result()->fetch_assoc();
            $assignStmt->close();
            $hasAccess = (bool)$assignRow;
        }
    } elseif ($roleRaw === 'supervisor') {
        if (!$userId) {
            apiRespond(400, ['status' => 'error', 'error' => 'userId required for supervisor role']);
        }

        $directStmt = $conn->prepare('SELECT 1 FROM plants WHERE id = ? AND supervisor_user_id = ? LIMIT 1');
        $directStmt->bind_param('ii', $plantId, $userId);
        $directStmt->execute();
        $directRow = $directStmt->get_result()->fetch_assoc();
        $directStmt->close();

        if ($directRow) {
            $hasAccess = true;
        } else {
            $mapStmt = $conn->prepare('SELECT 1 FROM supervisor_plants WHERE user_id = ? AND plant_id = ? LIMIT 1');
            $mapStmt->bind_param('ii', $userId, $plantId);
            $mapStmt->execute();
            $mapRow = $mapStmt->get_result()->fetch_assoc();
            $mapStmt->close();
            $hasAccess = (bool)$mapRow;
        }
    } else {
        $hasAccess = true;
    }

    if (!$hasAccess) {
        apiRespond(403, ['status' => 'error', 'error' => 'Access denied for this plant']);
    }

    $vehicleNumberColumn = 'vehicle_no';
    $columnCheck = $conn->query("SHOW COLUMNS FROM vehicles LIKE 'vehicle_no'");
    if (!$columnCheck || $columnCheck->num_rows === 0) {
        foreach (['number', 'reg_no', 'registration_no'] as $candidate) {
            $columnCheck = $conn->query("SHOW COLUMNS FROM vehicles LIKE '{$candidate}'");
            if ($columnCheck && $columnCheck->num_rows > 0) {
                $vehicleNumberColumn = $candidate;
                break;
            }
        }
    }

    $plantColumn = 'plant_id';
    $plantColumnCheck = $conn->query("SHOW COLUMNS FROM vehicles LIKE 'plant_id'");
    if (!$plantColumnCheck || $plantColumnCheck->num_rows === 0) {
        apiRespond(200, ['status' => 'ok', 'vehicles' => []]);
    }

    $stmt = $conn->prepare("SELECT id, {$vehicleNumberColumn} AS vehicle_no FROM vehicles WHERE {$plantColumn} = ? ORDER BY {$vehicleNumberColumn}");
    $stmt->bind_param('i', $plantId);
    $stmt->execute();
    $result = $stmt->get_result();

    $vehicles = [];
    while ($row = $result->fetch_assoc()) {
        $number = trim((string)($row['vehicle_no'] ?? ''));
        if ($number !== '') {
            $vehicles[] = [
                'id' => (int)$row['id'],
                'vehicle_no' => $number,
            ];
        }
    }
    $stmt->close();

    apiRespond(200, ['status' => 'ok', 'vehicles' => $vehicles]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
