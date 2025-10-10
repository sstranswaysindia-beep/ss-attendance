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

try {
    if (!td_table_exists($db, 'trips')) {
        td_json(['status' => 'error', 'error' => 'trips table missing'], 500);
    }

    $data = td_read_body();
    $tripId = isset($data['trip_id']) ? (int)$data['trip_id'] : 0;

    if ($tripId <= 0) {
        td_json(['status' => 'error', 'error' => 'trip_id required'], 422);
    }

    $stmt = $db->prepare('DELETE FROM trips WHERE id = ?');
    $stmt->bind_param('i', $tripId);
    $stmt->execute();
    $affected = $stmt->affected_rows;
    $stmt->close();

    if ($affected <= 0) {
        td_json(['status' => 'error', 'error' => 'Trip not found or already deleted'], 404);
    }

    td_json(['status' => 'ok', 'trip_id' => $tripId]);
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
