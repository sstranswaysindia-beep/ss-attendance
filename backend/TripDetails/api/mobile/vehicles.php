<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

if (!function_exists('td_table_exists')) {
    function td_table_exists(mysqli $db, string $table): bool
    {
        $table = $db->real_escape_string($table);
        $res = $db->query("SHOW TABLES LIKE '{$table}'");
        return $res && $res->num_rows > 0;
    }
}

if (!function_exists('td_has_column')) {
    function td_has_column(mysqli $db, string $table, string $column): bool
    {
        $table = $db->real_escape_string($table);
        $column = $db->real_escape_string($column);
        $sql = "SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = '{$table}'
                  AND COLUMN_NAME = '{$column}'
                LIMIT 1";
        $res = $db->query($sql);
        return $res && $res->num_rows > 0;
    }
}

$role = TD_MOBILE_ROLE;
$userId = TD_MOBILE_USER_ID;
$driverId = TD_MOBILE_DRIVER_ID;
$plantId = apiSanitizeInt(td_request_value('plantId', td_request_value('plant_id')));
$q = trim((string)td_request_value('q', td_request_value('query', td_request_value('search'))));

if (!$driverId && isset($_SESSION['driver_id'])) {
    $driverId = apiSanitizeInt($_SESSION['driver_id']);
}

