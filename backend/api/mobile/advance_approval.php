<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/common.php';

apiEnsurePost();

try {
    global $conn, $mysqli, $con;
    $db = $conn instanceof mysqli ? $conn : ($mysqli instanceof mysqli ? $mysqli : ($con instanceof mysqli ? $con : null));
    
    if (!$db) {
        throw new Exception('Database connection not available');
    }

    $data = $_POST;
    if (!$data || !isset($data['requestId'])) {
        $data = apiRequireJson();
    }

    $requestId = (int)($data['requestId'] ?? 0);
    $action = trim($data['action'] ?? ''); // 'approve' or 'reject'
    $comments = trim($data['comments'] ?? '');
    $adminId = trim($data['adminId'] ?? 'admin'); // Admin identifier

    if ($requestId <= 0) {
        apiRespond([
            'success' => false,
            'error' => 'Invalid request ID',
        ], 400);
    }

    if (!in_array($action, ['approve', 'reject'])) {
        apiRespond([
            'success' => false,
            'error' => 'Invalid action. Must be "approve" or "reject"',
        ], 400);
    }

    // Check if request exists and get current status
    $checkQuery = "SELECT id, status, driver_id, amount, purpose as reason FROM advance_requests WHERE id = ?";
    $stmt = $db->prepare($checkQuery);
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
    
    $request = $result->fetch_assoc();
    $stmt->close();

    // Check if request is already processed
    if ($request['status'] !== 'Pending') {
        apiRespond([
            'success' => false,
            'error' => 'Request has already been processed',
            'currentStatus' => $request['status'],
        ], 400);
    }

    // Update the request status
    $newStatus = $action === 'approve' ? 'Approved' : 'Rejected';
    $approvedAt = $action === 'approve' ? 'NOW()' : 'NULL';
    
    $updateQuery = "UPDATE advance_requests 
                    SET status = ?, 
                        remarks = ?, 
                        approval_at = $approvedAt
                    WHERE id = ?";
    
    $stmt = $db->prepare($updateQuery);
    $stmt->bind_param('ssi', $newStatus, $comments, $requestId);
    
    if (!$stmt->execute()) {
        $stmt->close();
        throw new Exception('Failed to update advance request');
    }
    
    $affectedRows = $stmt->affected_rows;
    $stmt->close();

    if ($affectedRows === 0) {
        throw new Exception('No rows were updated');
    }

    // Log the approval action
    $logQuery = "INSERT INTO advance_approval_logs 
                 (request_id, driver_id, action, admin_id, comments, created_at) 
                 VALUES (?, ?, ?, ?, ?, NOW())";
    
    $stmt = $db->prepare($logQuery);
    $stmt->bind_param('iisss', $requestId, $request['driver_id'], $action, $adminId, $comments);
    $stmt->execute(); // Don't fail if logging fails
    $stmt->close();

    // Get updated request details for response
    $detailsQuery = "SELECT 
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
                       p.plant_name
                     FROM advance_requests ar 
                     LEFT JOIN drivers d ON ar.driver_id = d.id 
                     LEFT JOIN users u ON d.user_id = u.id 
                     LEFT JOIN plants p ON d.plant_id = p.id
                     WHERE ar.id = ?";
    
    $stmt = $db->prepare($detailsQuery);
    $stmt->bind_param('i', $requestId);
    $stmt->execute();
    $result = $stmt->get_result();
    $updatedRequest = $result->fetch_assoc();
    $stmt->close();

    $responseData = [
        'id' => (int)$updatedRequest['id'],
        'driverId' => (int)$updatedRequest['driver_id'],
        'amount' => (float)$updatedRequest['amount'],
        'reason' => $updatedRequest['reason'],
        'status' => $updatedRequest['status'],
        'createdAt' => $updatedRequest['created_at'],
        'approvedAt' => $updatedRequest['approved_at'],
        'adminComments' => $updatedRequest['admin_comments'],
        'driver' => [
            'name' => $updatedRequest['driver_name'],
            'employeeId' => $updatedRequest['employee_id'],
            'username' => $updatedRequest['username'],
        ],
        'plant' => [
            'name' => $updatedRequest['plant_name'],
        ],
    ];

    apiRespond([
        'success' => true,
        'message' => "Request {$action}d successfully",
        'data' => $responseData,
    ]);

} catch (Exception $e) {
    error_log("Advance approval error: " . $e->getMessage());
    apiRespond([
        'success' => false,
        'error' => 'Failed to process advance request approval',
        'message' => $e->getMessage(),
    ], 500);
}
