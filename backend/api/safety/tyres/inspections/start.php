<?php
declare(strict_types=1);

require __DIR__ . '/../../bootstrap.php';

$beganTransaction = false;

try {
    if (!isset($conn) || !$conn instanceof \mysqli) {
        apiRespond(500, ['ok' => false, 'error' => 'Database connection not available']);
    }

    apiEnsurePost();

    $payload = apiRequireJson();
    $vehicleId = apiSanitizeInt($payload['vehicle_id'] ?? null);
    if (!$vehicleId) {
        apiRespond(422, ['ok' => false, 'error' => 'vehicle_id required']);
    }

    $tyreExpr = safety_vehicle_tyre_expression($conn);
    $vehicleStmt = $conn->prepare(
        "SELECT v.id, v.plant_id, {$tyreExpr} AS tyre_count
           FROM vehicles v
          WHERE v.id = ?
          LIMIT 1"
    );
    $vehicleStmt->bind_param('i', $vehicleId);
    $vehicleStmt->execute();
    $vehicle = $vehicleStmt->get_result()->fetch_assoc();
    $vehicleStmt->close();

    if (!$vehicle) {
        apiRespond(404, ['ok' => false, 'error' => 'Vehicle not found']);
    }

    $allowedPlants = safety_allowed_plants($conn, 'mine');
    $vehiclePlantId = (int)$vehicle['plant_id'];
    $driverId = apiSanitizeInt($_SESSION['driver_id'] ?? $_GET['driverId'] ?? $_GET['driver_id'] ?? null);
    $userId = apiSanitizeInt($_SESSION['user_id'] ?? $_GET['userId'] ?? $_GET['user_id'] ?? null);
    $role = strtolower(trim((string)($_SESSION['role'] ?? $_GET['role'] ?? '')));

    $authorised = in_array($vehiclePlantId, $allowedPlants, true);

    if (!$authorised && $driverId) {
        $checkStmt = $conn->prepare(
            'SELECT 1 FROM assignments WHERE driver_id = ? AND vehicle_id = ? LIMIT 1'
        );
        if ($checkStmt) {
            $checkStmt->bind_param('ii', $driverId, $vehicleId);
            $checkStmt->execute();
            $authorised = (bool)$checkStmt->get_result()->fetch_assoc();
            $checkStmt->close();
        }
    }

    if (!$authorised && $role === 'admin') {
        $authorised = true;
    }

    if (!$authorised) {
        apiRespond(403, ['ok' => false, 'error' => 'Not authorised for this vehicle']);
    }

    $assignmentId = null;

    if ($driverId) {
        $assignmentStmt = $conn->prepare(
            'SELECT id FROM assignments WHERE driver_id = ? AND vehicle_id = ? ORDER BY assigned_date DESC LIMIT 1'
        );
        if ($assignmentStmt) {
            $assignmentStmt->bind_param('ii', $driverId, $vehicleId);
            $assignmentStmt->execute();
            $assignmentRow = $assignmentStmt->get_result()->fetch_assoc();
            if ($assignmentRow) {
                $assignmentId = (int)$assignmentRow['id'];
            }
            $assignmentStmt->close();
        }
    }

    // Check for existing draft inspection for this vehicle
    $existingInspectionId = null;
    $existingPositions = [];
    $draftStmt = $conn->prepare(
        "SELECT id FROM tyre_inspections
          WHERE vehicle_id = ? AND status = 'draft'
          ORDER BY updated_at DESC LIMIT 1"
    );
    if ($draftStmt) {
        $draftStmt->bind_param('i', $vehicleId);
        $draftStmt->execute();
        $draftRes = $draftStmt->get_result();
        if ($row = $draftRes->fetch_assoc()) {
            $existingInspectionId = (int)$row['id'];
        }
        $draftStmt->close();
    }

    if ($existingInspectionId !== null) {
        $posStmt = $conn->prepare(
            'SELECT position_code FROM tyre_inspection_tyres WHERE inspection_id = ? ORDER BY id ASC'
        );
        if ($posStmt) {
            $posStmt->bind_param('i', $existingInspectionId);
            $posStmt->execute();
            $posRes = $posStmt->get_result();
            while ($posRow = $posRes->fetch_assoc()) {
                $existingPositions[] = (string)$posRow['position_code'];
            }
            $posStmt->close();
        }

        $hasStepney = in_array('S', $existingPositions, true);
        if (!$hasStepney) {
            $stepneyInsert = $conn->prepare(
                'INSERT INTO tyre_inspection_tyres (inspection_id, position_code) VALUES (?, ?)'
            );
            if ($stepneyInsert) {
                $stepneyCode = 'S';
                $stepneyInsert->bind_param('is', $existingInspectionId, $stepneyCode);
                $stepneyInsert->execute();
                $stepneyInsert->close();
                $existingPositions[] = 'S';
            }
        }

        if (!empty($existingPositions)) {
            apiRespond(200, [
                'ok' => true,
                'inspection_id' => $existingInspectionId,
                'positions' => $existingPositions,
            ]);
        }
        // if existing inspection found but positions missing, fall through to create new inspection
    }

    $tyreCount = (int)$vehicle['tyre_count'];
    $positions = safety_generate_positions($tyreCount);
    if (!in_array('S', $positions, true)) {
        $positions[] = 'S';
    }

    $conn->begin_transaction();
    $beganTransaction = true;

    $insertStmt = $conn->prepare(
        'INSERT INTO tyre_inspections (vehicle_id, plant_id, driver_id, inspector_user_id, assignment_id)
         VALUES (?, ?, ?, ?, ?)'
    );
    $driverIdParam = $driverId ?: null;
    $userIdParam = $userId ?: null;
    $assignmentIdParam = $assignmentId ?: null;
    $insertStmt->bind_param(
        'iiiii',
        $vehicleId,
        $vehicle['plant_id'],
        $driverIdParam,
        $userIdParam,
        $assignmentIdParam
    );
    $insertStmt->execute();
    $inspectionId = (int)$insertStmt->insert_id;
    $insertStmt->close();

    $tyreStmt = $conn->prepare(
        'INSERT INTO tyre_inspection_tyres (inspection_id, position_code) VALUES (?, ?)'
    );
    foreach ($positions as $code) {
        $tyreStmt->bind_param('is', $inspectionId, $code);
        $tyreStmt->execute();
    }
    $tyreStmt->close();

    $conn->commit();

    apiRespond(200, [
        'ok' => true,
        'inspection_id' => $inspectionId,
        'positions' => $positions,
    ]);
} catch (Throwable $e) {
    if (isset($conn) && $conn instanceof \mysqli && $beganTransaction) {
        $conn->rollback();
    }
    error_log('[safety/tyres/start] ' . $e->getMessage());
    apiRespond(500, ['ok' => false, 'error' => 'Unable to start inspection']);
}
