<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/common.php';

apiEnsurePost();

$data = apiRequireJson();

$driverId   = apiSanitizeInt($data['driverId'] ?? null);
$plantId    = apiSanitizeInt($data['plantId'] ?? null);
$vehicleId  = apiSanitizeInt($data['vehicleId'] ?? null);
$updatedBy  = apiSanitizeInt($data['userId'] ?? null);

if (!$driverId || !$plantId || !$vehicleId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId, plantId, and vehicleId are required integers.']);
}

$driverStmt = $conn->prepare('SELECT id FROM drivers WHERE id = ? LIMIT 1');
$driverStmt->bind_param('i', $driverId);
$driverStmt->execute();
if (!$driverStmt->get_result()->fetch_assoc()) {
    $driverStmt->close();
    apiRespond(404, ['status' => 'error', 'error' => 'Driver not found.']);
}
$driverStmt->close();

$conn->begin_transaction();

try {
    $existingStmt = $conn->prepare('SELECT id FROM assignments WHERE driver_id = ? LIMIT 1');
    $existingStmt->bind_param('i', $driverId);
    $existingStmt->execute();
    $row = $existingStmt->get_result()->fetch_assoc();
    $existingStmt->close();

    if ($row) {
        $assignmentId = (int)$row['id'];
        $updateStmt = $conn->prepare(
            'UPDATE assignments SET plant_id = ?, vehicle_id = ?, assigned_date = CURDATE() WHERE id = ?'
        );
        $updateStmt->bind_param('iii', $plantId, $vehicleId, $assignmentId);
        $updateStmt->execute();
        $updateStmt->close();
    } else {
        $insertStmt = $conn->prepare(
            'INSERT INTO assignments (driver_id, plant_id, vehicle_id, assigned_date) VALUES (?, ?, ?, CURDATE())'
        );
        $insertStmt->bind_param('iii', $driverId, $plantId, $vehicleId);
        $insertStmt->execute();
        $assignmentId = $insertStmt->insert_id;
        $insertStmt->close();
    }

    $savedPhotoRelPath = apiSaveUploadedFile('photo', $driverId, 'vehicle_' . $vehicleId);

    $conn->commit();

    apiRespond(200, [
        'status' => 'ok',
        'assignmentId' => $assignmentId,
        'driverId' => $driverId,
        'plantId' => $plantId,
        'vehicleId' => $vehicleId,
        'updatedBy' => $updatedBy,
        'photo' => $savedPhotoRelPath,
    ]);
} catch (Throwable $error) {
    $conn->rollback();
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
