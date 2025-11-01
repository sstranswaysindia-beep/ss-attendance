<?php
declare(strict_types=1);


function safety_user_context(): array
{
    $role = strtolower(trim((string)($_SESSION['role'] ?? '')));
    $userId = apiSanitizeInt($_SESSION['user_id'] ?? null);
    $driverId = apiSanitizeInt($_SESSION['driver_id'] ?? null);
    $plantId = apiSanitizeInt($_SESSION['plant_id'] ?? null);

    $supervisedPlantIds = [];
    if (!empty($_SESSION['supervised_plant_ids']) && is_array($_SESSION['supervised_plant_ids'])) {
        $supervisedPlantIds = array_values(array_unique(array_filter(
            array_map('intval', $_SESSION['supervised_plant_ids']),
            static fn($value) => $value > 0
        )));
    }

    // Fallback to request payload when session is not populated (mobile JSON/GET)
    $request = array_merge($_GET ?? [], $_POST ?? []);

    if ($role === '' && !empty($request['role'])) {
        $role = strtolower(trim((string)$request['role']));
    }
    if (!$userId) {
        $userId = apiSanitizeInt($request['userId'] ?? $request['user_id'] ?? null);
    }
    if (!$driverId) {
        $driverId = apiSanitizeInt($request['driverId'] ?? $request['driver_id'] ?? null);
    }
    if (!$plantId) {
        $plantId = apiSanitizeInt($request['plantId'] ?? $request['plant_id'] ?? null);
    }
    if (empty($supervisedPlantIds) && !empty($request['supervisedPlantIds'])) {
        $raw = $request['supervisedPlantIds'];
        if (is_array($raw)) {
            $supervisedPlantIds = array_values(array_unique(array_filter(
                array_map('intval', $raw),
                static fn($value) => $value > 0
            )));
        } elseif (is_string($raw)) {
            $parts = array_map('trim', explode(',', $raw));
            $supervisedPlantIds = array_values(array_unique(array_filter(
                array_map('intval', $parts),
                static fn($value) => $value > 0
            )));
        }
    }

    return [
        'role' => $role,
        'user_id' => $userId,
        'driver_id' => $driverId,
        'plant_id' => $plantId,
        'supervised_plant_ids' => $supervisedPlantIds,
    ];
}

function safety_has_column(\mysqli $conn, string $table, string $column): bool
{
    $table = $conn->real_escape_string($table);
    $column = $conn->real_escape_string($column);
    $sql = "SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = '{$table}'
              AND COLUMN_NAME = '{$column}'
            LIMIT 1";
    $result = $conn->query($sql);
    return $result && $result->num_rows > 0;
}

function safety_table_exists(\mysqli $conn, string $table): bool
{
    $table = $conn->real_escape_string($table);
    $sql = "SHOW TABLES LIKE '{$table}'";
    $result = $conn->query($sql);
    return $result && $result->num_rows > 0;
}

function safety_vehicle_tyre_expression(\mysqli $conn): string
{
    return safety_has_column($conn, 'vehicles', 'tyre_count')
        ? "COALESCE(NULLIF(v.tyre_count, 0), 6)"
        : "6";
}

/**
 * Determine plant IDs the current session user can access.
 *
 * @return int[] list of plant IDs
 */
