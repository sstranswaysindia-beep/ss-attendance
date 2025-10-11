<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require __DIR__ . '/common.php';

try {
    global $conn, $mysqli, $con;
    $db = $conn instanceof mysqli ? $conn : ($mysqli instanceof mysqli ? $mysqli : ($con instanceof mysqli ? $con : null));
    
    if (!$db) {
        throw new Exception('Database connection not available');
    }

    // Get query parameters
    $status = $_GET['status'] ?? 'all'; // all, pending, approved, rejected
    $page = max(1, (int)($_GET['page'] ?? 1));
    $limit = min(50, max(1, (int)($_GET['limit'] ?? 20)));
    $offset = ($page - 1) * $limit;

    // Build status filter
    $statusFilter = '';
    $params = [];
    $paramTypes = '';
    
    if ($status !== 'all') {
        $statusFilter = ' WHERE ar.status = ?';
        $params[] = $status;
        $paramTypes .= 's';
    }

    // Get total count
    $countQuery = "SELECT COUNT(*) as total FROM advance_requests ar 
                   LEFT JOIN drivers d ON ar.driver_id = d.id 
                   LEFT JOIN users u ON d.user_id = u.id 
                   LEFT JOIN plants p ON ar.plant_id = p.id
                   $statusFilter";
    
    $stmt = $db->prepare($countQuery);
    if (!empty($params)) {
        $stmt->bind_param($paramTypes, ...$params);
    }
    $stmt->execute();
    $countResult = $stmt->get_result();
    $totalCount = $countResult->fetch_assoc()['total'];
    $stmt->close();

    // Get requests with pagination
    $query = "SELECT 
                ar.id,
                ar.driver_id,
                ar.amount,
                ar.purpose as reason,
                ar.status,
                ar.requested_at as created_at,
                ar.approval_at as approved_at,
                ar.remarks as admin_comments,
                d.name as driver_name,
                d.empid as employee_id,
                u.username,
                u.full_name,
                p.plant_name,
                p.plant_code
              FROM advance_requests ar 
              LEFT JOIN drivers d ON ar.driver_id = d.id 
              LEFT JOIN users u ON d.user_id = u.id 
              LEFT JOIN plants p ON d.plant_id = p.id
              $statusFilter
              ORDER BY ar.requested_at DESC 
              LIMIT ? OFFSET ?";
    
    $params[] = $limit;
    $params[] = $offset;
    $paramTypes .= 'ii';
    
    $stmt = $db->prepare($query);
    $stmt->bind_param($paramTypes, ...$params);
    $stmt->execute();
    $result = $stmt->get_result();
    
    $requests = [];
    while ($row = $result->fetch_assoc()) {
        $requests[] = [
            'id' => (int)$row['id'],
            'driverId' => (int)$row['driver_id'],
            'amount' => (float)$row['amount'],
            'reason' => $row['reason'],
            'status' => $row['status'],
            'createdAt' => $row['created_at'],
            'approvedAt' => $row['approved_at'],
            'adminComments' => $row['admin_comments'],
            'driver' => [
                'name' => $row['driver_name'],
                'employeeId' => $row['employee_id'],
                'username' => $row['username'],
                'fullName' => $row['full_name'],
            ],
            'plant' => [
                'name' => $row['plant_name'],
                'code' => $row['plant_code'],
            ],
        ];
    }
    $stmt->close();

    // Calculate pagination info
    $totalPages = ceil($totalCount / $limit);
    
    apiRespond([
        'success' => true,
        'data' => [
            'requests' => $requests,
            'pagination' => [
                'currentPage' => $page,
                'totalPages' => $totalPages,
                'totalCount' => (int)$totalCount,
                'limit' => $limit,
                'hasNext' => $page < $totalPages,
                'hasPrev' => $page > 1,
            ],
            'filters' => [
                'status' => $status,
            ],
        ],
    ]);

} catch (Exception $e) {
    error_log("Advance requests list error: " . $e->getMessage());
    apiRespond([
        'success' => false,
        'error' => 'Failed to fetch advance requests',
        'message' => $e->getMessage(),
    ], 500);
}
