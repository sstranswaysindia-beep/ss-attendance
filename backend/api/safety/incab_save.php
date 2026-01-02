<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

apiEnsurePost();

$data = apiRequireJson();

$driverId = apiSanitizeInt($data['driver_id'] ?? null);
$vehicleId = apiSanitizeInt($data['vehicle_id'] ?? null);
$plantId = apiSanitizeInt($data['plant_id'] ?? null);
$assessorUserId = apiSanitizeInt($data['assessor_user_id'] ?? null);
$transporterName = trim((string)($data['transporter_name'] ?? ''));
$weather = trim((string)($data['weather'] ?? ''));
$locationText = trim((string)($data['location_text'] ?? ''));
$startTimeRaw = trim((string)($data['start_time'] ?? ''));
$endTimeRaw = trim((string)($data['end_time'] ?? ''));
$assessmentDateRaw = trim((string)($data['assessment_date'] ?? ''));
$overallNotes = trim((string)($data['overall_notes'] ?? ''));
$items = is_array($data['items'] ?? null) ? $data['items'] : [];

if (!$driverId || !$vehicleId || $assessmentDateRaw === '') {
    apiRespond(422, ['status' => 'error', 'error' => 'driver_id, vehicle_id, assessment_date are required']);
}

$assessmentDate = date_create($assessmentDateRaw) ? date('Y-m-d', strtotime($assessmentDateRaw)) : null;
if ($assessmentDate === null) {
    apiRespond(422, ['status' => 'error', 'error' => 'Invalid assessment_date']);
}

$startTime = null;
if ($startTimeRaw !== '') {
    $ts = strtotime($startTimeRaw);
    if ($ts !== false) {
        $startTime = date('Y-m-d H:i:s', $ts);
    }
}
$endTime = null;
if ($endTimeRaw !== '') {
    $te = strtotime($endTimeRaw);
    if ($te !== false) {
        $endTime = date('Y-m-d H:i:s', $te);
    }
}

$allowedResults = ['positive','needs_improvement','not_observed','yes','no'];
$cleanItems = [];
foreach ($items as $item) {
    if (!is_array($item)) {
        continue;
    }
    $code = trim((string)($item['item_code'] ?? ''));
    $section = trim((string)($item['section_key'] ?? ''));
    $result = trim((string)($item['result'] ?? ''));
    $text = trim((string)($item['question_text'] ?? ''));
    if ($code === '' || $section === '' || !in_array($result, $allowedResults, true)) {
        continue;
    }
    $cleanItems[] = [
        'item_code' => $code,
        'section_key' => $section,
        'question_text' => $text === '' ? $code : $text,
        'result' => $result,
    ];
}

if (empty($cleanItems)) {
    apiRespond(422, ['status' => 'error', 'error' => 'No valid assessment items supplied']);
}

try {
    $conn->begin_transaction();

    $stmt = $conn->prepare("
        INSERT INTO in_cab_assessments
            (driver_id, vehicle_id, plant_id, assessor_user_id, transporter_name, weather, location_text, start_time, end_time, assessment_date, overall_notes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ");
    $stmt->bind_param(
        'iiiisssssss',
        $driverId,
        $vehicleId,
        $plantId,
        $assessorUserId,
        $transporterName,
        $weather,
        $locationText,
        $startTime,
        $endTime,
        $assessmentDate,
        $overallNotes
    );
    $stmt->execute();
    $assessmentId = $stmt->insert_id;
    $stmt->close();

    $itemStmt = $conn->prepare("
        INSERT INTO in_cab_assessment_items
            (assessment_id, section_key, item_code, question_text, result)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE result = VALUES(result), question_text = VALUES(question_text)
    ");
    foreach ($cleanItems as $item) {
        $itemStmt->bind_param(
            'issss',
            $assessmentId,
            $item['section_key'],
            $item['item_code'],
            $item['question_text'],
            $item['result']
        );
        $itemStmt->execute();
    }
    $itemStmt->close();

    $conn->commit();

    apiRespond(200, [
        'status' => 'ok',
        'assessment_id' => (int)$assessmentId,
    ]);
} catch (Throwable $e) {
    $conn->rollback();
    error_log('[incab_save] ' . $e->getMessage());
    apiRespond(500, ['status' => 'error', 'error' => 'Failed to save assessment']);
}
