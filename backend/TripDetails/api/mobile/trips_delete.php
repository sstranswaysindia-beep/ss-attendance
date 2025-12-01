<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';
require_once dirname(__DIR__) . '/trip_notifications.php';

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
    // Make JSON body visible to downstream resolvers (they rely on TD_MOBILE_REQUEST/$_REQUEST-style data)
    $GLOBALS['TD_MOBILE_REQUEST'] = is_array($data) ? $data : [];
    $tripId = isset($data['trip_id']) ? (int)$data['trip_id'] : 0;

    if ($tripId <= 0) {
        td_json(['status' => 'error', 'error' => 'trip_id required'], 422);
    }

    $tripSnapshot = td_trip_fetch_snapshot($db, $tripId);
    if (!$tripSnapshot) {
        td_json(['status' => 'error', 'error' => 'Trip not found'], 404);
    }

    $stmt = $db->prepare('DELETE FROM trips WHERE id = ?');
    $stmt->bind_param('i', $tripId);
    $stmt->execute();
    $affected = $stmt->affected_rows;
    $stmt->close();

    if ($affected <= 0) {
        td_json(['status' => 'error', 'error' => 'Trip not found or already deleted'], 404);
    }

    $deletedByUserId = defined('TD_MOBILE_USER_ID') ? TD_MOBILE_USER_ID : null;
    $deletedByDriverId = defined('TD_MOBILE_DRIVER_ID') ? TD_MOBILE_DRIVER_ID : null;
    try {
        $session = (isset($_SESSION) && is_array($_SESSION)) ? $_SESSION : [];
        $sessionUser = (isset($session['user']) && is_array($session['user'])) ? $session['user'] : [];
        $sessionDriver = (isset($session['driver']) && is_array($session['driver'])) ? $session['driver'] : [];

        $deletedByName = isset($data['deleted_by_name']) && $data['deleted_by_name'] !== ''
            ? (string)$data['deleted_by_name']
            : (isset($data['deletedByName']) ? (string)$data['deletedByName'] : null);

        $deletedBy = td_trip_resolve_deleted_by($db, $deletedByUserId, $deletedByDriverId, $deletedByName);

        if (($deletedBy['user_id'] ?? null) === null) {
            $deletedBy['user_id'] = td_trip_first_valid_int([
                $deletedByUserId,
                $session['user_id'] ?? null,
                $session['id'] ?? null,
                $sessionUser['id'] ?? null,
                $sessionUser['user_id'] ?? null,
                $data['user_id'] ?? null,
                $data['userId'] ?? null,
            ]);
        }
        if (($deletedBy['driver_id'] ?? null) === null) {
            $deletedBy['driver_id'] = td_trip_first_valid_int([
                $deletedByDriverId,
                $session['driver_id'] ?? null,
                $sessionDriver['id'] ?? null,
                $sessionDriver['driver_id'] ?? null,
                $data['driver_id'] ?? null,
                $data['driverId'] ?? null,
            ]);
        }
        if (!isset($deletedBy['name']) || trim((string)$deletedBy['name']) === '') {
            $deletedBy['name'] = td_trip_first_non_empty_string([
                $session['full_name'] ?? null,
                $session['username'] ?? null,
                $session['name'] ?? null,
                $session['display_name'] ?? null,
                $sessionUser['full_name'] ?? null,
                $sessionUser['username'] ?? null,
                $sessionUser['name'] ?? null,
                $sessionUser['display_name'] ?? null,
                $session['driver_name'] ?? null,
                $sessionDriver['name'] ?? null,
                $sessionDriver['full_name'] ?? null,
                $data['deleted_by_name'] ?? null,
                $data['deletedByName'] ?? null,
            ]) ?? 'Unknown user';
        }

        td_trip_record_notification($db, $tripSnapshot, $deletedBy);
    } catch (Throwable $notifyError) {
        error_log('[td_mobile_trips_delete] notification_log_failed: ' . $notifyError->getMessage());
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
