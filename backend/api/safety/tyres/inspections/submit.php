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

    $overallNote = isset($payload['overall_note']) ? trim((string)$payload['overall_note']) : null;
    if ($overallNote !== null && $overallNote === '') {
        $overallNote = null;
    }

    $stmt = $conn->prepare(
        'SELECT id, vehicle_id, status
           FROM tyre_inspections
          WHERE id = ?
          LIMIT 1'
    );
    if (!$stmt) {
        apiRespond(500, ['ok' => false, 'error' => 'Failed to prepare inspection lookup']);
    }
    $stmt->bind_param('i', $inspectionId);
    $stmt->execute();
    $inspection = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$inspection) {
        apiRespond(404, ['ok' => false, 'error' => 'Inspection not found']);
    }

    $expectedCheckpoints = safety_expected_checkpoint_count();
    $tyreStmt = $conn->prepare(
        'SELECT tt.position_code,
                tt.status,
                tt.psi,
                (SELECT COUNT(*)
                   FROM tyre_inspection_answers tia
                  WHERE tia.tyre_row_id = tt.id) AS answer_count
           FROM tyre_inspection_tyres tt
          WHERE tt.inspection_id = ?
          ORDER BY tt.position_code ASC'
    );
    if (!$tyreStmt) {
        apiRespond(500, ['ok' => false, 'error' => 'Failed to prepare tyre lookup']);
    }
    $tyreStmt->bind_param('i', $inspectionId);
    $tyreStmt->execute();
    $tyresResult = $tyreStmt->get_result();

    $incompletePositions = [];
    while ($row = $tyresResult->fetch_assoc()) {
        $answerCount = (int)($row['answer_count'] ?? 0);
        if ($answerCount < $expectedCheckpoints) {
            $incompletePositions[] = $row['position_code'];
        }
    }
    $tyreStmt->close();

    if (!empty($incompletePositions)) {
        apiRespond(422, [
            'ok' => false,
            'error' => 'Please update all checkpoints',
            'positions' => $incompletePositions,
        ]);
    }

    $beganTransaction = $conn->begin_transaction();
    $now = (new DateTimeImmutable('now', new DateTimeZone('Asia/Kolkata')))->format('Y-m-d H:i:s');

    $updateStmt = $conn->prepare(
        'UPDATE tyre_inspections
            SET status = ?, submitted_at = ?, overall_note = ?, updated_at = CURRENT_TIMESTAMP
          WHERE id = ?'
    );
    if (!$updateStmt) {
        $conn->rollback();
        apiRespond(500, ['ok' => false, 'error' => 'Failed to prepare submission update']);
    }
    $status = 'submitted';
    $updateStmt->bind_param('sssi', $status, $now, $overallNote, $inspectionId);
    $updateStmt->execute();
    $updateStmt->close();

    if ($beganTransaction) {
        $conn->commit();
        $beganTransaction = false;
    }

    apiRespond(200, [
        'ok' => true,
        'status' => $status,
        'submitted_at' => $now,
    ]);
} catch (Throwable $e) {
    if (isset($conn) && $conn instanceof \mysqli && isset($beganTransaction) && $beganTransaction) {
        $conn->rollback();
    }
    error_log('[safety/tyres/submit] ' . $e->getMessage());
    apiRespond(500, ['ok' => false, 'error' => 'Unable to submit inspection']);
}
