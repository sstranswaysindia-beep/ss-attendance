<?php
/**
 * referral_register.php
 * Register a new user via a referral code.
 * POST body: { "username": "...", "password": "...", "referral_code": "..." }
 * Returns:  { "status": "ok", "user_id": "123" }
 */
declare(strict_types=1);
require_once __DIR__ . '/common.php';

apiSendCorsHeaders();
apiEnsurePost();

$data = apiRequireJson();
$username = trim((string) ($data['username'] ?? ''));
$password = (string) ($data['password'] ?? '');
$referralCode = trim((string) ($data['referral_code'] ?? ''));

if ($username === '' || $password === '' || $referralCode === '') {
    apiRespond(400, [
        'status' => 'error',
        'error' => 'username, password, and referral_code are all required',
    ]);
}

if (strlen($username) < 4) {
    apiRespond(400, ['status' => 'error', 'error' => 'Username must be at least 4 characters']);
}

if (strlen($password) < 6) {
    apiRespond(400, ['status' => 'error', 'error' => 'Password must be at least 6 characters']);
}

// ── Verify referral code exists ─────────────────────────────────────────
$codeStmt = $conn->prepare('SELECT id FROM users WHERE referral_code = ?');
$codeStmt->bind_param('s', $referralCode);
$codeStmt->execute();
$codeResult = $codeStmt->get_result();
$referrer = $codeResult->fetch_assoc();
$codeStmt->close();

if (!$referrer) {
    apiRespond(400, ['status' => 'error', 'error' => 'Invalid referral code']);
}

$referrerUserId = (int) $referrer['id'];

// ── Check if username already exists ────────────────────────────────────
$checkStmt = $conn->prepare('SELECT id FROM users WHERE username = ?');
$checkStmt->bind_param('s', $username);
$checkStmt->execute();
$checkResult = $checkStmt->get_result();
if ($checkResult->num_rows > 0) {
    apiRespond(400, ['status' => 'error', 'error' => 'Username already taken']);
}
$checkStmt->close();

// ── Create user ─────────────────────────────────────────────────────────
$hashedPassword = password_hash($password, PASSWORD_DEFAULT);
$role = 'referral'; // keep referral users separate from operational driver/supervisor roles
$now = date('Y-m-d H:i:s');

$insertStmt = $conn->prepare(
    'INSERT INTO users (username, password, role, referred_by, created_at) VALUES (?, ?, ?, ?, ?)'
);
$insertStmt->bind_param('sssis', $username, $hashedPassword, $role, $referrerUserId, $now);

if (!$insertStmt->execute()) {
    apiRespond(500, ['status' => 'error', 'error' => 'Failed to create user: ' . $conn->error]);
}

$newUserId = $conn->insert_id;
$insertStmt->close();

// ── Create referral record (status = pending) ───────────────────────────
$insertRef = $conn->prepare(
    'INSERT INTO user_referrals (referrer_user_id, referral_code, referred_user_id, referred_username, status, amount, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
);
$status = 'pending';
$amount = 0.00; // will be set after profile submit (driver=50, helper=30)
$insertRef->bind_param(
    'isissds',
    $referrerUserId,
    $referralCode,
    $newUserId,
    $username,
    $status,
    $amount,
    $now
);
$insertRef->execute();
$insertRef->close();

apiRespond(200, [
    'status' => 'ok',
    'user_id' => (string) $newUserId,
    'message' => 'User registered successfully',
]);
