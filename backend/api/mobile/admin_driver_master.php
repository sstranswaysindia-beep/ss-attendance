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
$statusFilter = trim((string) ($_GET['status'] ?? ''));

try {
    $sql = '
        SELECT d.id,
               d.empid,
               d.name,
               d.role,
               d.status,
               d.contact,
               d.dl_number,
               d.dl_validity,
               d.joining_date,
               d.profile_photo_url,
               d.plant_id,
               p.plant_name
          FROM drivers d
     LEFT JOIN plants p ON p.id = d.plant_id
         WHERE 1=1
    ';

    $types = '';
    $params = [];

    if ($statusFilter !== '') {
        $sql .= ' AND d.status = ?';
        $types .= 's';
        $params[] = $statusFilter;
    }

    if ($searchRaw !== '') {
        $sql .= ' AND (d.name LIKE ? OR d.empid LIKE ? OR p.plant_name LIKE ? OR d.contact LIKE ?)';
        $like = '%' . $searchRaw . '%';
        $types .= 'ssss';
        $params[] = $like;
        $params[] = $like;
        $params[] = $like;
        $params[] = $like;
    }

    $sql .= ' ORDER BY d.name ASC';

    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        throw new RuntimeException('Failed to prepare driver query: ' . $conn->error);
    }

    if ($types !== '') {
        apiBindParams($stmt, $types, $params);
    }

    $stmt->execute();
    $result = $stmt->get_result();

    $drivers = [];
    while ($row = $result->fetch_assoc()) {
        $drivers[] = [
            'id' => (int) $row['id'],
            'empId' => (string) ($row['empid'] ?? ''),
            'name' => (string) ($row['name'] ?? ''),
            'role' => (string) ($row['role'] ?? ''),
            'status' => (string) ($row['status'] ?? ''),
            'contact' => (string) ($row['contact'] ?? ''),
            'dlNumber' => (string) ($row['dl_number'] ?? ''),
            'dlValidity' => isset($row['dl_validity']) && $row['dl_validity'] !== null
                ? (string) $row['dl_validity']
                : null,
            'joiningDate' => isset($row['joining_date']) && $row['joining_date'] !== null
                ? (string) $row['joining_date']
                : null,
            'profilePhoto' => (string) ($row['profile_photo_url'] ?? ''),
            'plantId' => isset($row['plant_id']) ? (int) $row['plant_id'] : null,
            'plantName' => (string) ($row['plant_name'] ?? ''),
        ];
    }
    $stmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'count' => count($drivers),
        'drivers' => $drivers,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
