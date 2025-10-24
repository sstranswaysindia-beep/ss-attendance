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

$searchRaw = trim((string) ($_GET['q'] ?? $_GET['search'] ?? ''));
$plantFilter = apiSanitizeInt($_GET['plantId'] ?? null);

try {
    $sql = '
        SELECT v.id,
               v.vehicle_no,
               v.plant_id,
               p.plant_name,
               vd.gps,
               vd.company,
               vd.location,
               vd.model_no,
               vd.registration_date,
               vd.fitness_expiry,
               vd.insurance_expiry,
               vd.pollution_expiry,
               vd.brake_test_expiry
          FROM vehicles v
     LEFT JOIN plants p ON p.id = v.plant_id
     LEFT JOIN vehicle_details vd ON vd.vehicle_id = v.id
         WHERE 1=1
    ';

    $types = '';
    $params = [];

    if ($plantFilter !== null && $plantFilter > 0) {
        $sql .= ' AND v.plant_id = ?';
        $types .= 'i';
        $params[] = $plantFilter;
    }

    if ($searchRaw !== '') {
        $sql .= ' AND (v.vehicle_no LIKE ? OR p.plant_name LIKE ? OR vd.company LIKE ? OR vd.location LIKE ?)';
        $like = '%' . $searchRaw . '%';
        $types .= 'ssss';
        $params[] = $like;
        $params[] = $like;
        $params[] = $like;
        $params[] = $like;
    }

    $sql .= ' ORDER BY p.plant_name ASC, v.vehicle_no ASC';

    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        throw new RuntimeException('Failed to prepare vehicle query: ' . $conn->error);
    }

    if ($types !== '') {
        apiBindParams($stmt, $types, $params);
    }

    $stmt->execute();
    $result = $stmt->get_result();

    $vehicles = [];
    while ($row = $result->fetch_assoc()) {
        $vehicles[] = [
            'id' => (int) $row['id'],
            'vehicleNo' => (string) ($row['vehicle_no'] ?? ''),
            'plantId' => isset($row['plant_id']) ? (int) $row['plant_id'] : null,
            'plantName' => (string) ($row['plant_name'] ?? ''),
            'gps' => (string) ($row['gps'] ?? ''),
            'company' => (string) ($row['company'] ?? ''),
            'location' => (string) ($row['location'] ?? ''),
            'modelNo' => (string) ($row['model_no'] ?? ''),
            'registrationDate' => isset($row['registration_date']) && $row['registration_date'] !== null
                ? (string) $row['registration_date']
                : null,
            'fitnessExpiry' => isset($row['fitness_expiry']) && $row['fitness_expiry'] !== null
                ? (string) $row['fitness_expiry']
                : null,
            'insuranceExpiry' => isset($row['insurance_expiry']) && $row['insurance_expiry'] !== null
                ? (string) $row['insurance_expiry']
                : null,
            'pollutionExpiry' => isset($row['pollution_expiry']) && $row['pollution_expiry'] !== null
                ? (string) $row['pollution_expiry']
                : null,
            'brakeTestExpiry' => isset($row['brake_test_expiry']) && $row['brake_test_expiry'] !== null
                ? (string) $row['brake_test_expiry']
                : null,
        ];
    }
    $stmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'count' => count($vehicles),
        'vehicles' => $vehicles,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
