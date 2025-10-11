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

if (!function_exists('td_has_column')) {
    function td_has_column(string $table, string $column): bool
    {
        global $conn, $mysqli, $con;
        $db = $conn instanceof mysqli ? $conn
            : ($mysqli instanceof mysqli ? $mysqli
            : ($con instanceof mysqli ? $con : null));
        
        if (!$db) return false;
        
        $table = $db->real_escape_string($table);
        $column = $db->real_escape_string($column);
        $sql = "SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '{$table}' AND COLUMN_NAME = '{$column}' LIMIT 1";
        $res = $db->query($sql);
        return $res && $res->num_rows > 0;
    }
}

$role = TD_MOBILE_ROLE;
$userId = TD_MOBILE_USER_ID;
$driverId = TD_MOBILE_DRIVER_ID;

// Only supervisors and admins can approve advances
if (!in_array($role, ['supervisor', 'admin'])) {
    apiRespond(403, ['ok' => false, 'error' => 'Access denied. Only supervisors and admins can approve advances.']);
}

/* -------- Body parsing -------- */
function read_body_array(): array {
    $ct = strtolower($_SERVER['CONTENT_TYPE'] ?? '');
    $raw = file_get_contents('php://input') ?: '';
    if (strpos($ct,'json') !== false) {
        $j = json_decode($raw,true);
        if (is_array($j)) return $j;
    }
    if (!empty($_POST)) return $_POST;
    $j = json_decode($raw,true); 
    return is_array($j) ? $j : [];
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

    /* -------- Only POST -------- */
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
        apiRespond(405, ['ok' => false, 'error' => 'Method not allowed']);
    }

    $in = read_body_array();

    /* -------- Inputs -------- */
    $requestId = isset($in['request_id']) ? (int)$in['request_id'] : 0;
    $action = isset($in['action']) ? trim((string)$in['action']) : '';
    $comments = isset($in['comments']) ? trim((string)$in['comments']) : '';

    // Validate inputs
    if ($requestId <= 0) {
        apiRespond(400, ['ok' => false, 'error' => 'Invalid request ID']);
    }

    if (!in_array($action, ['approve', 'reject'])) {
        apiRespond(400, ['ok' => false, 'error' => 'Invalid action. Must be "approve" or "reject"']);
    }

    // Check if advance request exists and get details
    $stmt = $db->prepare("
        SELECT 
            ar.*,
            d.name as driver_name,
            d.employee_id,
            d.phone
        FROM advance_requests ar
        LEFT JOIN drivers d ON d.id = ar.driver_id
        WHERE ar.id = ? AND ar.status = 'pending'
    ");
    $stmt->bind_param('i', $requestId);
    $stmt->execute();
    $result = $stmt->get_result();
    $request = $result->fetch_assoc();
    $stmt->close();

    if (!$request) {
        apiRespond(404, ['ok' => false, 'error' => 'Advance request not found or already processed']);
    }

    // Check if the approver has permission for this driver's plant
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
            apiRespond(403, ['ok' => false, 'error' => 'You do not have permission to approve advances for this driver']);
        }
    }

    // Update the advance request
    $newStatus = $action === 'approve' ? 'approved' : 'rejected';
    $approvedBy = $userId;
    $approvedAt = date('Y-m-d H:i:s');

    $stmt = $db->prepare("
        UPDATE advance_requests 
        SET 
            status = ?,
            approved_by = ?,
            approved_at = ?,
            approval_comments = ?
        WHERE id = ?
    ");
    $stmt->bind_param('sissi', $newStatus, $approvedBy, $approvedAt, $comments, $requestId);
    $stmt->execute();
    $affectedRows = $stmt->affected_rows;
    $stmt->close();

    if ($affectedRows === 0) {
        apiRespond(500, ['ok' => false, 'error' => 'Failed to update advance request']);
    }

    // Log the approval action
    $logMessage = sprintf(
        "Advance request %s by %s (ID: %d) for driver %s (ID: %d). Amount: ₹%s. Comments: %s",
        $newStatus,
        $role === 'admin' ? 'Admin' : 'Supervisor',
        $userId,
        $request['driver_name'],
        $request['driver_id'],
        number_format($request['amount'], 2),
        $comments ?: 'No comments'
    );

    // Insert into activity log if table exists
    if (td_table_exists($db, 'activity_logs')) {
        $stmt = $db->prepare("
            INSERT INTO activity_logs (user_id, action, details, created_at)
            VALUES (?, 'advance_approval', ?, NOW())
        ");
        $stmt->bind_param('is', $userId, $logMessage);
        $stmt->execute();
        $stmt->close();
    }

    // Get approver name for response
    $approverName = '';
    if ($role === 'admin') {
        $stmt = $db->prepare("SELECT username FROM users WHERE id = ?");
        $stmt->bind_param('i', $userId);
        $stmt->execute();
        $result = $stmt->get_result();
        $user = $result->fetch_assoc();
        $approverName = $user['username'] ?? 'Admin';
        $stmt->close();
    } else {
        // For supervisor, get from drivers table or users table
        $stmt = $db->prepare("
            SELECT COALESCE(d.name, u.username) as name
            FROM users u
            LEFT JOIN drivers d ON d.id = u.driver_id
            WHERE u.id = ?
        ");
        $stmt->bind_param('i', $userId);
        $stmt->execute();
        $result = $stmt->get_result();
        $user = $result->fetch_assoc();
        $approverName = $user['name'] ?? 'Supervisor';
        $stmt->close();
    }

    // Return success response
    apiRespond(200, [
        'ok' => true,
        'message' => "Advance request {$newStatus} successfully",
        'data' => [
            'request_id' => $requestId,
            'status' => $newStatus,
            'approved_by' => $approverName,
            'approved_at' => $approvedAt,
            'comments' => $comments,
            'driver_name' => $request['driver_name'],
            'amount' => number_format($request['amount'], 2),
            'request_date' => $request['created_at']
        ]
    ]);

} catch (Exception $e) {
    error_log("Advance approval error: " . $e->getMessage());
    apiRespond(500, ['ok' => false, 'error' => 'Internal server error']);
}
?>
