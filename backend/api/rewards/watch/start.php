<?php
declare(strict_types=1);

require __DIR__ . '/../../bootstrap.php';

try {
    apiEnsurePost();

    if (!isset($conn) || !$conn instanceof mysqli) {
        apiRespond(500, ['ok' => false, 'error' => 'Database connection not available']);
    }

    $payload = apiRequireJson();
    $ctx = rewards_user_context();
    $role = rewards_normalize_role($ctx['role']);
    $userId = apiSanitizeInt($ctx['user_id']);

    if ($role === null || !$userId) {
        apiRespond(403, ['ok' => false, 'error' => 'Unauthorized']);
    }

    $limits = rewards_fetch_limits($conn);
    $usage = rewards_usage_today($conn, $userId, $role, $limits['cooldown_minutes']);

    if ($usage['rewarded_today'] >= $limits['daily_view_limit']) {
        apiRespond(429, [
            'ok' => false,
            'error' => 'Daily limit reached',
            'limits' => [
                'daily_view_limit' => $limits['daily_view_limit'],
                'rewarded_today' => $usage['rewarded_today'],
            ],
        ]);
    }

    if (!empty($usage['next_available_at'])) {
        $next = new DateTime($usage['next_available_at']);
        $now = new DateTime('now');
        if ($next > $now) {
            apiRespond(429, [
                'ok' => false,
                'error' => 'Please wait before watching the next ad',
                'cooldown_ends_at' => $next->format(DATE_ATOM),
            ]);
        }
    }

    $adNetwork = trim((string)($payload['ad_network'] ?? 'admob'));
    if ($adNetwork === '') {
        $adNetwork = 'admob';
    }

    $sessionToken = rewards_generate_token();
    $rewardAmount = $limits['reward_amount'];

    $stmt = $conn->prepare(
        'INSERT INTO watch_ads_sessions (user_id, role, ad_network, reward_amount, status, session_token)
         VALUES (?, ?, ?, ?, \'initiated\', ?)'
    );
    $stmt->bind_param('issds', $userId, $role, $adNetwork, $rewardAmount, $sessionToken);
    $stmt->execute();
    $sessionId = (int)$stmt->insert_id;
    $stmt->close();

    apiRespond(200, [
        'ok' => true,
        'session' => [
            'id' => $sessionId,
            'token' => $sessionToken,
            'ad_network' => $adNetwork,
            'reward_amount' => $rewardAmount,
        ],
        'limits' => [
            'daily_view_limit' => $limits['daily_view_limit'],
            'rewarded_today' => $usage['rewarded_today'],
            'cooldown_minutes' => $limits['cooldown_minutes'],
        ],
    ]);
} catch (Throwable $e) {
    error_log('[rewards/watch/start] ' . $e->getMessage());
    apiRespond(500, ['ok' => false, 'error' => 'Unable to start watch session']);
}