function safety_allowed_plants(\mysqli $conn, string $scope = 'mine'): array
{
    $ctx = safety_user_context();
    $allowed = [];

    if ($ctx['plant_id']) {
        $allowed[] = $ctx['plant_id'];
    }

    if (($ctx['role'] === 'driver' && $ctx['driver_id']) || $scope === 'mine') {
        if ($ctx['driver_id']) {
            // Check current assignment
            $stmt = $conn->prepare(
                'SELECT plant_id FROM assignments WHERE driver_id = ? ORDER BY assigned_date DESC LIMIT 1'
            );
            if ($stmt) {
                $stmt->bind_param('i', $ctx['driver_id']);
                $stmt->execute();
                $res = $stmt->get_result();
                if ($row = $res->fetch_assoc()) {
                    $plantId = (int)$row['plant_id'];
                    if ($plantId > 0) {
                        $allowed[] = $plantId;
                    }
                }
                $stmt->close();
            }

            // Additional driver columns if present
            $columns = [];
            foreach (['plant_id', 'default_plant_id', 'supervisor_of_plant_id'] as $column) {
                if (safety_has_column($conn, 'drivers', $column)) {
                    $columns[] = $column;
                }
            }
            if (!empty($columns)) {
                $select = implode(',', array_map(static fn($col) => "{$col} AS {$col}", $columns));
                $stmt = $conn->prepare("SELECT {$select} FROM drivers WHERE id = ? LIMIT 1");
                if ($stmt) {
                    $stmt->bind_param('i', $ctx['driver_id']);
                    $stmt->execute();
                    $res = $stmt->get_result();
                    if ($row = $res->fetch_assoc()) {
                        foreach ($columns as $column) {
                            $plantId = apiSanitizeInt($row[$column] ?? null);
                            if ($plantId) {
                                $allowed[] = $plantId;
                            }
                        }
                    }
                    $stmt->close();
                }
            }
        }
    }

    if ($ctx['role'] === 'supervisor' || $scope === 'plant') {
        $allowed = array_merge($allowed, $ctx['supervised_plant_ids']);

        if ($ctx['user_id'] && safety_table_exists($conn, 'supervisor_plants')) {
            $stmt = $conn->prepare(
                'SELECT plant_id FROM supervisor_plants WHERE user_id = ?'
            );
            if ($stmt) {
                $stmt->bind_param('i', $ctx['user_id']);
                $stmt->execute();
                $res = $stmt->get_result();
                while ($row = $res->fetch_assoc()) {
                    $plantId = (int)$row['plant_id'];
                    if ($plantId > 0) {
                        $allowed[] = $plantId;
                    }
                }
                $stmt->close();
            }
        }
    }

    $unique = array_values(array_unique(array_filter(
        array_map('intval', $allowed),
        static fn($plantId) => $plantId > 0
    )));
    sort($unique);
    if (empty($unique) && $ctx['role'] === 'admin') {
        $result = $conn->query('SELECT id FROM plants');
        if ($result) {
            while ($row = $result->fetch_assoc()) {
                $id = (int)$row['id'];
                if ($id > 0) {
                    $unique[] = $id;
                }
            }
            sort($unique);
        }
    }
    return $unique;
}

/**
 * Generate tyre position codes (R1, L1, R2, L2, ...).
 */
function safety_generate_positions(int $tyreCount): array
{
    if ($tyreCount <= 0) {
        $tyreCount = 6;
    }

    $positions = [];

    if ($tyreCount >= 1) {
        $positions[] = 'L1';
    }
    if ($tyreCount >= 2) {
        $positions[] = 'R1';
    }

    $remaining = $tyreCount - min($tyreCount, 2);
    $axle = 2;
    $assignExtraToLeft = true;

    while ($remaining > 0) {
        $tyresThisAxle = min($remaining, 4);
        $perSide = intdiv($tyresThisAxle, 2);
        $extra = $tyresThisAxle % 2;

        if ($perSide === 0) {
            $side = $assignExtraToLeft ? 'L' : 'R';
            $positions[] = $side . $axle . '1';
            $assignExtraToLeft = !$assignExtraToLeft;
            $remaining--;
            break;
        }

        for ($slot = 1; $slot <= $perSide; $slot++) {
            $positions[] = 'L' . $axle . $slot;
        }
        for ($slot = 1; $slot <= $perSide; $slot++) {
            $positions[] = 'R' . $axle . $slot;
        }

        $remaining -= $perSide * 2;

        if ($extra > 0) {
            $side = $assignExtraToLeft ? 'L' : 'R';
            $positions[] = $side . $axle . ($perSide + 1);
            $assignExtraToLeft = !$assignExtraToLeft;
            $remaining--;
        }

        $axle++;
    }

    return $positions;
}

function safety_expected_checkpoint_count(): int
{
    return 8;
}

/**
 * @return array{min: float, max: float}
 */