$sessionPlantId = isset($_SESSION['plant_id']) ? (int)$_SESSION['plant_id'] : 0;
$sessionSupervised = [];
if (!empty($_SESSION['supervised_plant_ids']) && is_array($_SESSION['supervised_plant_ids'])) {
    $sessionSupervised = array_map('intval', $_SESSION['supervised_plant_ids']);
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

// plantId is normally required.
// Exceptions:
// - supervisor/admin global search mode (q provided)
// - supervisor/admin global list mode (plantId=0 with empty q) to populate pickers
$isSupervisorOrAdmin = in_array($role, ['supervisor', 'admin'], true);
if (!$plantId && !($isSupervisorOrAdmin && $q !== '')) {
    apiRespond(400, ['status' => 'error', 'error' => 'plantId is required']);
}

try {
    $hasAccess = false;

    // Supervisor/admin: allow searching vehicles across ALL plants when q is provided.
    // This is used for global search in Khata Book vehicle picker.
    if ($q !== '' && in_array($role, ['supervisor', 'admin'], true)) {
        $column = 'vehicle_no';
        $columnCheck = $conn->query("SHOW COLUMNS FROM vehicles LIKE 'vehicle_no'");
        if (!$columnCheck || $columnCheck->num_rows === 0) {
            foreach (['number', 'reg_no', 'registration_no'] as $candidate) {
                $columnCheck = $conn->query("SHOW COLUMNS FROM vehicles LIKE '{$candidate}'");
                if ($columnCheck && $columnCheck->num_rows > 0) {
                    $column = $candidate;
                    break;
                }
            }
        }

        $plantColumnCheck = $conn->query("SHOW COLUMNS FROM vehicles LIKE 'plant_id'");
        if (!$plantColumnCheck || $plantColumnCheck->num_rows === 0) {
            apiRespond(200, ['status' => 'ok', 'vehicles' => []]);
        }

        $like = '%' . $q . '%';
        // Try to include plant name if plants table/column exists (schema differs between deployments).
        $plantsTableExists = false;
        $plantsRes = $conn->query("SHOW TABLES LIKE 'plants'");
        if ($plantsRes && $plantsRes->num_rows > 0) {
            $plantsTableExists = true;
        }
        $plantNameCol = null;
        if ($plantsTableExists) {
            foreach (['plant_name', 'name', 'plant'] as $cand) {
                $colRes = $conn->query("SHOW COLUMNS FROM plants LIKE '{$cand}'");
                if ($colRes && $colRes->num_rows > 0) {
                    $plantNameCol = $cand;
                    break;
                }
            }
        }

        if ($plantsTableExists && $plantNameCol) {
            $sql = "
                SELECT v.id,
                       v.{$column} AS vehicle_no,
                       v.plant_id AS plant_id,
                       COALESCE(p.{$plantNameCol}, '') AS plant_name
                FROM vehicles v
                LEFT JOIN plants p ON p.id = v.plant_id
                WHERE v.plant_id IS NOT NULL
                  AND (
                        v.{$column} LIKE ?
                        OR CAST(v.plant_id AS CHAR) LIKE ?
                        OR COALESCE(p.{$plantNameCol}, '') LIKE ?
                      )
                ORDER BY v.{$column}
                LIMIT 200
            ";
            $stmt = $conn->prepare($sql);
            $stmt->bind_param('sss', $like, $like, $like);
        } else {
            $sql = "
                SELECT v.id,
                       v.{$column} AS vehicle_no,
                       v.plant_id AS plant_id,
                       '' AS plant_name
                FROM vehicles v
                WHERE v.plant_id IS NOT NULL
                  AND (v.{$column} LIKE ? OR CAST(v.plant_id AS CHAR) LIKE ?)
                ORDER BY v.{$column}
                LIMIT 200
            ";
            $stmt = $conn->prepare($sql);
            $stmt->bind_param('ss', $like, $like);
        }
        $stmt->execute();
        $res = $stmt->get_result();

        $vehicles = [];
        while ($row = $res->fetch_assoc()) {
            $number = trim((string)($row['vehicle_no'] ?? ''));
            if ($number === '') continue;
            $vehicles[] = [
                'id' => (int)($row['id'] ?? 0),
                'vehicle_no' => $number,
                'plant_id' => (int)($row['plant_id'] ?? 0),
                'plant_name' => (string)($row['plant_name'] ?? ''),
            ];
        }
        $stmt->close();

        apiRespond(200, ['status' => 'ok', 'vehicles' => $vehicles]);
    }

    // Supervisor/admin: allow listing vehicles across ALL plants when plantId=0 and q is empty.
    // Note: capped to avoid very large payloads.
    if ($plantId === 0 && $q === '' && $isSupervisorOrAdmin) {
        $column = 'vehicle_no';
        $columnCheck = $conn->query("SHOW COLUMNS FROM vehicles LIKE 'vehicle_no'");
        if (!$columnCheck || $columnCheck->num_rows === 0) {
            foreach (['number', 'reg_no', 'registration_no'] as $candidate) {
                $columnCheck = $conn->query("SHOW COLUMNS FROM vehicles LIKE '{$candidate}'");
                if ($columnCheck && $columnCheck->num_rows > 0) {
                    $column = $candidate;
                    break;
                }
            }
        }

        $plantColumnCheck = $conn->query("SHOW COLUMNS FROM vehicles LIKE 'plant_id'");
        if (!$plantColumnCheck || $plantColumnCheck->num_rows === 0) {
            apiRespond(200, ['status' => 'ok', 'vehicles' => []]);
        }

        // Try to include plant name if plants table/column exists (schema differs between deployments).
        $plantsTableExists = false;
        $plantsRes = $conn->query("SHOW TABLES LIKE 'plants'");
        if ($plantsRes && $plantsRes->num_rows > 0) {
            $plantsTableExists = true;
        }
        $plantNameCol = null;
        if ($plantsTableExists) {
            foreach (['plant_name', 'name', 'plant'] as $cand) {
                $colRes = $conn->query("SHOW COLUMNS FROM plants LIKE '{$cand}'");
                if ($colRes && $colRes->num_rows > 0) {
                    $plantNameCol = $cand;
                    break;
                }
            }
        }

        if ($plantsTableExists && $plantNameCol) {
            $sql = "
                SELECT v.id,
                       v.{$column} AS vehicle_no,
                       v.plant_id AS plant_id,
                       COALESCE(p.{$plantNameCol}, '') AS plant_name
                FROM vehicles v
                LEFT JOIN plants p ON p.id = v.plant_id
                WHERE v.plant_id IS NOT NULL
                ORDER BY v.{$column}
                LIMIT 500
            ";
            $stmt = $conn->prepare($sql);
        } else {
            $sql = "
                SELECT v.id,
                       v.{$column} AS vehicle_no,
                       v.plant_id AS plant_id,
                       '' AS plant_name
                FROM vehicles v
                WHERE v.plant_id IS NOT NULL
                ORDER BY v.{$column}
                LIMIT 500
            ";
            $stmt = $conn->prepare($sql);
        }

        $stmt->execute();
        $res = $stmt->get_result();

        $vehicles = [];
        while ($row = $res->fetch_assoc()) {
            $number = trim((string)($row['vehicle_no'] ?? ''));
            if ($number === '') continue;
            $vehicles[] = [
                'id' => (int)($row['id'] ?? 0),
                'vehicle_no' => $number,
                'plant_id' => (int)($row['plant_id'] ?? 0),
                'plant_name' => (string)($row['plant_name'] ?? ''),
            ];
        }
        $stmt->close();

        apiRespond(200, ['status' => 'ok', 'vehicles' => $vehicles]);
    }

    $allowedPlantIds = [];
    if ($sessionPlantId > 0) {
        $allowedPlantIds[] = $sessionPlantId;
    }
    foreach ($sessionSupervised as $sid) {
        if ($sid > 0) {
            $allowedPlantIds[] = $sid;
        }
    }

    if ($role === 'driver') {
        if ($driverId) {
            $selectColumns = [];
            if (td_has_column($conn, 'drivers', 'plant_id')) {
                $selectColumns[] = 'plant_id AS plant_id';
            }
            if (td_has_column($conn, 'drivers', 'default_plant_id')) {
                $selectColumns[] = 'default_plant_id AS default_plant_id';
            }
            if (td_has_column($conn, 'drivers', 'supervisor_of_plant_id')) {
                $selectColumns[] = 'supervisor_of_plant_id AS supervisor_of_plant_id';
            }

            if (!empty($selectColumns)) {
                $driverStmt = $conn->prepare(
                    'SELECT ' . implode(', ', $selectColumns) . ' FROM drivers WHERE id = ? LIMIT 1'
                );
                if ($driverStmt) {
                    $driverStmt->bind_param('i', $driverId);
                    $driverStmt->execute();
                    if ($row = $driverStmt->get_result()->fetch_assoc()) {
                        foreach (['plant_id', 'default_plant_id', 'supervisor_of_plant_id'] as $field) {
                            if (isset($row[$field]) && (int)$row[$field] > 0) {
                                $allowedPlantIds[] = (int)$row[$field];
                            }
                        }
                    }
                    $driverStmt->close();
                }
            }

            $assignStmt = $conn->prepare('SELECT DISTINCT plant_id FROM assignments WHERE driver_id = ? AND plant_id IS NOT NULL');
            if ($assignStmt) {
                $assignStmt->bind_param('i', $driverId);
                $assignStmt->execute();
                $assignRes = $assignStmt->get_result();
                while ($assignRow = $assignRes->fetch_assoc()) {
                    $allowedPlantIds[] = (int)$assignRow['plant_id'];
                }
                $assignStmt->close();
            }
        }

        $hasAccess = in_array($plantId, $allowedPlantIds, true);

        if (!$hasAccess && $driverId) {
            $fallbackStmt = $conn->prepare('SELECT 1 FROM assignments WHERE driver_id = ? AND plant_id = ? LIMIT 1');
            if ($fallbackStmt) {
                $fallbackStmt->bind_param('ii', $driverId, $plantId);
                $fallbackStmt->execute();
                $hasAccess = (bool)$fallbackStmt->get_result()->fetch_assoc();
                $fallbackStmt->close();
            }
        }

        if (!$hasAccess && !$driverId) {
            apiRespond(400, ['status' => 'error', 'error' => 'driverId required for driver role']);
        }
    } elseif ($role === 'supervisor') {
        if (!$userId) {
            apiRespond(400, ['status' => 'error', 'error' => 'userId required for supervisor role']);
        }

        if (!empty($sessionSupervised)) {
            $hasAccess = in_array($plantId, $sessionSupervised, true);
        }

        if (!$hasAccess) {
            $directStmt = $conn->prepare('SELECT 1 FROM plants WHERE id = ? AND supervisor_user_id = ? LIMIT 1');
            if ($directStmt) {
                $directStmt->bind_param('ii', $plantId, $userId);
                $directStmt->execute();
                $hasAccess = (bool)$directStmt->get_result()->fetch_assoc();
                $directStmt->close();
            }
        }

        if (!$hasAccess) {
            $mapStmt = $conn->prepare('SELECT 1 FROM supervisor_plants WHERE user_id = ? AND plant_id = ? LIMIT 1');
            if ($mapStmt) {
                $mapStmt->bind_param('ii', $userId, $plantId);
                $mapStmt->execute();
                $hasAccess = (bool)$mapStmt->get_result()->fetch_assoc();
                $mapStmt->close();
            }
        }
    } elseif ($role === 'admin') {
        $hasAccess = true;
    } else {
        $hasAccess = in_array($plantId, $allowedPlantIds, true);
    }

    if (!$hasAccess) {
        apiRespond(403, ['status' => 'error', 'error' => 'Access denied for this plant']);
    }

    $column = 'vehicle_no';
    $columnCheck = $conn->query("SHOW COLUMNS FROM vehicles LIKE 'vehicle_no'");
    if (!$columnCheck || $columnCheck->num_rows === 0) {
        foreach (['number', 'reg_no', 'registration_no'] as $candidate) {
            $columnCheck = $conn->query("SHOW COLUMNS FROM vehicles LIKE '{$candidate}'");
            if ($columnCheck && $columnCheck->num_rows > 0) {
                $column = $candidate;
                break;
            }
        }
    }

    $plantColumnCheck = $conn->query("SHOW COLUMNS FROM vehicles LIKE 'plant_id'");
    if (!$plantColumnCheck || $plantColumnCheck->num_rows === 0) {
        apiRespond(200, ['status' => 'ok', 'vehicles' => []]);
    }

    $stmt = $conn->prepare("SELECT id, {$column} AS vehicle_no FROM vehicles WHERE plant_id = ? ORDER BY {$column}");
    $stmt->bind_param('i', $plantId);
    $stmt->execute();
    $result = $stmt->get_result();

    $vehicles = [];

    $lastEndedTripStmt = null;
    $recentCustomersStmt = null;
    $lastTripVehicleId = 0;
    $recentCustomersVehicleId = 0;

    $hasTrips = td_table_exists($conn, 'trips');
    $hasTripCustomers = $hasTrips && td_table_exists($conn, 'trip_customers');

    if ($hasTrips) {
        $lastEndedTripStmt = $conn->prepare(
            'SELECT end_km, end_date FROM trips
             WHERE vehicle_id = ? AND end_km IS NOT NULL
             ORDER BY COALESCE(end_date, start_date) DESC, id DESC
             LIMIT 1'
        );
        if ($lastEndedTripStmt) {
            $lastEndedTripStmt->bind_param('i', $lastTripVehicleId);
        }
    }

    if ($hasTripCustomers) {
        $recentCustomersStmt = $conn->prepare(
            'SELECT tc.customer_name
             FROM trip_customers tc
             JOIN trips t ON t.id = tc.trip_id
             WHERE t.vehicle_id = ?
             ORDER BY tc.id DESC
             LIMIT 8'
        );
        if ($recentCustomersStmt) {
            $recentCustomersStmt->bind_param('i', $recentCustomersVehicleId);
        }
    }

    while ($row = $result->fetch_assoc()) {
        $number = trim((string)($row['vehicle_no'] ?? ''));
        if ($number !== '') {
            $vehicleId = (int)$row['id'];
            $lastEndKm = null;
            $lastEndDate = null;

            if ($lastEndedTripStmt) {
                $lastTripVehicleId = $vehicleId;
                if ($lastEndedTripStmt->execute()) {
                    $endedResult = $lastEndedTripStmt->get_result();
                    if ($endedResult && ($endedRow = $endedResult->fetch_assoc())) {
                        if ($endedRow['end_km'] !== null && $endedRow['end_km'] !== '') {
                            $lastEndKm = (int)$endedRow['end_km'];
                        }
                        if (!empty($endedRow['end_date'])) {
                            $lastEndDate = (string)$endedRow['end_date'];
                        }
                    }
                }
            }

            $recentCustomers = [];
            if ($recentCustomersStmt) {
                $recentCustomersVehicleId = $vehicleId;
                if ($recentCustomersStmt->execute()) {
                    $customersResult = $recentCustomersStmt->get_result();
                    if ($customersResult) {
                        while ($customerRow = $customersResult->fetch_assoc()) {
                            $name = trim((string)($customerRow['customer_name'] ?? ''));
                            if ($name === '') {
                                continue;
                            }
                            if (!in_array($name, $recentCustomers, true)) {
                                $recentCustomers[] = $name;
                            }
                            if (count($recentCustomers) >= 5) {
                                break;
                            }
                        }
                    }
                }
            }

            $vehicles[] = [
                'id' => $vehicleId,
                'vehicle_no' => $number,
                'last_end_km' => $lastEndKm,
                'last_end_date' => $lastEndDate,
                'recent_customers' => $recentCustomers,
            ];
        }
    }
    $stmt->close();

    if ($lastEndedTripStmt) {
        $lastEndedTripStmt->close();
    }
    if ($recentCustomersStmt) {
        $recentCustomersStmt->close();
    }

    apiRespond(200, ['status' => 'ok', 'vehicles' => $vehicles]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
