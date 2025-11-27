<?php
declare(strict_types=1);

require dirname(__DIR__) . '/bootstrap.php';

try {
    if (!isset($conn) || !$conn instanceof mysqli) {
        apiRespond(500, ['ok' => false, 'error' => 'Database connection not available']);
    }

    $ctx = rewards_user_context();
    $role = rewards_normalize_role($ctx['role']);
    $userId = apiSanitizeInt($ctx['user_id']);

    if ($role === null || !$userId) {
        apiRespond(403, ['ok' => false, 'error' => 'Unauthorized']);
    }

    $limits = rewards_fetch_limits($conn);
    $usage = rewards_usage_today($conn, $userId, $role, $limits['cooldown_minutes']);
    $balance = rewards_fetch_balance($conn, $userId);
    $history = rewards_recent_ledger($conn, $userId, $role, 20);

    apiRespond(200, [
        'ok' => true,
        'balance' => $balance,
        'limits' => [
            'reward_amount' => $limits['reward_amount'],
            'daily_view_limit' => $limits['daily_view_limit'],
            'rewarded_today' => $usage['rewarded_today'],
            'cooldown_minutes' => $limits['cooldown_minutes'],
            'next_available_at' => $usage['next_available_at'],
        ],
        'history' => array_map(
            static function (array $entry): array {
                return [
                    'amount' => (float)$entry['amount'],
                    'type' => $entry['type'],
                    'reference_id' => $entry['reference_id'],
                    'note' => $entry['note'],
                    'created_at' => $entry['created_at'],
                ];
            },
            $history
        ),
    ]);
} catch (Throwable $e) {
    error_log('[rewards/watch/status] ' . $e->getMessage());
    apiRespond(500, ['ok' => false, 'error' => 'Unable to load status']);
}
