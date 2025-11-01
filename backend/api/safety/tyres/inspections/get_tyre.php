<?php
declare(strict_types=1);

require __DIR__ . '/../../bootstrap.php';

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

    $stmt = $conn->prepare(
        'SELECT ti.id              AS inspection_id,
                ti.vehicle_id      AS vehicle_id,
                ti.plant_id        AS plant_id,
                ti.driver_id       AS driver_id,
                ti.inspector_user_id AS inspector_user_id,
                tt.id              AS tyre_row_id,
                tt.psi             AS psi,
                tt.status          AS tyre_status,
                tt.photo_url       AS photo_url,
                tt.updated_at      AS updated_at,
                tia.checkpoint_no  AS checkpoint_no,
                tia.result         AS checkpoint_result,
                tia.remark         AS checkpoint_remark
           FROM tyre_inspection_tyres tt
           JOIN tyre_inspections ti
             ON ti.id = tt.inspection_id
           LEFT JOIN tyre_inspection_answers tia
             ON tia.tyre_row_id = tt.id
          WHERE ti.id = ?
            AND tt.position_code = ?
          ORDER BY tia.checkpoint_no ASC'
    );
    if (!$stmt) {
        apiRespond(500, ['ok' => false, 'error' => 'Unable to prepare tyre lookup']);
    }
    $stmt->bind_param('is', $inspectionId, $positionCode);
    $stmt->execute();
    $result = $stmt->get_result();

    if (!$result || $result->num_rows === 0) {
        $stmt->close();
        apiRespond(404, ['ok' => false, 'error' => 'Tyre position not found for inspection']);
    }

    $answers = [];
    $base = null;
    while ($row = $result->fetch_assoc()) {
        if ($base === null) {
            $base = $row;
        }
        if ($row['checkpoint_no'] !== null) {
            $answers[] = [
                'checkpoint_no' => (int)$row['checkpoint_no'],
                'result' => (string)$row['checkpoint_result'],
                'remark' => isset($row['checkpoint_remark']) && $row['checkpoint_remark'] !== ''
                    ? (string)$row['checkpoint_remark']
                    : null,
            ];
        }
    }
    $stmt->close();

    if ($base === null) {
        apiRespond(404, ['ok' => false, 'error' => 'Tyre position not found for inspection']);
    }

    $psi = $base['psi'];
    $response = [
        'ok' => true,
        'inspection_id' => (int)$base['inspection_id'],
        'position_code' => $positionCode,
        'psi' => $psi === null ? null : (float)$psi,
        'photo_url' => $base['photo_url'],
        'status' => $base['tyre_status'],
        'answers' => $answers,
        'updated_at' => $base['updated_at'],
    ];

    apiRespond(200, $response);
} catch (Throwable $e) {
    error_log('[safety/tyres/get_tyre] ' . $e->getMessage());
    apiRespond(500, ['ok' => false, 'error' => 'Unable to load tyre data']);
}
