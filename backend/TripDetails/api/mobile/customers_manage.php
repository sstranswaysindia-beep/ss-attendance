<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';
require __DIR__ . '/_auth_guard.php';

global $conn, $mysqli, $con;
/** @var mysqli|null $db */
$db = $conn instanceof mysqli ? $conn
    : ($mysqli instanceof mysqli ? $mysqli
    : ($con instanceof mysqli ? $con : null));

if (!$db || $db->connect_errno) {
    apiRespond(500, ['status' => 'error', 'error' => 'DB unavailable']);
}

@$db->set_charset('utf8mb4');
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

function cm_request(): array {
    return $GLOBALS['TD_MOBILE_REQUEST'] ?? [];
}

function cm_action(): string {
    return strtolower(trim((string) (cm_request()['action'] ?? 'list')));
}

function cm_table_exists(mysqli $db, string $table): bool {
    $table = $db->real_escape_string($table);
    $res = $db->query("SHOW TABLES LIKE '{$table}'");
    return $res && $res->num_rows > 0;
}

function cm_has_col(mysqli $db, string $table, string $column): bool {
    $table = $db->real_escape_string($table);
    $column = $db->real_escape_string($column);
    $sql = "SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = '{$table}'
              AND COLUMN_NAME = '{$column}'
            LIMIT 1";
    $res = $db->query($sql);
    return $res && $res->num_rows > 0;
}

function cm_norm_spaces(string $value): string {
    $value = trim($value);
    $value = preg_replace('/\s+/u', ' ', $value) ?? $value;
    return $value;
}

function cm_clean_name(string $name): string {
    $name = cm_norm_spaces($name);
    if ($name === '') {
        return '';
    }
    $name = preg_replace('/[^\pL\pN ]+/u', ' ', $name) ?? $name;
    return cm_norm_spaces($name);
}

function cm_code_from_first_chars(string $name, int $n, int $maxLen = 40): string {
    $n = max(1, $n);
    $name = cm_clean_name($name);
    $raw = preg_replace('/[^\pL\pN]+/u', '', $name) ?? '';
    $raw = strtoupper($raw);
    if ($raw === '') {
        $raw = 'CUST';
    }
    $code = substr($raw, 0, min($n, $maxLen));
    $code = preg_replace('/[^A-Z0-9]/', '', $code) ?? '';
    if ($code === '') {
        $code = 'CUST';
    }
    return strlen($code) > $maxLen ? substr($code, 0, $maxLen) : $code;
}

function cm_short_code_exists(mysqli $db, string $code, int $excludeId = 0): bool {
    if ($excludeId > 0) {
        $stmt = $db->prepare('SELECT id FROM customers_master WHERE short_code = ? AND id <> ? LIMIT 1');
        $stmt->bind_param('si', $code, $excludeId);
    } else {
        $stmt = $db->prepare('SELECT id FROM customers_master WHERE short_code = ? LIMIT 1');
        $stmt->bind_param('s', $code);
    }
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();
    return (bool) $row;
}

function cm_auto_short_code(mysqli $db, string $customerName, int $excludeId = 0): string {
    $customerName = cm_clean_name($customerName);
    $raw = preg_replace('/[^\pL\pN]+/u', '', $customerName) ?? '';
    $raw = strtoupper($raw);
    if ($raw === '') {
        $raw = 'CUST';
    }

    $maxLen = 40;
    $maxTry = min($maxLen, max(3, strlen($raw)));
    $last = '';

    for ($n = 3; $n <= $maxTry; $n++) {
        $code = cm_code_from_first_chars($customerName, $n, $maxLen);
        $last = $code;
        if (!cm_short_code_exists($db, $code, $excludeId)) {
            return $code;
        }
    }

    $base = substr(($last ?: 'CUST'), 0, 38);
    for ($i = 1; $i <= 99; $i++) {
        $try = $base . str_pad((string) $i, 2, '0', STR_PAD_LEFT);
        if (!cm_short_code_exists($db, $try, $excludeId)) {
            return $try;
        }
    }

    return substr($base, 0, 39) . 'X';
}

function cm_fetch_customers(mysqli $db): array {
    if (!cm_table_exists($db, 'customers_master')) {
        throw new RuntimeException('customers_master table not found');
    }

    $hasShort = cm_has_col($db, 'customers_master', 'short_code');
    $hasStatus = cm_has_col($db, 'customers_master', 'status');
    $hasCreated = cm_has_col($db, 'customers_master', 'created_at');

    $sql = 'SELECT id, customer_name'
        . ($hasShort ? ', short_code' : ', "" AS short_code')
        . ($hasStatus ? ', status' : ', "Active" AS status')
        . ($hasCreated ? ', created_at' : ', NULL AS created_at')
        . ' FROM customers_master
            WHERE customer_name IS NOT NULL
              AND TRIM(customer_name) <> ""
          ORDER BY customer_name ASC';

    $rows = [];
    if ($result = $db->query($sql)) {
        while ($row = $result->fetch_assoc()) {
            $rows[] = [
                'id' => (int) ($row['id'] ?? 0),
                'customer_name' => trim((string) ($row['customer_name'] ?? '')),
                'short_code' => trim((string) ($row['short_code'] ?? '')),
                'status' => trim((string) ($row['status'] ?? 'Active')) ?: 'Active',
                'created_at' => $row['created_at'] ?? null,
            ];
        }
        $result->close();
    }

    return $rows;
}

