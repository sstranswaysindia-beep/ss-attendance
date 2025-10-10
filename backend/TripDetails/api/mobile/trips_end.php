<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

if (!function_exists('td_json')) {
    function td_json(array $payload, int $status = 200): void
    {
        if (function_exists('ob_get_level')) {
            while (ob_get_level() > 0) {
                @ob_end_clean();
            }
        }

        if (!headers_sent()) {
            http_response_code($status);
            header('Content-Type: application/json; charset=utf-8');
            header('Cache-Control: no-store, no-cache, must-revalidate, private');
        }

        echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }
}

/** @var mysqli|null $conn */
/** @var mysqli|null $mysqli */
/** @var mysqli|null $con */
$db = $conn instanceof mysqli
    ? $conn
    : ($mysqli instanceof mysqli
        ? $mysqli
        : ($con instanceof mysqli ? $con : null));

if (!$db || $db->connect_errno) {
    td_json(['status' => 'error', 'error' => 'Database connection not available'], 500);
}

@$db->set_charset('utf8mb4');
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

if (!function_exists('td_table_exists')) {
    function td_table_exists(mysqli $db, string $table): bool
    {
        $table = $db->real_escape_string($table);
        $res = $db->query("SHOW TABLES LIKE '{$table}'");
        return $res && $res->num_rows > 0;
    }
}

if (!function_exists('td_has_col')) {
    function td_has_col(mysqli $db, string $table, string $column): bool
    {
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
}

function td_read_body(): array
{
    $payload = $GLOBALS['TD_MOBILE_REQUEST'] ?? [];
    if (!is_array($payload) || empty($payload)) {
        $raw = file_get_contents('php://input') ?: '';
        if ($raw !== '') {
            $json = json_decode($raw, true);
            if (is_array($json)) {
                $payload = $json;
            }
        }
    }

    if (!is_array($payload)) {
        $payload = [];
    }

    return $payload;
}

function td_to_ymd(?string $value): ?string
{
    if ($value === null) {
        return null;
    }

    $value = trim($value);
    if ($value === '') {
        return null;
    }

    if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $value)) {
        return $value;
    }

    if (preg_match('/^(\d{2})[-\/](\d{2})[-\/](\d{4})$/', $value, $matches)) {
        return sprintf('%s-%s-%s', $matches[3], $matches[2], $matches[1]);
    }

    return $value;
}

