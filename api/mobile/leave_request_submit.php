<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require __DIR__ . '/common.php';

apiEnsurePost();

$data = apiRequireJson();

$driverId = apiSanitizeInt($data['driverId'] ?? null);
$requestedById = apiSanitizeInt($data['requestedById'] ?? null);
$leaveType = trim((string)($data['leaveType'] ?? ''));
$startDateRaw = trim((string)($data['startDate'] ?? ''));
$endDateRaw = trim((string)($data['endDate'] ?? ''));
$duration = trim((string)($data['duration'] ?? 'Full Day'));
$halfDaySession = trim((string)($data['halfDaySession'] ?? ''));
$reason = trim((string)($data['reason'] ?? ''));
$status = trim((string)($data['status'] ?? 'Pending'));

$allowedTypes = [
    'Casual Leave',
    'Sick Leave',
    'Earned / Privilege Leave',
    'Half Day Leave',
    'Compensatory Off',
    'Other',
];
$allowedDurations = ['Full Day', 'Half Day'];
$allowedHalfDaySessions = ['First Half', 'Second Half'];
$allowedStatuses = ['Draft', 'Pending'];

if (!$driverId || !$requestedById) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId and requestedById are required']);
}

if (!in_array($leaveType, $allowedTypes, true)) {
    apiRespond(400, ['status' => 'error', 'error' => 'Invalid leave type']);
}

if (!in_array($duration, $allowedDurations, true)) {
    apiRespond(400, ['status' => 'error', 'error' => 'Invalid leave duration']);
}

if (!in_array($status, $allowedStatuses, true)) {
    $status = 'Pending';
}

if ($status !== 'Draft' && $reason === '') {
    apiRespond(400, ['status' => 'error', 'error' => 'reason is required']);
}

try {
    $startDate = new DateTime($startDateRaw);
    $endDate = new DateTime($endDateRaw);
} catch (Throwable $e) {
    apiRespond(400, ['status' => 'error', 'error' => 'Invalid date provided']);
}

if ($endDate < $startDate) {
    apiRespond(400, ['status' => 'error', 'error' => 'End date must be after start date']);
}

if ($duration === 'Half Day') {
    if ($startDate->format('Y-m-d') !== $endDate->format('Y-m-d')) {
        apiRespond(400, ['status' => 'error', 'error' => 'Half day must be a single date']);
    }
    if (!in_array($halfDaySession, $allowedHalfDaySessions, true)) {
        apiRespond(400, ['status' => 'error', 'error' => 'Select half day session']);
    }
} else {
    $halfDaySession = '';
}

$totalDays = $duration === 'Half Day'
    ? 0.5
    : ($endDate->diff($startDate)->days + 1);

$driverStmt = $conn->prepare('SELECT id FROM drivers WHERE id = ? LIMIT 1');
if ($driverStmt) {
    $driverStmt->bind_param('i', $driverId);
    $driverStmt->execute();
    $driverRow = $driverStmt->get_result()->fetch_assoc();
    $driverStmt->close();
    if (!$driverRow) {
        apiRespond(404, ['status' => 'error', 'error' => 'Driver not found']);
    }
}

$requestedByStmt = $conn->prepare('SELECT id FROM users WHERE id = ? LIMIT 1');
if ($requestedByStmt) {
    $requestedByStmt->bind_param('i', $requestedById);
    $requestedByStmt->execute();
    $requestedByRow = $requestedByStmt->get_result()->fetch_assoc();
    $requestedByStmt->close();
    if (!$requestedByRow) {
        apiRespond(404, ['status' => 'error', 'error' => 'Requested by user not found']);
    }
}

try {
    $insertStmt = $conn->prepare(
        'INSERT INTO leave_requests (
             driver_id,
             requested_by_id,
             leave_type,
             leave_start_date,
             leave_end_date,
             total_days,
             leave_duration,
             half_day_session,
             reason,
             status
         ) VALUES (?, ?, ?, ?, ?, ?, ?, NULLIF(?, ""), ?, ?)'
    );
    $startDateStr = $startDate->format('Y-m-d');
    $endDateStr = $endDate->format('Y-m-d');
    $insertStmt->bind_param(
        'iisssdssss',
        $driverId,
        $requestedById,
        $leaveType,
        $startDateStr,
        $endDateStr,
        $totalDays,
        $duration,
        $halfDaySession,
        $reason,
        $status
    );
    $insertStmt->execute();
    $leaveId = (int) $insertStmt->insert_id;
    $insertStmt->close();

    if ($status === 'Pending' && $leaveId > 0) {
        $sharedKey = getSettingValue($conn, 'api.shared_key');
        if ($sharedKey) {
            $scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
            $host = $_SERVER['HTTP_HOST'] ?? 'sstranswaysindia.com';
            $notifyUrls = [
                $scheme . '://' . $host . '/backend/api/notify_leave_request.php',
                $scheme . '://' . $host . '/api/notify_leave_request.php',
            ];
            $payload = json_encode([
                'leave_id' => $leaveId,
                'source' => 'driver',
            ]);
            foreach ($notifyUrls as $notifyUrl) {
                $opts = [
                    'http' => [
                        'method' => 'POST',
                        'header' => "Content-Type: application/json\r\nX-API-KEY: {$sharedKey}\r\n",
                        'content' => $payload,
                        'timeout' => 6,
                    ],
                ];
                @file_get_contents($notifyUrl, false, stream_context_create($opts));
            }
        }
    }

    apiRespond(200, [
        'status' => 'ok',
        'leaveRequestId' => $leaveId,
        'state' => $status,
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
