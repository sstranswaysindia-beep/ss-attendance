<?php
declare(strict_types=1);

require __DIR__ . '/../../bootstrap.php';

$beganTransaction = false;

try {
    apiEnsurePost();

    if (!isset($conn) || !$conn instanceof \mysqli) {
        apiRespond(500, ['ok' => false, 'error' => 'Database connection not available']);
    }

    $payload = apiRequireJson();

    $inspectionId = apiSanitizeInt($payload['inspection_id'] ?? null);
    if (!$inspectionId) {
        apiRespond(422, ['ok' => false, 'error' => 'inspection_id required']);
    }

    $positionCode = strtoupper(trim((string)($payload['position_code'] ?? '')));
    if ($positionCode === '') {
        apiRespond(422, ['ok' => false, 'error' => 'position_code required']);
    }

    $psi = apiSanitizeFloat($payload['psi'] ?? null);
    if ($psi === null) {
        apiRespond(422, ['ok' => false, 'error' => 'psi required']);
    }

    $answersPayload = $payload['answers'] ?? null;
    if (!is_array($answersPayload) || empty($answersPayload)) {
        apiRespond(422, ['ok' => false, 'error' => 'answers required']);
    }

    $photoBase64 = null;
    if (!empty($payload['photo_base64']) && is_string($payload['photo_base64'])) {
        $photoBase64 = $payload['photo_base64'];
    }

    $expectedCheckpoints = safety_expected_checkpoint_count();
    $answers = [];
    $checkpointSeen = [];
    foreach ($answersPayload as $entry) {
        if (!is_array($entry)) {
            continue;
        }
        $checkpoint = apiSanitizeInt($entry['checkpoint_no'] ?? $entry['checkpoint'] ?? null);
        $resultRaw = strtolower(trim((string)($entry['result'] ?? '')));
        if (
            !$checkpoint
            || !in_array($resultRaw, ['acceptable', 'caution', 'non_acceptable'], true)
        ) {
            continue;
        }
        $remark = isset($entry['remark']) ? trim((string)$entry['remark']) : null;
        $checkpointSeen[$checkpoint] = true;
        $answers[] = [
            'checkpoint_no' => $checkpoint,
            'result' => $resultRaw,
            'remark' => $remark === '' ? null : $remark,
        ];
    }

    if (count($answers) < $expectedCheckpoints) {
        apiRespond(422, ['ok' => false, 'error' => 'Please update all checkpoints']);
    }

    $selectStmt = $conn->prepare(
        'SELECT ti.id, ti.vehicle_id, ti.status, tt.id AS tyre_row_id
           FROM tyre_inspections ti
           JOIN tyre_inspection_tyres tt
             ON tt.inspection_id = ti.id
            AND tt.position_code = ?
          WHERE ti.id = ?
          LIMIT 1'
    );
    if (!$selectStmt) {
        apiRespond(500, ['ok' => false, 'error' => 'Failed to prepare inspection query']);
    }
    $selectStmt->bind_param('si', $positionCode, $inspectionId);
    $selectStmt->execute();
    $inspection = $selectStmt->get_result()->fetch_assoc();
    $selectStmt->close();

    if (!$inspection) {
        apiRespond(404, ['ok' => false, 'error' => 'Inspection or tyre position not found']);
    }

    $vehicleId = (int)$inspection['vehicle_id'];
    $tyreRowId = (int)$inspection['tyre_row_id'];

    $beganTransaction = $conn->begin_transaction();

    $deleteStmt = $conn->prepare('DELETE FROM tyre_inspection_answers WHERE tyre_row_id = ?');
    if ($deleteStmt) {
        $deleteStmt->bind_param('i', $tyreRowId);
        $deleteStmt->execute();
        $deleteStmt->close();
    }

    $insertStmt = $conn->prepare(
        'INSERT INTO tyre_inspection_answers (tyre_row_id, checkpoint_no, result, remark)
         VALUES (?, ?, ?, ?)'
    );
    if (!$insertStmt) {
        $conn->rollback();
        apiRespond(500, ['ok' => false, 'error' => 'Failed to prepare answer insert']);
    }

    $tyreRowIdParam = $tyreRowId;
    $checkpointParam = 0;
    $resultParam = '';
    $remarkParam = null;
    $insertStmt->bind_param('iiss', $tyreRowIdParam, $checkpointParam, $resultParam, $remarkParam);

    $status = 'ok';
    foreach ($answers as $answer) {
        $checkpointParam = $answer['checkpoint_no'];
        $resultParam = $answer['result'];
        $remarkParam = $answer['remark'];
        if ($resultParam === 'non_acceptable') {
            $status = 'issue';
        } elseif ($resultParam === 'caution' && $status !== 'issue') {
            $status = 'caution';
        }
        $insertStmt->execute();
    }
    $insertStmt->close();

    $photoUrl = null;
    if ($photoBase64 !== null) {
        try {
            $paths = safety_store_tyre_photo($vehicleId, $positionCode, $photoBase64);
            $photoUrl = $paths['relative'];
        } catch (Throwable $e) {
            $conn->rollback();
            apiRespond(500, ['ok' => false, 'error' => 'Failed to store tyre photo']);
        }
    }

    if ($photoUrl !== null) {
        $updateStmt = $conn->prepare(
            'UPDATE tyre_inspection_tyres
                SET psi = ?, status = ?, photo_url = ?, updated_at = CURRENT_TIMESTAMP
              WHERE id = ?'
        );
    } else {
        $updateStmt = $conn->prepare(
            'UPDATE tyre_inspection_tyres
                SET psi = ?, status = ?, updated_at = CURRENT_TIMESTAMP
              WHERE id = ?'
        );
    }
    if (!$updateStmt) {
        $conn->rollback();
        apiRespond(500, ['ok' => false, 'error' => 'Failed to prepare tyre update']);
    }
    $psiValueParam = round($psi, 1);
    if ($photoUrl !== null) {
        $updateStmt->bind_param('dssi', $psiValueParam, $status, $photoUrl, $tyreRowId);
    } else {
        $updateStmt->bind_param('dsi', $psiValueParam, $status, $tyreRowId);
    }
    $updateStmt->execute();
    $updateStmt->close();

    $touchStmt = $conn->prepare(
        'UPDATE tyre_inspections SET updated_at = CURRENT_TIMESTAMP WHERE id = ?'
    );
    if ($touchStmt) {
        $touchStmt->bind_param('i', $inspectionId);
        $touchStmt->execute();
        $touchStmt->close();
    }

    if ($beganTransaction) {
        $conn->commit();
        $beganTransaction = false;
    }

    $psiRange = safety_load_psi_range($conn);
    $warnings = [];
    if ($psiValueParam < $psiRange['min'] || $psiValueParam > $psiRange['max']) {
        $warnings[] = sprintf(
            'PSI outside recommended range (%.0f–%.0f PSI)',
            $psiRange['min'],
            $psiRange['max']
        );
    }

    apiRespond(200, [
        'ok' => true,
        'photo_url' => $photoUrl,
        'warnings' => $warnings,
        'answers_saved' => count($answers),
        'psi_saved' => $psiValueParam,
        'tyre_row_id' => $tyreRowId,
        'tyre_status' => $status,
    ]);
} catch (Throwable $e) {
    if (isset($conn) && $conn instanceof \mysqli && isset($beganTransaction) && $beganTransaction) {
        $conn->rollback();
    }
    error_log('[safety/tyres/save] ' . $e->getMessage());
    apiRespond(500, ['ok' => false, 'error' => 'Unable to save tyre data']);
}