try {
    if (!td_table_exists($db, 'trips')) {
        td_json(['status' => 'error', 'error' => 'trips table missing'], 500);
    }

    $data = td_read_body();

    $tripId = isset($data['trip_id']) ? (int)$data['trip_id'] : 0;
    $endDate = td_to_ymd(isset($data['end_date']) ? (string)$data['end_date'] : null);

    $rawEndKm = $data['end_km'] ?? null;
    $endKm = ($rawEndKm === null || $rawEndKm === '') ? null : (int)str_replace(',', '', (string)$rawEndKm);

    if ($tripId <= 0) {
        td_json(['status' => 'error', 'error' => 'trip_id required'], 422);
    }

    if ($endDate === null || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $endDate)) {
        td_json(['status' => 'error', 'error' => 'end_date must be YYYY-MM-DD'], 422);
    }

    if ($endKm === null || $endKm < 0) {
        td_json(['status' => 'error', 'error' => 'end_km required/invalid'], 422);
    }

    $columns = ['start_km'];
    if (td_has_col($db, 'trips', 'status')) {
        $columns[] = 'status';
    }
    if (td_has_col($db, 'trips', 'end_km')) {
        $columns[] = 'end_km';
    }
    if (td_has_col($db, 'trips', 'end_date')) {
        $columns[] = 'end_date';
    }
    if (td_has_col($db, 'trips', 'start_date')) {
        $columns[] = 'start_date';
    }

    $sql = 'SELECT ' . implode(',', $columns) . ' FROM trips WHERE id = ? LIMIT 1';
    $stmt = $db->prepare($sql);
    $stmt->bind_param('i', $tripId);
    $stmt->execute();
    $result = $stmt->get_result();
    if (!$result || !$result->num_rows) {
        $stmt->close();
        td_json(['status' => 'error', 'error' => 'Trip not found'], 404);
    }

    $trip = $result->fetch_assoc();
    $stmt->close();

    $startKm = (int)($trip['start_km'] ?? 0);
    $startDate = isset($trip['start_date']) ? td_to_ymd((string)$trip['start_date']) : null;

    $alreadyEnded = false;
    if (array_key_exists('status', $trip)) {
        $status = strtolower((string)($trip['status'] ?? ''));
        $alreadyEnded = in_array($status, ['ended', 'completed', '0', 'false'], true);
    } else {
        if (array_key_exists('end_km', $trip) && $trip['end_km'] !== null) {
            $alreadyEnded = true;
        }
        if (array_key_exists('end_date', $trip) && $trip['end_date'] !== null) {
            $alreadyEnded = true;
        }
    }

    if ($alreadyEnded) {
        td_json(['status' => 'error', 'error' => 'Trip already ended'], 409);
    }

    if ($endKm <= $startKm) {
        td_json([
            'status' => 'error',
            'error' => "End KM must be greater than Start KM (Start: {$startKm})",
        ], 422);
    }

    if ($startDate !== null && preg_match('/^\d{4}-\d{2}-\d{2}$/', $startDate)) {
        if (strcmp($endDate, $startDate) < 0) {
            td_json([
                'status' => 'error',
                'error' => "End date ({$endDate}) cannot be before Start date ({$startDate})",
            ], 422);
        }
    }

    $sets = [];
    $types = '';
    $values = [];

    if (td_has_col($db, 'trips', 'end_date')) {
        $sets[] = 'end_date = ?';
        $types .= 's';
        $values[] = $endDate;
    }

    if (td_has_col($db, 'trips', 'end_km')) {
        $sets[] = 'end_km = ?';
        $types .= 'i';
        $values[] = $endKm;
    }

    if (td_has_col($db, 'trips', 'status')) {
        $sets[] = "status = 'ended'";
    }

    if (td_has_col($db, 'trips', 'ended_at')) {
        $sets[] = 'ended_at = NOW()';
    }

    if (empty($sets)) {
        td_json(['status' => 'error', 'error' => 'No suitable columns to update (check schema)'], 500);
    }

    $updateSql = 'UPDATE trips SET ' . implode(', ', $sets) . ' WHERE id = ?';
    $stmt = $db->prepare($updateSql);
    $types .= 'i';
    $values[] = $tripId;

    $bindParams = [$types];
    foreach ($values as $index => &$value) {
        $bindParams[] = &$value;
    }
    call_user_func_array([$stmt, 'bind_param'], $bindParams);
    $stmt->execute();
    $stmt->close();

    $totalKm = null;
    if (td_has_col($db, 'trips', 'total_km')) {
        $stmt = $db->prepare('SELECT total_km FROM trips WHERE id = ?');
        $stmt->bind_param('i', $tripId);
        $stmt->execute();
        $result = $stmt->get_result();
        if ($result && $result->num_rows) {
            $totalKm = (int)($result->fetch_assoc()['total_km'] ?? 0);
        }
        $stmt->close();
    } else {
        $totalKm = max(0, $endKm - $startKm);
    }

    td_json([
        'status' => 'ok',
        'trip_id' => $tripId,
        'total_km' => $totalKm,
    ]);
} catch (mysqli_sql_exception $exception) {
    td_json([
        'status' => 'error',
        'error' => 'Database error',
        'code' => (int)$exception->getCode(),
        'detail' => $exception->getMessage(),
    ], 500);
} catch (Throwable $exception) {
    td_json([
        'status' => 'error',
        'error' => $exception->getMessage(),
    ], 500);
}
