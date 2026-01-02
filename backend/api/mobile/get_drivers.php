<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/common.php';

// Handle OPTIONS request for CORS
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

// Only allow GET requests
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    apiRespond(405, ['status' => 'error', 'error' => 'Method not allowed']);
}

try {
    if (!function_exists('column_exists')) {
        function column_exists(mysqli $db, string $table, string $column): bool {
            $tableEsc = $db->real_escape_string($table);
            $columnEsc = $db->real_escape_string($column);
            $sql = "
                SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = '{$tableEsc}'
                  AND COLUMN_NAME = '{$columnEsc}'
                LIMIT 1
            ";
            $res = $db->query($sql);
            $exists = $res && $res->num_rows > 0;
            if ($res instanceof mysqli_result) {
                $res->free();
            }
            return $exists;
        }
    }

    if (!function_exists('table_exists')) {
        function table_exists(mysqli $db, string $table): bool {
            $tableEsc = $db->real_escape_string($table);
            $res = $db->query("SHOW TABLES LIKE '{$tableEsc}'");
            $exists = $res && $res->num_rows > 0;
            if ($res instanceof mysqli_result) {
                $res->free();
            }
            return $exists;
        }
    }

    $hasPlantId = column_exists($conn, 'drivers', 'plant_id');
    $hasPlants = $hasPlantId && table_exists($conn, 'plants') && column_exists($conn, 'plants', 'plant_name');

    $plantSelect = $hasPlants ? ', p.plant_name' : ', NULL AS plant_name';
    $plantJoin = $hasPlants ? ' LEFT JOIN plants p ON p.id = d.plant_id' : '';
    $plantIdSelect = $hasPlantId ? ', d.plant_id' : ', NULL AS plant_id';

    // Query to get active drivers (with plant if available)
    $stmt = $conn->prepare("
        SELECT d.id, d.name {$plantIdSelect} {$plantSelect}
        FROM drivers d
        {$plantJoin}
        WHERE d.status = 'Active'
        ORDER BY d.name
    ");
    $stmt->execute();
    $result = $stmt->get_result();
    
    $drivers = [];
    while ($row = $result->fetch_assoc()) {
        $drivers[] = [
            'id' => (int)$row['id'],
            'name' => $row['name'],
            'plant' => $row['plant_name'] ?? null,
        ];
    }
    $stmt->close();

    error_log("DEBUG: Found " . count($drivers) . " active drivers");

    apiRespond(200, [
        'status' => 'ok',
        'drivers' => $drivers
    ]);
} catch (Throwable $error) {
    error_log("DEBUG: Get drivers error - " . $error->getMessage());
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
