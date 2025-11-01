<?php
declare(strict_types=1);


/**
 * Resolve the current user context (role, ids) from session or request payload.
 *
 * @return array{role:string,user_id:int|null,driver_id:int|null,supervisor_id:int|null}
 */
function rewards_user_context(): array
{
    $role = strtolower(trim((string)($_SESSION['role'] ?? '')));
    $userId = apiSanitizeInt($_SESSION['user_id'] ?? null);
    $driverId = apiSanitizeInt($_SESSION['driver_id'] ?? null);
    $supervisorId = apiSanitizeInt($_SESSION['supervisor_id'] ?? null);

    $request = array_merge($_GET ?? [], $_POST ?? []);

    if ($role === '' && !empty($request['role'])) {
        $role = strtolower(trim((string)$request['role']));
    }
    if (!$userId) {
        $userId = apiSanitizeInt($request['userId'] ?? $request['user_id'] ?? null);
    }
    if (!$driverId) {
        $driverId = apiSanitizeInt($request['driverId'] ?? $request['driver_id'] ?? null);
    }
    if (!$supervisorId) {
        $supervisorId = apiSanitizeInt($request['supervisorId'] ?? $request['supervisor_id'] ?? null);
    }

    return [
        'role' => $role,
        'user_id' => $userId,
        'driver_id' => $driverId,
        'supervisor_id' => $supervisorId,
    ];
}

/**
 * Normalise role to either driver or supervisor, return null if not supported.
 */
function rewards_normalize_role(string $role): ?string
{
    $role = strtolower(trim($role));
    return in_array($role, ['driver', 'supervisor'], true) ? $role : null;
}

/**
 * Fetch reward configuration (reward amount, limits, cooldown).
 *
 * @return array{reward_amount:float,daily_view_limit:int,cooldown_minutes:int}
 */
function rewards_fetch_limits(mysqli $conn): array
{
    try {
        $result = $conn->query(
            'SELECT reward_amount, daily_view_limit, cooldown_minutes
             FROM watch_ads_limits
             WHERE id = 1
             LIMIT 1'
        );
        if ($result && $row = $result->fetch_assoc()) {
            return [
                'reward_amount' => (float)$row['reward_amount'],
                'daily_view_limit' => (int)$row['daily_view_limit'],
                'cooldown_minutes' => (int)$row['cooldown_minutes'],
            ];
        }
    } catch (Throwable $e) {
        // fall through to defaults
    }

    return [
        'reward_amount' => 1.0,
        'daily_view_limit' => 10,
        'cooldown_minutes' => 30,
    ];
}

/**
 * Return usage statistics for the current user.
 *
 * @return array{rewarded_today:int,last_rewarded_at:?string,next_available_at:?string}
 */
function rewards_usage_today(mysqli $conn, int $userId, string $role, int $cooldownMinutes): array
{
    $stmt = $conn->prepare(
        "SELECT
            SUM(CASE WHEN status = 'rewarded' AND DATE(rewarded_at) = CURDATE() THEN 1 ELSE 0 END) AS rewarded_today,
            MAX(CASE WHEN status = 'rewarded' THEN rewarded_at ELSE NULL END) AS last_rewarded_at
         FROM watch_ads_sessions
         WHERE user_id = ? AND role = ?"
    );
    $stmt->bind_param('is', $userId, $role);
    $stmt->execute();
    $res = $stmt->get_result();
    $row = $res->fetch_assoc() ?: ['rewarded_today' => 0, 'last_rewarded_at' => null];
    $stmt->close();

    $rewardedToday = (int)($row['rewarded_today'] ?? 0);
    $lastRewardedAt = $row['last_rewarded_at'] ?? null;
    $nextAvailableAt = null;

    if ($lastRewardedAt) {
        try {
            $last = new DateTime($lastRewardedAt);
            $last->modify('+' . max(0, $cooldownMinutes) . ' minutes');
            $nextAvailableAt = $last->format(DATE_ATOM);
        } catch (Throwable $e) {
            $nextAvailableAt = null;
        }
    }

    return [
        'rewarded_today' => $rewardedToday,
        'last_rewarded_at' => $lastRewardedAt,
        'next_available_at' => $nextAvailableAt,
    ];
}

/**
 * Fetch current reward balance for the user.
 */
function rewards_fetch_balance(mysqli $conn, int $userId): float
{
    $stmt = $conn->prepare(
        'SELECT balance FROM user_reward_balances WHERE user_id = ? LIMIT 1'
    );
    $stmt->bind_param('i', $userId);
    $stmt->execute();
    $res = $stmt->get_result();
    $balance = 0.0;
    if ($row = $res->fetch_assoc()) {
        $balance = (float)$row['balance'];
    }
    $stmt->close();
    return $balance;
}

/**
 * Append an entry to reward_ledger.
 */
function rewards_insert_ledger(
    mysqli $conn,
    int $userId,
    string $role,
    float $amount,
    string $type,
    ?int $referenceId,
    ?string $note = null
): void {
    $referenceIdParam = $referenceId ?? 0;
    $noteParam = $note ?? '';
    $stmt = $conn->prepare(
        "INSERT INTO reward_ledger (user_id, role, amount, type, reference_id, note)
         VALUES (?, ?, ?, ?, NULLIF(?, 0), NULLIF(?, ''))"
    );
    $stmt->bind_param('isdsis', $userId, $role, $amount, $type, $referenceIdParam, $noteParam);
    $stmt->execute();
    $stmt->close();
}

/**
 * Upsert the reward balance for the user.
 */
function rewards_update_balance(mysqli $conn, int $userId, string $role, float $increment): float
{
    $stmt = $conn->prepare(
        'INSERT INTO user_reward_balances (user_id, role, balance)
         VALUES (?, ?, ?)
         ON DUPLICATE KEY UPDATE balance = balance + VALUES(balance), role = VALUES(role)'
    );
    $stmt->bind_param('isd', $userId, $role, $increment);
    $stmt->execute();
    $stmt->close();

    return rewards_fetch_balance($conn, $userId);
}

/**
 * Generate a unique session token.
 */
function rewards_generate_token(): string
{
    return bin2hex(random_bytes(24));
}

/**
 * Fetch recent ledger entries.
 *
 * @return array<int, array<string, mixed>>
 */
function rewards_recent_ledger(mysqli $conn, int $userId, string $role, int $limit = 20): array
{
    $stmt = $conn->prepare(
        'SELECT amount, type, reference_id, note, created_at
         FROM reward_ledger
         WHERE user_id = ? AND role = ?
         ORDER BY created_at DESC
         LIMIT ?'
    );
    $stmt->bind_param('isi', $userId, $role, $limit);
    $stmt->execute();
    $res = $stmt->get_result();
    $rows = [];
    while ($row = $res->fetch_assoc()) {
        $row['amount'] = (float)$row['amount'];
        $rows[] = $row;
    }
    $stmt->close();
    return $rows;
}
