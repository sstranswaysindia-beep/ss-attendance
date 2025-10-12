<?php
declare(strict_types=1);

require __DIR__ . '/common.php';

apiEnsurePost();

$data = apiRequireJson();

$roleRaw   = strtolower(trim((string)($data['role'] ?? 'driver')));
$userId    = apiSanitizeInt($data['userId'] ?? null);
$driverId  = apiSanitizeInt($data['driverId'] ?? null);

$plantIds = [];

try {
    if ($roleRaw === 'driver') {
        if (!$driverId) {
            apiRespond(400, ['status' => 'error', 'error' => 'driverId required for driver role']);
        }

        $driverStmt = $conn->prepare('SELECT plant_id, default_plant_id, supervisor_of_plant_id FROM drivers WHERE id = ? LIMIT 1');
        $driverStmt->bind_param('i', $driverId);
        $driverStmt->execute();
        $driverRow = $driverStmt->get_result()->fetch_assoc();
        $driverStmt->close();
        if ($driverRow) {
            foreach (['plant_id', 'default_plant_id', 'supervisor_of_plant_id'] as $field) {
                if (!empty($driverRow[$field])) {
                    $plantIds[] = (int)$driverRow[$field];
                }
            }
        }

        $assignStmt = $conn->prepare('SELECT DISTINCT plant_id FROM assignments WHERE driver_id = ? AND plant_id IS NOT NULL');
        $assignStmt->bind_param('i', $driverId);
        $assignStmt->execute();
        $assignRes = $assignStmt->get_result();
        while ($row = $assignRes->fetch_assoc()) {
            $plantIds[] = (int)$row['plant_id'];
        }
        $assignStmt->close();
    } elseif ($roleRaw === 'supervisor') {
        if (!$userId) {
            apiRespond(400, ['status' => 'error', 'error' => 'userId required for supervisor role']);
        }

        $directStmt = $conn->prepare('SELECT id FROM plants WHERE supervisor_user_id = ?');
        $directStmt->bind_param('i', $userId);
        $directStmt->execute();
        $directRes = $directStmt->get_result();
        while ($row = $directRes->fetch_assoc()) {
            $plantIds[] = (int)$row['id'];
        }
        $directStmt->close();

        $mapStmt = $conn->prepare('SELECT plant_id FROM supervisor_plants WHERE user_id = ?');
        $mapStmt->bind_param('i', $userId);
        $mapStmt->execute();
        $mapRes = $mapStmt->get_result();
        while ($row = $mapRes->fetch_assoc()) {
            if (!empty($row['plant_id'])) {
                $plantIds[] = (int)$row['plant_id'];
            }
        }
        $mapStmt->close();
    } else {
        $allRes = $conn->query('SELECT id FROM plants');
        while ($row = $allRes->fetch_assoc()) {
            $plantIds[] = (int)$row['id'];
        }
    }

    $plantIds = array_values(array_unique(array_filter($plantIds, static fn($value) => $value > 0)));

    if (empty($plantIds)) {
        apiRespond(200, ['status' => 'ok', 'plants' => []]);
    }

    $nameColumn = 'plant_name';
    $columnCheck = $conn->query("SHOW COLUMNS FROM plants LIKE 'plant_name'");
    if (!$columnCheck || $columnCheck->num_rows === 0) {
        foreach (['name', 'title'] as $candidate) {
            $columnCheck = $conn->query("SHOW COLUMNS FROM plants LIKE '{$candidate}'");
            if ($columnCheck && $columnCheck->num_rows > 0) {
                $nameColumn = $candidate;
                break;
            }
        }
    }

    $placeholders = implode(',', array_fill(0, count($plantIds), '?'));
    $types = str_repeat('i', count($plantIds));
    $stmt = $conn->prepare("SELECT id, {$nameColumn} AS plant_name FROM plants WHERE id IN ({$placeholders}) ORDER BY {$nameColumn}");
    $stmt->bind_param($types, ...$plantIds);
    $stmt->execute();
    $result = $stmt->get_result();

    $plants = [];
    while ($row = $result->fetch_assoc()) {
        $plants[] = [
            'plantId' => (int)$row['id'],
            'plantName' => $row['plant_name'] ?? '',
        ];
    }
    $stmt->close();

    apiRespond(200, ['status' => 'ok', 'plants' => $plants]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
