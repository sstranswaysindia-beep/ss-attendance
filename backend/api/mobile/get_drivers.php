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
    // Query to get active drivers
    $stmt = $conn->prepare("
        SELECT id, name 
        FROM drivers 
        WHERE status = 'Active' 
        ORDER BY name
    ");
    $stmt->execute();
    $result = $stmt->get_result();
    
    $drivers = [];
    while ($row = $result->fetch_assoc()) {
        $drivers[] = [
            'id' => (int)$row['id'],
            'name' => $row['name']
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
