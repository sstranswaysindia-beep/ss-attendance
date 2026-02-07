<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

$ctx = safety_user_context();
$userId = $ctx['user_id'] ?: null;
$driverId = $ctx['driver_id'] ?: null;

if (!isset($conn) || !$conn instanceof mysqli) {
    apiRespond(500, ['status' => 'error', 'error' => 'Database connection not available']);
}

try {
    apiEnsurePost();
    $body = apiRequireJson();

    $moduleId = apiSanitizeInt($body['module_id'] ?? $body['moduleId'] ?? null);
    $position = apiSanitizeInt($body['position_seconds'] ?? $body['position'] ?? 0) ?? 0;
    $duration = apiSanitizeInt($body['duration_seconds'] ?? $body['duration'] ?? null);
    $completed = !empty($body['completed']);

    if (!$moduleId || $moduleId <= 0) {
        apiRespond(400, ['status' => 'error', 'error' => 'module_id is required']);
    }
    if (!$userId && !$driverId) {
        apiRespond(401, ['status' => 'error', 'error' => 'User context required']);
    }

    if (!safety_table_exists($conn, 'safety_training_modules') || !safety_table_exists($conn, 'safety_training_progress')) {
        apiRespond(400, ['status' => 'error', 'error' => 'Training tables not installed']);
    }

    $trainingYear = (new DateTimeImmutable('now'))->format('Y');
    $identityKey = ($userId ? ('u_' . $userId) : ('d_' . $driverId)) . '_' . $trainingYear;

    // auto-complete if near the end; never downgrade an already completed row
    $position = max(0, $position);
    $autoComplete = false;
    if ($duration !== null && $duration > 0) {
        $threshold = max(0, (int)floor($duration * 0.95));
        $autoComplete = $position >= $threshold;
        // clamp position to duration for cleaner progress
        $position = min($position, $duration);
    }
    if ($completed) {
        $autoComplete = true;
    }

    // upsert (year-scoped identity_key)
    $sql = "
        INSERT INTO safety_training_progress (user_id, driver_id, identity_key, module_id, position_seconds, completed)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            position_seconds = VALUES(position_seconds),
            completed = GREATEST(completed, VALUES(completed))
    ";
    $stmt = $conn->prepare($sql);
    $uid = $userId ?: null;
    $did = $driverId ?: null;
    $completedFlag = $autoComplete ? 1 : 0;
    $stmt->bind_param('issiii', $uid, $did, $identityKey, $moduleId, $position, $completedFlag);
    $stmt->execute();
    $stmt->close();

    if ($duration !== null && $duration > 0) {
        $durStmt = $conn->prepare('UPDATE safety_training_modules SET duration_seconds = ? WHERE id = ? AND (duration_seconds IS NULL OR duration_seconds = 0)');
        $durStmt->bind_param('ii', $duration, $moduleId);
        $durStmt->execute();
        $durStmt->close();
    }

    apiRespond(200, [
        'status' => 'ok',
        'module_id' => $moduleId,
        'position' => $position,
        'completed' => $completed,
    ]);
} catch (Throwable $e) {
    apiRespond(500, ['status' => 'error', 'error' => $e->getMessage()]);
}
