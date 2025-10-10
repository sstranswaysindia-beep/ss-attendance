<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

$role = TD_MOBILE_ROLE;
$userId = TD_MOBILE_USER_ID;
$driverId = TD_MOBILE_DRIVER_ID ?? null;

if (!$driverId && isset($_SESSION['driver_id'])) {
    $driverId = apiSanitizeInt($_SESSION['driver_id']);
}

$sessionPlantId = isset($_SESSION['plant_id']) ? (int)$_SESSION['plant_id'] : 0;
$sessionSupervised = [];
if (!empty($_SESSION['supervised_plant_ids']) && is_array($_SESSION['supervised_plant_ids'])) {
    $sessionSupervised = array_map('intval', $_SESSION['supervised_plant_ids']);
}

$plantIds = [];

if ($sessionPlantId > 0) {
    $plantIds[] = $sessionPlantId;
}
if (!empty($sessionSupervised)) {
    foreach ($sessionSupervised as $sid) {
        if ($sid > 0) {
            $plantIds[] = $sid;
        }
    }
}

if (!$driverId && $userId) {
    $userDriverStmt = $conn->prepare('SELECT driver_id FROM users WHERE id = ? LIMIT 1');
    if ($userDriverStmt) {
        $userDriverStmt->bind_param('i', $userId);
        if ($userDriverStmt->execute()) {
            if ($userRow = $userDriverStmt->get_result()->fetch_assoc()) {
                $driverId = apiSanitizeInt($userRow['driver_id'] ?? null);
            }
        }
        $userDriverStmt->close();
    }
}

try {
    if ($role === 'driver') {
        if (!$driverId) {
            // Without a driver id fall back to session/user-derived plants only.
        } else {
            $selectColumns = [];
            if (td_has_column('drivers', 'plant_id')) {
                $selectColumns[] = 'plant_id AS plant_id';
            }
            if (td_has_column('drivers', 'default_plant_id')) {
                $selectColumns[] = 'default_plant_id AS default_plant_id';
            }
            if (td_has_column('drivers', 'supervisor_of_plant_id')) {
                $selectColumns[] = 'supervisor_of_plant_id AS supervisor_of_plant_id';
            }

            if (!empty($selectColumns)) {
                $driverStmt = $conn->prepare(
                    'SELECT ' . implode(', ', $selectColumns) . ' FROM drivers WHERE id = ? LIMIT 1'
                );
                $driverStmt->bind_param('i', $driverId);
                $driverStmt->execute();
                if ($row = $driverStmt->get_result()->fetch_assoc()) {
                    foreach (['plant_id', 'default_plant_id', 'supervisor_of_plant_id'] as $field) {
                        if (array_key_exists($field, $row) && !empty($row[$field])) {
                            $plantIds[] = (int)$row[$field];
                        }
                    }
                }
                $driverStmt->close();
            }

            $assignStmt = $conn->prepare('SELECT DISTINCT plant_id FROM assignments WHERE driver_id = ? AND plant_id IS NOT NULL');
            $assignStmt->bind_param('i', $driverId);
            $assignStmt->execute();
            $assignRes = $assignStmt->get_result();
            while ($assignRow = $assignRes->fetch_assoc()) {
                $plantIds[] = (int)$assignRow['plant_id'];
            }
            $assignStmt->close();
        }
    } elseif ($role === 'supervisor') {
        if (!$userId && empty($plantIds)) {
            apiRespond(400, ['status' => 'error', 'error' => 'userId required for supervisor role']);
        }

        if ($userId) {
            $directStmt = $conn->prepare('SELECT id FROM plants WHERE supervisor_user_id = ?');
            $directStmt->bind_param('i', $userId);
            $directStmt->execute();
            $directRes = $directStmt->get_result();
            while ($directRow = $directRes->fetch_assoc()) {
                $plantIds[] = (int)$directRow['id'];
            }
            $directStmt->close();

            $mapStmt = $conn->prepare('SELECT plant_id FROM supervisor_plants WHERE user_id = ?');
            $mapStmt->bind_param('i', $userId);
            $mapStmt->execute();
            $mapRes = $mapStmt->get_result();
            while ($mapRow = $mapRes->fetch_assoc()) {
                if (!empty($mapRow['plant_id'])) {
                    $plantIds[] = (int)$mapRow['plant_id'];
                }
            }
            $mapStmt->close();
        }
    } elseif ($role === 'admin') {
        $allRes = $conn->query('SELECT id FROM plants');
        while ($row = $allRes->fetch_assoc()) {
            $plantIds[] = (int)$row['id'];
        }
    } else {
        if ($sessionPlantId > 0 || !empty($sessionSupervised)) {
            // Already seeded from session; no additional filtering needed.
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
            'id' => (int)$row['id'],
            'plant_name' => $row['plant_name'] ?? '',
        ];
    }
    $stmt->close();

    apiRespond(200, ['status' => 'ok', 'plants' => $plants]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
