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

    // Get request ID from query parameter
    $requestId = (int)($_GET['id'] ?? 0);
    
    if ($requestId <= 0) {
        apiRespond([
            'success' => false,
            'error' => 'Invalid request ID',
        ], 400);
    }

    // Get detailed request information
    $query = "SELECT 
                ar.id,
                ar.driver_id,
                ar.amount,
                ar.purpose as reason,
                ar.status,
                ar.requested_at as created_at,
                ar.requested_at as updated_at,
                ar.approval_at as approved_at,
                ar.remarks as admin_comments,
                d.name as driver_name,
                d.empid as employee_id,
                d.phone,
                d.address,
                d.joining_date,
                d.salary,
                u.username,
                u.full_name,
                u.email,
                p.plant_name,
                p.plant_code,
                p.address as plant_address
              FROM advance_requests ar 
              LEFT JOIN drivers d ON ar.driver_id = d.id 
              LEFT JOIN users u ON d.user_id = u.id 
              LEFT JOIN plants p ON d.plant_id = p.id
              WHERE ar.id = ?";
    
    $stmt = $db->prepare($query);
    $stmt->bind_param('i', $requestId);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows === 0) {
        $stmt->close();
        apiRespond([
            'success' => false,
            'error' => 'Advance request not found',
        ], 404);
    }
    
    $row = $result->fetch_assoc();
    $stmt->close();

    // Get driver's recent advance requests for context
    $contextQuery = "SELECT 
                       ar.id,
                       ar.amount,
                       ar.status,
                       ar.requested_at as created_at,
                       ar.approval_at as approved_at
                     FROM advance_requests ar 
                     WHERE ar.driver_id = ? AND ar.id != ?
                     ORDER BY ar.requested_at DESC 
                     LIMIT 5";
    
    $stmt = $db->prepare($contextQuery);
    $stmt->bind_param('ii', $row['driver_id'], $requestId);
    $stmt->execute();
    $contextResult = $stmt->get_result();
    
    $recentRequests = [];
    while ($contextRow = $contextResult->fetch_assoc()) {
        $recentRequests[] = [
            'id' => (int)$contextRow['id'],
            'amount' => (float)$contextRow['amount'],
            'status' => $contextRow['status'],
            'createdAt' => $contextRow['created_at'],
            'approvedAt' => $contextRow['approved_at'],
        ];
    }
    $stmt->close();

    // Get driver's total advance statistics
    $statsQuery = "SELECT 
                     COUNT(*) as total_requests,
                     SUM(CASE WHEN status = 'Approved' THEN amount ELSE 0 END) as total_approved,
                     SUM(CASE WHEN status = 'Pending' THEN amount ELSE 0 END) as total_pending,
                     SUM(CASE WHEN status = 'Rejected' THEN amount ELSE 0 END) as total_rejected
                   FROM advance_requests 
                   WHERE driver_id = ?";
    
    $stmt = $db->prepare($statsQuery);
    $stmt->bind_param('i', $row['driver_id']);
    $stmt->execute();
    $statsResult = $stmt->get_result();
    $stats = $statsResult->fetch_assoc();
    $stmt->close();

    $requestData = [
        'id' => (int)$row['id'],
        'driverId' => (int)$row['driver_id'],
        'amount' => (float)$row['amount'],
        'reason' => $row['reason'],
        'status' => $row['status'],
        'createdAt' => $row['created_at'],
        'updatedAt' => $row['updated_at'],
        'approvedAt' => $row['approved_at'],
        'adminComments' => $row['admin_comments'],
        'driver' => [
            'name' => $row['driver_name'],
            'employeeId' => $row['employee_id'],
            'phone' => $row['phone'],
            'address' => $row['address'],
            'joiningDate' => $row['joining_date'],
            'salary' => $row['salary'] ? (float)$row['salary'] : null,
            'username' => $row['username'],
            'fullName' => $row['full_name'],
            'email' => $row['email'],
        ],
        'plant' => [
            'name' => $row['plant_name'],
            'code' => $row['plant_code'],
            'address' => $row['plant_address'],
        ],
        'context' => [
            'recentRequests' => $recentRequests,
            'statistics' => [
                'totalRequests' => (int)$stats['total_requests'],
                'totalApproved' => (float)$stats['total_approved'],
                'totalPending' => (float)$stats['total_pending'],
                'totalRejected' => (float)$stats['total_rejected'],
            ],
        ],
    ];

    apiRespond([
        'success' => true,
        'data' => $requestData,
    ]);

} catch (Exception $e) {
    error_log("Advance request details error: " . $e->getMessage());
    apiRespond([
        'success' => false,
        'error' => 'Failed to fetch advance request details',
        'message' => $e->getMessage(),
    ], 500);
}