try {
    $action = cm_action();

    if ($action === 'list') {
        apiRespond(200, [
            'status' => 'ok',
            'customers' => cm_fetch_customers($db),
        ]);
    }

    apiEnsurePost();
    $request = cm_request();

    if ($action === 'add') {
        $rawInput = trim((string) ($request['customer_name'] ?? $request['customerNames'] ?? $request['customer_names'] ?? ''));
        if ($rawInput === '') {
            apiRespond(400, ['status' => 'error', 'error' => 'Customer name required']);
        }

        $parts = preg_split('/\s*,\s*/u', $rawInput) ?: [];
        $parts = array_values(array_filter($parts, static fn ($value) => trim((string) $value) !== ''));
        if (empty($parts)) {
            apiRespond(400, ['status' => 'error', 'error' => 'No valid customer names found']);
        }

        $inserted = [];
        $skipped = [];
        $errors = [];

        $dupStmt = $db->prepare('SELECT id FROM customers_master WHERE customer_name = ? LIMIT 1');
        $insertStmt = $db->prepare(
            "INSERT INTO customers_master (customer_name, short_code, status)
             VALUES (?, ?, 'Active')"
        );

        foreach ($parts as $part) {
            $name = cm_clean_name((string) $part);
            if ($name === '') {
                $errors[] = ['name' => (string) $part, 'reason' => 'Empty after cleaning'];
                continue;
            }

            $dupStmt->bind_param('s', $name);
            $dupStmt->execute();
            $existing = $dupStmt->get_result()->fetch_assoc();
            if ($existing) {
                $skipped[] = $name;
                continue;
            }

            $code = cm_auto_short_code($db, $name);

            try {
                $insertStmt->bind_param('ss', $name, $code);
                $insertStmt->execute();
                $inserted[] = [
                    'id' => (int) $insertStmt->insert_id,
                    'customer_name' => $name,
                    'short_code' => $code,
                ];
            } catch (Throwable $error) {
                $message = $error->getMessage();
                if (stripos($message, 'duplicate') !== false) {
                    $skipped[] = $name;
                } else {
                    $errors[] = ['name' => $name, 'reason' => $message];
                }
            }
        }

        $dupStmt->close();
        $insertStmt->close();

        apiRespond(200, [
            'status' => 'ok',
            'message' => sprintf(
                'Done. Inserted: %d, Skipped: %d%s',
                count($inserted),
                count($skipped),
                count($errors) > 0 ? ', Errors: ' . count($errors) : ''
            ),
            'count_inserted' => count($inserted),
            'count_skipped' => count($skipped),
            'count_errors' => count($errors),
            'inserted' => $inserted,
            'skipped' => $skipped,
            'errors' => $errors,
        ]);
    }

    if ($action === 'update') {
        $id = apiSanitizeInt($request['id'] ?? null);
        $name = cm_clean_name((string) ($request['customer_name'] ?? $request['customerName'] ?? ''));
        $status = trim((string) ($request['status'] ?? 'Active'));
        $regenCode = apiSanitizeInt($request['regen_code'] ?? $request['regenCode'] ?? 0) === 1;

        if (!$id || $id <= 0) {
            apiRespond(400, ['status' => 'error', 'error' => 'Invalid id']);
        }
        if ($name === '') {
            apiRespond(400, ['status' => 'error', 'error' => 'Customer name required']);
        }
        if (!in_array($status, ['Active', 'Inactive'], true)) {
            $status = 'Active';
        }

        $currentStmt = $db->prepare('SELECT id, short_code FROM customers_master WHERE id = ? LIMIT 1');
        $currentStmt->bind_param('i', $id);
        $currentStmt->execute();
        $current = $currentStmt->get_result()->fetch_assoc();
        $currentStmt->close();
        if (!$current) {
            apiRespond(404, ['status' => 'error', 'error' => 'Row not found']);
        }

        $dupStmt = $db->prepare('SELECT id FROM customers_master WHERE customer_name = ? AND id <> ? LIMIT 1');
        $dupStmt->bind_param('si', $name, $id);
        $dupStmt->execute();
        $dup = $dupStmt->get_result()->fetch_assoc();
        $dupStmt->close();
        if ($dup) {
            apiRespond(409, ['status' => 'error', 'error' => 'Customer name already used']);
        }

        $shortCode = (string) ($current['short_code'] ?? '');
        if ($regenCode) {
            $shortCode = cm_auto_short_code($db, $name, $id);
            $stmt = $db->prepare('UPDATE customers_master SET customer_name = ?, short_code = ?, status = ? WHERE id = ?');
            $stmt->bind_param('sssi', $name, $shortCode, $status, $id);
        } else {
            $stmt = $db->prepare('UPDATE customers_master SET customer_name = ?, status = ? WHERE id = ?');
            $stmt->bind_param('ssi', $name, $status, $id);
        }
        $stmt->execute();
        $stmt->close();

        apiRespond(200, [
            'status' => 'ok',
            'message' => $regenCode ? 'Regenerated' : 'Updated',
            'customer' => [
                'id' => $id,
                'customer_name' => $name,
                'short_code' => $shortCode,
                'status' => $status,
            ],
        ]);
    }

    if ($action === 'delete') {
        $id = apiSanitizeInt($request['id'] ?? null);
        if (!$id || $id <= 0) {
            apiRespond(400, ['status' => 'error', 'error' => 'Invalid id']);
        }

        $stmt = $db->prepare('DELETE FROM customers_master WHERE id = ?');
        $stmt->bind_param('i', $id);
        $stmt->execute();
        $affected = $stmt->affected_rows;
        $stmt->close();

        apiRespond(200, [
            'status' => 'ok',
            'message' => 'Deleted',
            'affected' => $affected,
        ]);
    }

    apiRespond(400, ['status' => 'error', 'error' => 'Unsupported action']);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
