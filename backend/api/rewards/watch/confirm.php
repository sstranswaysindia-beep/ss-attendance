<?php
declare(strict_types=1);

require dirname(__DIR__) . '/bootstrap.php';

$transactionStarted = false;

try {
    apiEnsurePost();

    if (!isset($conn) || !$conn instanceof mysqli) {
        apiRespond(500, ['ok' => false, 'error' => 'Database connection not available']);
    }

    $payload = apiRequireJson();
    $token = trim((string)($payload['session_token'] ?? ''));
    if ($token === '') {
        apiRespond(422, ['ok' => false, 'error' => 'session_token required']);
    }

    $ctx = rewards_user_context();
    $role = rewards_normalize_role($ctx['role']);
    $userId = apiSanitizeInt($ctx['user_id']);

    if ($role === null || !$userId) {
        apiRespond(403, ['ok' => false, 'error' => 'Unauthorized']);
    }

    $conn->begin_transaction();
    $transactionStarted = true;

    $stmt = $conn->prepare(
        'SELECT id, user_id, role, status, reward_amount
         FROM watch_ads_sessions
         WHERE session_token = ?
         LIMIT 1
         FOR UPDATE'
    );
    $stmt->bind_param('s', $token);
    $stmt->execute();
    $res = $stmt->get_result();
    $session = $res->fetch_assoc();
    $stmt->close();

    if (!$session) {
        $conn->rollback();
        apiRespond(404, ['ok' => false, 'error' => 'Invalid session token']);
    }

    if ((int)$session['user_id'] !== $userId || $session['role'] !== $role) {
        $conn->rollback();
        apiRespond(403, ['ok' => false, 'error' => 'Session does not belong to user']);
    }

    if ($session['status'] === 'rewarded') {
        $balance = rewards_fetch_balance($conn, $userId);
        $conn->commit();
        apiRespond(200, [
            'ok' => true,
            'duplicate' => true,
            'reward_amount' => (float)$session['reward_amount'],
            'balance' => $balance,
        ]);
    }

    if ($session['status'] !== 'initiated') {
        $conn->rollback();
        apiRespond(409, ['ok' => false, 'error' => 'Session already resolved']);
    }

    $rewardAmount = (float)$session['reward_amount'];

    $updateStmt = $conn->prepare(
        "UPDATE watch_ads_sessions
         SET status = 'rewarded', rewarded_at = NOW(), updated_at = NOW()
         WHERE id = ?"
    );
    $sessionId = (int)$session['id'];
    $updateStmt->bind_param('i', $sessionId);
    $updateStmt->execute();
    $updateStmt->close();

    $balance = rewards_update_balance($conn, $userId, $role, $rewardAmount);
    rewards_insert_ledger(
        $conn,
        $userId,
        $role,
        $rewardAmount,
        'ad_reward',
        $sessionId,
        'Rewarded ad view'
    );

    $conn->commit();
    $transactionStarted = false;

    apiRespond(200, [
        'ok' => true,
        'reward_amount' => $rewardAmount,
        'balance' => $balance,
        'session_id' => $sessionId,
    ]);
} catch (Throwable $e) {
    if ($transactionStarted && isset($conn) && $conn instanceof mysqli) {
        $conn->rollback();
    }
    error_log('[rewards/watch/confirm] ' . $e->getMessage());
    apiRespond(500, ['ok' => false, 'error' => 'Unable to confirm reward']);
}
