<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/common.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    apiRespond(405, ['status' => 'error', 'error' => 'Method not allowed']);
}

/**
 * Normalise enum/text flags into booleans.
 */
function admin_geofence_normalize_flag($value): bool
{
    if ($value === null) {
        return false;
    }
    if (is_bool($value)) {
        return $value;
    }
    $normalized = strtolower(trim((string) $value));
    return $normalized === 'y'
        || $normalized === 'yes'
        || $normalized === '1'
        || $normalized === 'true';
}

$plantFilter = apiSanitizeInt($_GET['plantId'] ?? $_GET['plant_id'] ?? null);

try {
    $plantMap = [];
    $plantsUsed = [];

    $plantResult = $conn->query(
        'SELECT id, plant_name
           FROM plants
       ORDER BY plant_name ASC'
    );
    if ($plantResult) {
        while ($row = $plantResult->fetch_assoc()) {
            $plantId = (int) $row['id'];
            $plantMap[$plantId] = (string) ($row['plant_name'] ?? '');
        }
        $plantResult->close();
    }

    $users = [];

    // Collect active driver/helper accounts with their master plant.
    $driverSql = "
        SELECT u.id            AS user_id,
               u.full_name     AS full_name,
               u.username      AS username,
               u.role          AS user_role,
               u.geofencing_enable,
               u.last_login_at,
               d.empid         AS emp_id,
               d.contact       AS contact,
               d.status        AS driver_status,
               d.plant_id      AS plant_id
          FROM users u
          JOIN drivers d ON d.id = u.driver_id
         WHERE LOWER(TRIM(u.role)) IN ('driver', 'helper')
      ORDER BY u.full_name ASC
    ";
    $driverResult = $conn->query($driverSql);
    if ($driverResult) {
        while ($row = $driverResult->fetch_assoc()) {
            $driverStatus = strtolower(trim((string) ($row['driver_status'] ?? '')));
            if ($driverStatus !== '' && $driverStatus !== 'active') {
                continue;
            }

            $plantId = isset($row['plant_id']) ? (int) $row['plant_id'] : null;
            $plantList = [];
            if ($plantId && isset($plantMap[$plantId])) {
                $plantList[] = [
                    'id' => $plantId,
                    'name' => $plantMap[$plantId],
                ];
                $plantsUsed[$plantId] = true;
            }

            if ($plantFilter && $plantId !== $plantFilter) {
                continue;
            }

            $userRole = strtolower(trim((string) ($row['user_role'] ?? 'driver')));
            if ($userRole !== 'helper') {
                $userRole = 'driver';
            }

            $users[] = [
                'userId' => (int) $row['user_id'],
                'fullName' => (string) ($row['full_name'] ?? ''),
                'role' => $userRole,
                'username' => (string) ($row['username'] ?? ''),
                'contact' => (string) ($row['contact'] ?? ''),
                'employeeId' => (string) ($row['emp_id'] ?? ''),
                'plants' => $plantList,
                'geofencingEnabled' => admin_geofence_normalize_flag($row['geofencing_enable'] ?? null),
                'lastLoginAt' => $row['last_login_at'] ?? null,
            ];
        }
        $driverResult->close();
    }

    // Fetch supervisor accounts.
    $supervisorSql = "
        SELECT u.id        AS user_id,
               u.full_name AS full_name,
               u.username  AS username,
               u.geofencing_enable,
               u.last_login_at
          FROM users u
         WHERE LOWER(TRIM(u.role)) = 'supervisor'
      ORDER BY u.full_name ASC
    ";
    $supervisorResult = $conn->query($supervisorSql);

    $supervisorPlantMap = [];
    $mapResult = $conn->query(
        'SELECT user_id, plant_id
           FROM supervisor_plants
          WHERE user_id IS NOT NULL AND plant_id IS NOT NULL'
    );
    if ($mapResult) {
        while ($row = $mapResult->fetch_assoc()) {
            $userId = (int) $row['user_id'];
            $plantId = (int) $row['plant_id'];
            if (!isset($supervisorPlantMap[$userId])) {
                $supervisorPlantMap[$userId] = [];
            }
            $supervisorPlantMap[$userId][$plantId] = true;
        }
        $mapResult->close();
    }

    $directResult = $conn->query(
        'SELECT supervisor_user_id AS user_id, id AS plant_id
           FROM plants
          WHERE supervisor_user_id IS NOT NULL'
    );
    if ($directResult) {
        while ($row = $directResult->fetch_assoc()) {
            $userId = (int) $row['user_id'];
            $plantId = (int) $row['plant_id'];
            if (!isset($supervisorPlantMap[$userId])) {
                $supervisorPlantMap[$userId] = [];
            }
            $supervisorPlantMap[$userId][$plantId] = true;
        }
        $directResult->close();
    }

    if ($supervisorResult) {
        while ($row = $supervisorResult->fetch_assoc()) {
            $userId = (int) $row['user_id'];
            $plantIds = array_keys($supervisorPlantMap[$userId] ?? []);

            $plantList = [];
            foreach ($plantIds as $pid) {
                if (!isset($plantMap[$pid])) {
                    continue;
                }
                $plantList[] = [
                    'id' => $pid,
                    'name' => $plantMap[$pid],
                ];
                $plantsUsed[$pid] = true;
            }

            if ($plantFilter && !in_array($plantFilter, $plantIds, true)) {
                continue;
            }

            $users[] = [
                'userId' => $userId,
                'fullName' => (string) ($row['full_name'] ?? ''),
                'role' => 'supervisor',
                'username' => (string) ($row['username'] ?? ''),
                'contact' => '',
                'employeeId' => null,
                'plants' => $plantList,
                'geofencingEnabled' => admin_geofence_normalize_flag($row['geofencing_enable'] ?? null),
                'lastLoginAt' => $row['last_login_at'] ?? null,
            ];
        }
        $supervisorResult->close();
    }

    usort($users, static function (array $a, array $b): int {
        return strcasecmp($a['fullName'], $b['fullName']);
    });

    $plantOptions = [];
    foreach (array_keys($plantsUsed) as $plantId) {
        if (!isset($plantMap[$plantId])) {
            continue;
        }
        $plantOptions[] = [
            'id' => $plantId,
            'name' => $plantMap[$plantId],
        ];
    }

    usort($plantOptions, static function (array $a, array $b): int {
        return strcasecmp($a['name'], $b['name']);
    });

    apiRespond(200, [
        'status' => 'ok',
        'users' => $users,
        'plants' => $plantOptions,
        'count' => count($users),
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
