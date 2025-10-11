<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

$role = TD_MOBILE_ROLE;
$userId = TD_MOBILE_USER_ID;
$driverId = TD_MOBILE_DRIVER_ID;

// Only supervisors and admins can view advance request details
if (!in_array($role, ['supervisor', 'admin'])) {
    apiRespond(403, ['ok' => false, 'error' => 'Access denied. Only supervisors and admins can view advance request details.']);
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

    // Get request ID from query parameter
    $requestId = isset($_GET['id']) ? (int)$_GET['id'] : 0;

    if ($requestId <= 0) {
        apiRespond(400, ['ok' => false, 'error' => 'Invalid request ID']);
    }

    // Get advance request details
    $query = "
        SELECT 
            ar.*,
            d.name as driver_name,
            d.employee_id,
            d.phone as driver_phone,
            d.aadhaar,
            d.joining_date,
            d.salary,
            v.vehicle_number,
            p.plant_name,
            p.address as plant_address,
            p.contact_number as plant_contact,
            approver_user.username as approver_username,
            approver_driver.name as approver_name
        FROM advance_requests ar
        LEFT JOIN drivers d ON d.id = ar.driver_id
        LEFT JOIN vehicles v ON v.id = d.vehicle_id
        LEFT JOIN plants p ON p.id = v.plant_id
        LEFT JOIN users approver_user ON approver_user.id = ar.approved_by
        LEFT JOIN drivers approver_driver ON approver_driver.id = approver_user.driver_id
        WHERE ar.id = ?
    ";

    $stmt = $db->prepare($query);
    $stmt->bind_param('i', $requestId);
    $stmt->execute();
    $result = $stmt->get_result();
    $request = $result->fetch_assoc();
    $stmt->close();

    if (!$request) {
        apiRespond(404, ['ok' => false, 'error' => 'Advance request not found']);
    }

    // Check if the user has permission to view this request
    if ($role === 'supervisor') {
        // For supervisors, check if they supervise the driver's plant
        $stmt = $db->prepare("
            SELECT 1 FROM supervisor_plants sp
            WHERE sp.supervisor_id = ? AND sp.plant_id = (
                SELECT v.plant_id FROM drivers d
                LEFT JOIN vehicles v ON v.id = d.vehicle_id
                WHERE d.id = ?
            )
        ");
        $stmt->bind_param('ii', $userId, $request['driver_id']);
        $stmt->execute();
        $result = $stmt->get_result();
        $hasPermission = $result->num_rows > 0;
        $stmt->close();

        if (!$hasPermission) {
            apiRespond(403, ['ok' => false, 'error' => 'You do not have permission to view this advance request']);
        }
    }

    // Get driver's recent advance history
    $stmt = $db->prepare("
        SELECT 
            ar.id,
            ar.amount,
            ar.reason,
            ar.status,
            ar.created_at,
            ar.approved_at
        FROM advance_requests ar
        WHERE ar.driver_id = ? AND ar.id != ?
        ORDER BY ar.created_at DESC
        LIMIT 5
    ");
    $stmt->bind_param('ii', $request['driver_id'], $requestId);
    $stmt->execute();
    $result = $stmt->get_result();
    $advanceHistory = [];

    while ($row = $result->fetch_assoc()) {
        $advanceHistory[] = [
            'id' => (int)$row['id'],
            'amount' => (float)$row['amount'],
            'formatted_amount' => '₹' . number_format($row['amount'], 2),
            'reason' => $row['reason'],
            'status' => $row['status'],
            'status_label' => ucfirst($row['status']),
            'created_at' => $row['created_at'],
            'formatted_date' => date('d M Y', strtotime($row['created_at'])),
            'approved_at' => $row['approved_at'],
            'formatted_approved_date' => $row['approved_at'] ? date('d M Y', strtotime($row['approved_at'])) : null
        ];
    }
    $stmt->close();

    // Calculate driver's total advance amount (approved only)
    $stmt = $db->prepare("
        SELECT 
            COUNT(*) as total_requests,
            COALESCE(SUM(amount), 0) as total_amount
        FROM advance_requests 
        WHERE driver_id = ? AND status = 'approved'
    ");
    $stmt->bind_param('i', $request['driver_id']);
    $stmt->execute();
    $result = $stmt->get_result();
    $advanceStats = $result->fetch_assoc();
    $stmt->close();

    // Format the response
    $response = [
        'ok' => true,
        'data' => [
            'request' => [
                'id' => (int)$request['id'],
                'driver_id' => (int)$request['driver_id'],
                'amount' => (float)$request['amount'],
                'formatted_amount' => '₹' . number_format($request['amount'], 2),
                'reason' => $request['reason'],
                'status' => $request['status'],
                'status_label' => ucfirst($request['status']),
                'created_at' => $request['created_at'],
                'formatted_date' => date('d M Y, h:i A', strtotime($request['created_at'])),
                'approved_by' => $request['approved_by'] ? (int)$request['approved_by'] : null,
                'approver_name' => $request['approver_name'] ?: $request['approver_username'],
                'approved_at' => $request['approved_at'],
                'formatted_approved_date' => $request['approved_at'] ? date('d M Y, h:i A', strtotime($request['approved_at'])) : null,
                'approval_comments' => $request['approval_comments']
            ],
            'driver' => [
                'id' => (int)$request['driver_id'],
                'name' => $request['driver_name'],
                'employee_id' => $request['employee_id'],
                'phone' => $request['driver_phone'],
                'aadhaar' => $request['aadhaar'],
                'joining_date' => $request['joining_date'],
                'formatted_joining_date' => $request['joining_date'] ? date('d M Y', strtotime($request['joining_date'])) : null,
                'salary' => $request['salary'] ? (float)$request['salary'] : null,
                'formatted_salary' => $request['salary'] ? '₹' . number_format($request['salary'], 2) : null,
                'vehicle_number' => $request['vehicle_number'],
                'plant_name' => $request['plant_name'],
                'plant_address' => $request['plant_address'],
                'plant_contact' => $request['plant_contact']
            ],
            'advance_history' => $advanceHistory,
            'advance_stats' => [
                'total_requests' => (int)$advanceStats['total_requests'],
                'total_amount' => (float)$advanceStats['total_amount'],
                'formatted_total_amount' => '₹' . number_format($advanceStats['total_amount'], 2)
            ]
        ]
    ];

    apiRespond(200, $response);

} catch (Exception $e) {
    error_log("Advance request details error: " . $e->getMessage());
    apiRespond(500, ['ok' => false, 'error' => 'Internal server error']);
}
?>