function safety_load_psi_range(\mysqli $conn): array
{
    $psiMin = 120.0;
    $psiMax = 130.0;

    try {
        $stmt = $conn->prepare(
            "SELECT setting_key, setting_value
             FROM system_settings
             WHERE setting_key IN ('SAFETY_TYRE_PSI_MIN', 'SAFETY_TYRE_PSI_MAX')"
        );
        if ($stmt) {
            $stmt->execute();
            $res = $stmt->get_result();
            while ($row = $res->fetch_assoc()) {
                $key = (string)($row['setting_key'] ?? '');
                $value = $row['setting_value'] ?? null;
                if ($value === null) {
                    continue;
                }
                if ($key === 'SAFETY_TYRE_PSI_MIN') {
                    $psiMin = (float)$value;
                } elseif ($key === 'SAFETY_TYRE_PSI_MAX') {
                    $psiMax = (float)$value;
                }
            }
            $stmt->close();
        }
    } catch (Throwable $e) {
        // ignore and fall back to defaults
    }

    return ['min' => $psiMin, 'max' => $psiMax];
}

function safety_document_root(): string
{
    $candidates = [];
    $documentRoot = $_SERVER['DOCUMENT_ROOT'] ?? '';
    if (is_string($documentRoot) && $documentRoot !== '') {
        $candidates[] = rtrim($documentRoot, DIRECTORY_SEPARATOR);
    }

    $candidates[] = dirname(__DIR__, 4) . '/public_html';
    $candidates[] = dirname(__DIR__, 3) . '/public_html';

    foreach ($candidates as $candidate) {
        if (!$candidate) {
            continue;
        }
        $path = rtrim($candidate, DIRECTORY_SEPARATOR);
        if (is_dir($path)) {
            $real = realpath($path);
            return $real !== false ? rtrim($real, DIRECTORY_SEPARATOR) : $path;
        }
    }

    $fallback = dirname(__DIR__, 3) . '/public_html';
    if (!is_dir($fallback)) {
        @mkdir($fallback, 0755, true);
    }
    $real = realpath($fallback);
    return $real !== false ? rtrim($real, DIRECTORY_SEPARATOR) : rtrim($fallback, DIRECTORY_SEPARATOR);
}

/**
 * @return array{relative: string, absolute: string}
 */
function safety_store_tyre_photo(int $vehicleId, string $positionCode, string $photoBase64): array
{
    $payload = trim($photoBase64);
    if ($payload === '') {
        throw new InvalidArgumentException('Empty photo payload');
    }

    $extension = 'jpg';
    if (preg_match('/^data:image\/([a-zA-Z0-9+]+);base64,/', $payload, $matches) === 1) {
        $extension = strtolower($matches[1]);
        $payload = substr($payload, strpos($payload, ',') + 1);
    }

    $binary = base64_decode($payload, true);
    if ($binary === false) {
        throw new InvalidArgumentException('Invalid photo payload');
    }

    if (!in_array($extension, ['jpg', 'jpeg'], true)) {
        $image = @imagecreatefromstring($binary);
        if ($image === false) {
            throw new RuntimeException('Unable to decode image payload');
        }
        ob_start();
        imagejpeg($image, null, 90);
        $binary = ob_get_clean();
        imagedestroy($image);
        if ($binary === false) {
            throw new RuntimeException('Unable to re-encode image payload');
        }
        $extension = 'jpg';
    } else {
        $extension = 'jpg';
    }

    $date = new \DateTimeImmutable('now', new \DateTimeZone('Asia/Kolkata'));
    $dateFolder = $date->format('Y-m-d');
    $documentRoot = safety_document_root();
    $targetDir = $documentRoot . "/DriverDocs/uploads/tyre/{$vehicleId}/{$dateFolder}";
    if (!is_dir($targetDir) && !mkdir($targetDir, 0755, true) && !is_dir($targetDir)) {
        throw new RuntimeException('Unable to create tyre photo directory');
    }

    $safePosition = preg_replace('/[^A-Za-z0-9]+/', '_', strtoupper($positionCode)) ?: 'tyre';
    $fileName = sprintf(
        '%s_%s.%s',
        $safePosition,
        $date->format('His'),
        $extension
    );
    $absolutePath = $targetDir . '/' . $fileName;

    if (file_put_contents($absolutePath, $binary) === false) {
        throw new RuntimeException('Unable to write tyre photo');
    }

    $relative = "/DriverDocs/uploads/tyre/{$vehicleId}/{$dateFolder}/{$fileName}";
    return ['relative' => $relative, 'absolute' => $absolutePath];
}
