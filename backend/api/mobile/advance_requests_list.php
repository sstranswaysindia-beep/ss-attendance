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

$role = TD_MOBILE_ROLE;
$userId = TD_MOBILE_USER_ID;
$driverId = TD_MOBILE_DRIVER_ID;

// Only supervisors and admins can view advance requests
if (!in_array($role, ['supervisor', 'admin'])) {
    apiRespond(403, ['ok' => false, 'error' => 'Access denied. Only supervisors and admins can view advance requests.']);
}

/* -------- DB handle -------- */
try {
    global $conn, $mysqli, $con;
    /** @var mysqli|null $db */
    $db = $conn instanceof mysqli ? $conn
        : ($mysqli instanceof mysqli ? $mysqli
        : ($con instanceof mysqli ? $con : null));
    
    if (!$db || $db->connect_errno) {
        apiRespond(500, ['ok' => false, 'error' => 'Database connection not available']);
    }
    
    @$db->set_charset('utf8mb4');
    mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

    // Get query parameters
    $status = $_GET['status'] ?? 'all'; // all, pending, approved, rejected
    $page = max(1, (int)($_GET['page'] ?? 1));
    $limit = min(50, max(10, (int)($_GET['limit'] ?? 20)));
    $offset = ($page - 1) * $limit;

    // Build the query based on user role and status filter
    $whereConditions = [];
    $params = [];
    $paramTypes = '';

    if ($role === 'supervisor') {
        // Supervisors can only see requests from drivers in plants they supervise
        $whereConditions[] = "d.plant_id IN (
            SELECT sp.plant_id FROM supervisor_plants sp 
            WHERE sp.supervisor_id = ?
        )";
        $params[] = $userId;
        $paramTypes .= 'i';
    }

    if ($status !== 'all') {
        $whereConditions[] = "ar.status = ?";
        $params[] = $status;
        $paramTypes .= 's';
    }

    $whereClause = $whereConditions ? 'WHERE ' . implode(' AND ', $whereConditions) : '';

    // Get total count
    $countQuery = "
        SELECT COUNT(*) as total
        FROM advance_requests ar
        LEFT JOIN drivers d ON d.id = ar.driver_id
        LEFT JOIN vehicles v ON v.id = d.vehicle_id
        {$whereClause}
    ";

    $stmt = $db->prepare($countQuery);
    if ($params) {
        $stmt->bind_param($paramTypes, ...$params);
    }
    $stmt->execute();
    $result = $stmt->get_result();
    $totalCount = $result->fetch_assoc()['total'];
    $stmt->close();

    // Get advance requests with pagination
    $query = "
        SELECT 
            ar.id,
            ar.driver_id,
            ar.amount,
            ar.reason,
            ar.status,
            ar.created_at,
            ar.approved_by,
            ar.approved_at,
            ar.approval_comments,
            d.name as driver_name,
            d.employee_id,
            d.phone as driver_phone,
            v.vehicle_number,
            p.plant_name,
            approver.name as approver_name,
            approver.username as approver_username
        FROM advance_requests ar
        LEFT JOIN drivers d ON d.id = ar.driver_id
        LEFT JOIN vehicles v ON v.id = d.vehicle_id
        LEFT JOIN plants p ON p.id = v.plant_id
        LEFT JOIN users approver_user ON approver_user.id = ar.approved_by
        LEFT JOIN drivers approver ON approver.id = approver_user.driver_id
        {$whereClause}
        ORDER BY ar.created_at DESC
        LIMIT ? OFFSET ?
    ";

    $params[] = $limit;
    $params[] = $offset;
    $paramTypes .= 'ii';

    $stmt = $db->prepare($query);
    if ($params) {
        $stmt->bind_param($paramTypes, ...$params);
    }
    $stmt->execute();
    $result = $stmt->get_result();
    $requests = [];

    while ($row = $result->fetch_assoc()) {
        $requests[] = [
            'id' => (int)$row['id'],
            'driver_id' => (int)$row['driver_id'],
            'driver_name' => $row['driver_name'],
            'employee_id' => $row['employee_id'],
            'driver_phone' => $row['driver_phone'],
            'vehicle_number' => $row['vehicle_number'],
            'plant_name' => $row['plant_name'],
            'amount' => (float)$row['amount'],
            'formatted_amount' => '₹' . number_format($row['amount'], 2),
            'reason' => $row['reason'],
            'status' => $row['status'],
            'status_label' => ucfirst($row['status']),
            'created_at' => $row['created_at'],
            'formatted_date' => date('d M Y, h:i A', strtotime($row['created_at'])),
            'approved_by' => $row['approved_by'] ? (int)$row['approved_by'] : null,
            'approver_name' => $row['approver_name'] ?: $row['approver_username'],
            'approved_at' => $row['approved_at'],
            'formatted_approved_date' => $row['approved_at'] ? date('d M Y, h:i A', strtotime($row['approved_at'])) : null,
            'approval_comments' => $row['approval_comments']
        ];
    }
    $stmt->close();

    // Get status counts for filters
    $statusCounts = [];
    $statuses = ['pending', 'approved', 'rejected'];
    
    foreach ($statuses as $statusType) {
        $statusWhereConditions = [];
        $statusParams = [];
        $statusParamTypes = '';

        if ($role === 'supervisor') {
            $statusWhereConditions[] = "d.plant_id IN (
                SELECT sp.plant_id FROM supervisor_plants sp 
                WHERE sp.supervisor_id = ?
            )";
            $statusParams[] = $userId;
            $statusParamTypes .= 'i';
        }

        $statusWhereConditions[] = "ar.status = ?";
        $statusParams[] = $statusType;
        $statusParamTypes .= 's';

        $statusWhereClause = 'WHERE ' . implode(' AND ', $statusWhereConditions);

        $statusQuery = "
            SELECT COUNT(*) as count
            FROM advance_requests ar
            LEFT JOIN drivers d ON d.id = ar.driver_id
            LEFT JOIN vehicles v ON v.id = d.vehicle_id
            {$statusWhereClause}
        ";

        $stmt = $db->prepare($statusQuery);
        $stmt->bind_param($statusParamTypes, ...$statusParams);
        $stmt->execute();
        $result = $stmt->get_result();
        $statusCounts[$statusType] = (int)$result->fetch_assoc()['count'];
        $stmt->close();
    }

    $totalPages = ceil($totalCount / $limit);

    apiRespond(200, [
        'ok' => true,
        'data' => [
            'requests' => $requests,
            'pagination' => [
                'current_page' => $page,
                'total_pages' => $totalPages,
                'total_count' => $totalCount,
                'per_page' => $limit,
                'has_next' => $page < $totalPages,
                'has_prev' => $page > 1
            ],
            'status_counts' => [
                'pending' => $statusCounts['pending'],
                'approved' => $statusCounts['approved'],
                'rejected' => $statusCounts['rejected'],
                'total' => array_sum($statusCounts)
            ],
            'filters' => [
                'status' => $status,
                'role' => $role
            ]
        ]
    ]);

} catch (Exception $e) {
    error_log("Advance requests list error: " . $e->getMessage());
    apiRespond(500, ['ok' => false, 'error' => 'Internal server error']);
}
?>
