<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

// Force absolute host for audio to avoid mixed/invalid origins on mobile
$BASE_AUDIO = 'https://sstranswaysindia.com';
$AUDIO_FALLBACK = 'https://sstranswaysindia.com/DriverDocs/audio/training/training1.mp3';

$ctx = safety_user_context();
$userId = $ctx['user_id'] ?: null;
$driverId = $ctx['driver_id'] ?: null;

if (!isset($conn) || !$conn instanceof mysqli) {
    apiRespond(500, ['status' => 'error', 'error' => 'Database connection not available']);
}

try {
    if (!safety_table_exists($conn, 'safety_training_modules')) {
        apiRespond(200, ['status' => 'ok', 'modules' => []]);
    }

    // Annual training: track progress per calendar year (identity_key includes year).
    $now = new DateTimeImmutable('now');
    $trainingYear = $now->format('Y');
    $yearStart = (new DateTimeImmutable($now->format('Y-01-01 00:00:00')))->format('Y-m-d H:i:s');
    $yearEnd = (new DateTimeImmutable(((int)$trainingYear + 1) . '-01-01 00:00:00'))->format('Y-m-d H:i:s');

    $modules = [];
    $sql = "
        SELECT id, code, title, description, transcript, audio_url, duration_seconds, sort_order
        FROM safety_training_modules
        WHERE is_active = 1
        ORDER BY sort_order ASC, id ASC
    ";
    $res = $conn->query($sql);
    while ($row = $res->fetch_assoc()) {
        $audioUrl = $row['audio_url'] ?? '';
        if ($audioUrl !== null && $audioUrl !== '') {
            if (!preg_match('#^https?://#i', $audioUrl)) {
                if ($audioUrl[0] !== '/') {
                    $audioUrl = '/' . $audioUrl;
                }
                $audioUrl = "{$BASE_AUDIO}{$audioUrl}";
            }
        } else {
            $audioUrl = $AUDIO_FALLBACK;
        }

        // If HTTPS fails for clients, provide both protocols
        $audioCandidates = [$audioUrl];
        if (str_starts_with($audioUrl, 'https://')) {
            $audioCandidates[] = str_replace('https://', 'http://', $audioUrl);
        } elseif (str_starts_with($audioUrl, 'http://')) {
            $audioCandidates[] = str_replace('http://', 'https://', $audioUrl);
        }

        $modules[] = [
            'id' => (int)$row['id'],
            'code' => $row['code'],
            'title' => $row['title'],
            'description' => $row['description'],
            'transcript' => $row['transcript'],
            'audioUrl' => $audioUrl,
            'audioCandidates' => $audioCandidates,
            'duration' => $row['duration_seconds'] !== null ? (int)$row['duration_seconds'] : null,
            'sortOrder' => (int)$row['sort_order'],
        ];
    }

    // Attach progress per module
    $progressByModule = [];
    if (!empty($modules) && ($userId || $driverId) && safety_table_exists($conn, 'safety_training_progress')) {
        $identityKey = ($userId ? ('u_' . $userId) : ('d_' . $driverId)) . '_' . $trainingYear;
        $ids = implode(',', array_fill(0, count($modules), '?'));
        $types = str_repeat('i', count($modules));
        $values = array_map(static fn($m) => $m['id'], $modules);
        $stmt = $conn->prepare("
            SELECT module_id, position_seconds, completed
            FROM safety_training_progress
            WHERE identity_key = ?
              AND created_at >= ?
              AND created_at < ?
              AND updated_at >= ?
              AND updated_at < ?
              AND module_id IN ({$ids})
        ");
        if ($stmt) {
            $bind = [$typesWithIdentity = 'sssss' . $types];
            $bind[] = &$identityKey;
            $bind[] = &$yearStart;
            $bind[] = &$yearEnd;
            $bind[] = &$yearStart;
            $bind[] = &$yearEnd;
            foreach ($values as $idx => $val) {
                $bind[] = &$values[$idx];
            }
            call_user_func_array([$stmt, 'bind_param'], $bind);
            $stmt->execute();
            $res = $stmt->get_result();
            while ($row = $res->fetch_assoc()) {
                $progressByModule[(int)$row['module_id']] = [
                    'position' => (int)$row['position_seconds'],
                    'completed' => (int)$row['completed'] === 1,
                ];
            }
            $stmt->close();
        }
    }

    $sorted = [];
    $locked = false;
    foreach ($modules as $index => $module) {
        $progress = $progressByModule[$module['id']] ?? ['position' => 0, 'completed' => false];
        $canPlay = !$locked;
        if (!$progress['completed']) {
            $locked = true; // next modules locked until this completes
        }
        $sorted[] = array_merge($module, [
            'progress' => $progress,
            'locked' => !$canPlay,
        ]);
    }

    $payload = ['status' => 'ok', 'modules' => $sorted];
    if (!empty($_GET['debug']) || !empty($_POST['debug'])) {
        $payload['debug'] = [
            'trainingYear' => $trainingYear,
            'identityKeyUsed' => ($userId ? ('u_' . $userId) : ('d_' . $driverId)) . '_' . $trainingYear,
            'yearStart' => $yearStart,
            'yearEnd' => $yearEnd,
            'modulesCount' => count($sorted),
            'progressRowsMatched' => count($progressByModule),
            'ctx' => [
                'userId' => $userId,
                'driverId' => $driverId,
                'role' => $ctx['role'] ?? '',
            ],
        ];
    }

    apiRespond(200, $payload);
} catch (Throwable $e) {
    apiRespond(500, ['status' => 'error', 'error' => $e->getMessage()]);
}
