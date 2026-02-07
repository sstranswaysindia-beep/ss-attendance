<?php
declare(strict_types=1);

ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);
date_default_timezone_set('Asia/Kolkata');

if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

$authFile = __DIR__ . '/../includes/auth.php';
if (is_file($authFile)) {
    require_once $authFile;
    if (function_exists('checkRole')) {
        checkRole(['admin']); // add 'supervisor' later if needed
    }
}

// Restrict this page to only specific usernames
$allowedUsers = ['vikas_sachan', 'neeraj'];

$currentLogin = strtolower((string) (
    $_SESSION['username']
        ?? $_SESSION['user_name']
        ?? ($_SESSION['user']['username'] ?? '')
        ?? ($_SESSION['user']['name'] ?? '')
));

if (!in_array($currentLogin, $allowedUsers, true)) {
    http_response_code(403);
    echo 'Access denied: you are not allowed to view this page.';
    exit;
}

/**
 * We rely on api/mobile/common.php (same style as other DriverDocs pages)
 * to bootstrap $conn and shared helpers.
 */
$commonCandidates = [
    __DIR__ . '/api/mobile/common.php',
    dirname(__DIR__) . '/api/mobile/common.php',
    __DIR__ . '/common.php',
];
$commonLoaded = false;
foreach ($commonCandidates as $path) {
    if (is_file($path)) {
        require_once $path;
        $commonLoaded = true;
        break;
    }
}
if (!$commonLoaded) {
    throw new RuntimeException(
        'Unable to locate api/mobile/common.php. Tried paths: ' . implode(', ', $commonCandidates)
    );
}

mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

$currentUserId = isset($_SESSION['user_id']) ? (int) $_SESSION['user_id'] : 0;
if ($currentUserId <= 0 && isset($_SESSION['user']['id'])) {
    $currentUserId = (int) $_SESSION['user']['id'];
}
$currentUserName = (string) (
    $_SESSION['user_name']
        ?? $_SESSION['username']
        ?? ($_SESSION['user']['display_name'] ?? '')
        ?? ($_SESSION['user']['name'] ?? '')
        ?? 'Admin'
);

if (empty($_SESSION['supervisor_approval_csrf'])) {
    $_SESSION['supervisor_approval_csrf'] = bin2hex(random_bytes(16));
}
$csrfToken = $_SESSION['supervisor_approval_csrf'];

$flash = $_SESSION['supervisor_approval_flash'] ?? null;
unset($_SESSION['supervisor_approval_flash']);

function supervisorRedirectWithFlash(string $type, string $message): void {
    $_SESSION['supervisor_approval_flash'] = [
        'type' => $type,
        'message' => $message,
    ];
    $redirect = $_SERVER['REQUEST_URI'] ?? 'supervisor_approvals_admin.php';
    header('Location: ' . $redirect);
    exit;
}

function h(?string $value): string {
    return htmlspecialchars((string) $value, ENT_QUOTES, 'UTF-8');
}

function formatDateTime(?string $value): string {
    if (!$value) return '—';
    try {
        $dt = new DateTime($value);
        return $dt->format('d M Y · h:i A');
    } catch (Throwable $e) {
        return $value;
    }
}

function formatWorkingHours(?string $inTime, ?string $outTime): string {
    if (!$inTime || !$outTime) return '—';
    try {
        $in = new DateTime($inTime);
        $out = new DateTime($outTime);
        if ($out < $in) return '—';
        $seconds = $out->getTimestamp() - $in->getTimestamp();
        $hours = intdiv($seconds, 3600);
        $minutes = intdiv($seconds % 3600, 60);
        return sprintf('%02d:%02d', $hours, $minutes);
    } catch (Throwable $e) {
        return '—';
    }
}

function isDifferentInOutDate(?string $inTime, ?string $outTime): bool {
    if (!$inTime || !$outTime) return false;
    try {
        $in = new DateTime($inTime);
        $out = new DateTime($outTime);
        return $in->format('Y-m-d') !== $out->format('Y-m-d');
    } catch (Throwable $e) {
        return false;
    }
}

function statusBadgeClass(string $status): string {
    switch (strtolower($status)) {
        case 'approved': return 'success';
        case 'rejected': return 'danger';
        case 'pending':  return 'warning';
        default:         return 'secondary';
    }
}

/* ----------------- POST: Approve / Reject ----------------- */
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['attendance_id'], $_POST['action'])) {
    $isAjax = (
        isset($_POST['ajax']) && $_POST['ajax'] === '1'
    ) || (
        isset($_SERVER['HTTP_X_REQUESTED_WITH']) &&
        strtolower($_SERVER['HTTP_X_REQUESTED_WITH']) === 'xmlhttprequest'
    );

    $sendJson = function (string $status, string $message, array $extra = []) {
        if (!headers_sent()) header('Content-Type: application/json; charset=UTF-8');
        echo json_encode(array_merge([
            'status'  => $status, // 'ok' or 'error'
            'message' => $message,
        ], $extra));
        exit;
    };

    $token = (string) ($_POST['csrf_token'] ?? '');
    if (!hash_equals($csrfToken, $token)) {
        if ($isAjax) $sendJson('error', 'Invalid or expired form token. Please refresh the page.');
        supervisorRedirectWithFlash('danger', 'Invalid or expired form token. Please try again.');
    }

    if ($currentUserId <= 0) {
        if ($isAjax) $sendJson('error', 'Your admin session is missing a user id. Please log in again.');
        supervisorRedirectWithFlash('danger', 'Your admin session is missing a user id. Please log in again.');
    }

    $attendanceId = filter_var($_POST['attendance_id'], FILTER_VALIDATE_INT);
    $action = strtolower(trim((string) $_POST['action']));
    $notes  = trim((string) ($_POST['notes'] ?? ''));

    if (!$attendanceId || $attendanceId <= 0) {
        if ($isAjax) $sendJson('error', 'Invalid attendance id.');
        supervisorRedirectWithFlash('danger', 'Invalid attendance id.');
    }
    if (!in_array($action, ['approve', 'reject'], true)) {
        if ($isAjax) $sendJson('error', 'Unsupported action requested.');
        supervisorRedirectWithFlash('danger', 'Unsupported action requested.');
    }

    try {
        $fetchStmt = $conn->prepare(
            'SELECT approval_status, driver_id, plant_id, in_time, out_time, notes
               FROM attendance
              WHERE id = ?
              LIMIT 1'
        );
        $fetchStmt->bind_param('i', $attendanceId);
        $fetchStmt->execute();
        $attendanceRow = $fetchStmt->get_result()->fetch_assoc();
        $fetchStmt->close();

        if (!$attendanceRow) {
            if ($isAjax) $sendJson('error', 'Attendance record not found.');
            supervisorRedirectWithFlash('danger', 'Attendance record not found.');
        }

        if ($action === 'approve' && empty($attendanceRow['out_time'])) {
            $msg = 'Cannot approve until an OUT punch has been submitted.';
            if ($isAjax) $sendJson('error', $msg);
            supervisorRedirectWithFlash('danger', $msg);
        }

        $newStatus = $action === 'approve' ? 'Approved' : 'Rejected';

        $updateStmt = $conn->prepare(
            'UPDATE attendance
                SET approval_status = ?,
                    notes = CASE WHEN ? <> "" THEN ? ELSE notes END,
                    closed_by_id = ?,
                    closed_at = NOW(),
                    source = "web"
              WHERE id = ?
              LIMIT 1'
        );
        $updateStmt->bind_param('sssii', $newStatus, $notes, $notes, $currentUserId, $attendanceId);
        $updateStmt->execute();
        $affected = $updateStmt->affected_rows;
        $updateStmt->close();

        $alreadyUpdated = false;
        if ($affected <= 0) {
            $previousStatus = (string) ($attendanceRow['approval_status'] ?? '');
            if (strcasecmp($previousStatus, $newStatus) === 0) {
                $alreadyUpdated = true;
            } else {
                throw new RuntimeException('Unable to update attendance record.');
            }
        }

        // Link adjust request via notes (#123) if present
        $adjustRequestId = null;
        if (!empty($attendanceRow['notes']) &&
            preg_match('/#(\d+)/', (string) $attendanceRow['notes'], $match)
        ) {
            $adjustRequestId = (int) $match[1];
        }

        if ($adjustRequestId) {
            $resolutionNote = $notes !== '' ? $notes : '';
            $adjustStmt = $conn->prepare(
                'UPDATE attendance_adjust_requests
                    SET status = ?,
                        resolved_by_id = ?,
                        resolved_at = NOW(),
                        resolution_note = NULLIF(?, "")
                  WHERE id = ?
                  LIMIT 1'
            );
            $adjustStmt->bind_param('sisi', $newStatus, $currentUserId, $resolutionNote, $adjustRequestId);
            $adjustStmt->execute();
            $adjustStmt->close();
        }

        $message = $alreadyUpdated
            ? "Attendance #{$attendanceId} was already marked as {$newStatus}."
            : "Attendance #{$attendanceId} marked as {$newStatus}.";

        if ($isAjax) {
            $sendJson('ok', $message, [
                'attendanceId'   => $attendanceId,
                'newStatus'      => $newStatus,
                'alreadyUpdated' => $alreadyUpdated,
            ]);
        }

        supervisorRedirectWithFlash('success', $message);
    } catch (Throwable $e) {
        $err = 'Failed to update attendance: ' . $e->getMessage();
        if ($isAjax) $sendJson('error', $err);
        supervisorRedirectWithFlash('danger', $err);
    }
}

/* ----------------- Filters: Status ----------------- */
$statusOptions = ['Pending', 'Approved', 'Rejected', 'All'];
$statusRaw = isset($_GET['status']) ? (string) $_GET['status'] : 'Pending';
$statusFilter = ucfirst(strtolower($statusRaw));
if (!in_array($statusFilter, $statusOptions, true)) $statusFilter = 'Pending';

/* ----------------- Filters: Role ----------------- */
/**
 * role in URL: driver/helper/supervisor/all
 * default: supervisor (your previous behavior)
 */
$roleOptions = ['driver','helper','supervisor','all'];
$roleRaw = strtolower(trim((string)($_GET['role'] ?? 'supervisor')));
if (!in_array($roleRaw, $roleOptions, true)) $roleRaw = 'supervisor';
$roleFilterServer = $roleRaw; // used for default active pill + API param if supported

/* ----------------- Filters: Date (From / To) ----------------- */
$fromRaw = isset($_GET['from']) ? trim((string) $_GET['from']) : '';
$toRaw   = isset($_GET['to'])   ? trim((string) $_GET['to'])   : '';

$today = new DateTimeImmutable('today');

if ($fromRaw === '' && $toRaw === '') {
    $firstOfMonth = $today->modify('first day of this month');
    $lastOfMonth  = $today->modify('last day of this month');
    $fromDateObj = $firstOfMonth;
    $toDateObj   = $lastOfMonth;
} else {
    $fromDateObj = DateTimeImmutable::createFromFormat('Y-m-d', $fromRaw) ?: $today->modify('-29 days');
    $toDateObj   = DateTimeImmutable::createFromFormat('Y-m-d', $toRaw)   ?: $today;

    if ($fromDateObj > $toDateObj) {
        $tmp         = $fromDateObj;
        $fromDateObj = $toDateObj;
        $toDateObj   = $tmp;
    }
}

$fromDate  = $fromDateObj->format('Y-m-d');
$toDate    = $toDateObj->format('Y-m-d');
$rangeDays = $fromDateObj->diff($toDateObj)->days + 1;

/* ----------------- Filters: Plant ----------------- */
$plantFilter = isset($_GET['plantId']) ? (int) $_GET['plantId'] : null;
if ($plantFilter !== null && $plantFilter <= 0) $plantFilter = null;

/* ----------------- Search term (for preservation) ----------------- */
$searchTerm = isset($_GET['search']) ? trim((string) $_GET['search']) : '';

/* ----------------- Data load ----------------- */
$plantOptions      = [];
$approvals         = [];
$missingAttendance = [];
$fetchError        = null;
$statusCounts      = ['Pending' => 0, 'Approved' => 0, 'Rejected' => 0];

try {
    $plantStmt = $conn->query('SELECT id, plant_name FROM plants ORDER BY plant_name ASC');
    while ($row = $plantStmt->fetch_assoc()) {
        $plantOptions[] = [
            'id'   => (int) $row['id'],
            'name' => $row['plant_name'],
        ];
    }
    $plantStmt->close();
} catch (Throwable $e) {
    $fetchError = 'Unable to load plant list: ' . $e->getMessage();
}

if ($currentUserId <= 0 && isset($_GET['adminUserId'])) {
    $currentUserId   = (int) $_GET['adminUserId'];
    $currentUserName = 'Admin #' . $currentUserId;
}

if (!$fetchError && $currentUserId <= 0) {
    $fetchError = 'Please sign in through the admin portal to review approvals.';
}

if (!$fetchError) {
    $statusForApi = strtoupper($statusFilter); // PENDING/APPROVED/REJECTED/ALL
    $plantForApi  = $plantFilter ? (string) $plantFilter : '0';

    /**
     * IMPORTANT:
     * If your API supports role filtering, we pass it.
     * If API ignores it, no problem (client-side filter still works).
     */
    $apiParams = [
        'adminUserId' => $currentUserId,
        'status'      => $statusForApi,
        'fromDate'    => $fromDate,
        'toDate'      => $toDate,
        'plantId'     => $plantForApi,
        'role'        => strtoupper($roleFilterServer), // DRIVER/HELPER/SUPERVISOR/ALL
    ];

    $scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
    $host   = $_SERVER['HTTP_HOST'] ?? 'localhost';
    $apiUrl = sprintf('%s://%s/api/mobile/attendance_admin_supervisor_approvals.php', $scheme, $host);

    $ch = curl_init($apiUrl . '?' . http_build_query($apiParams));
    if ($ch === false) {
        $fetchError = 'Unable to initialize approvals API request.';
    } else {
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 15);
        $apiResponse = curl_exec($ch);
        if ($apiResponse === false) {
            $fetchError = 'Failed to contact approvals API: ' . curl_error($ch);
        } else {
            $statusCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            $payload    = json_decode($apiResponse, true);
            if (!is_array($payload)) {
                $fetchError = 'Invalid response from approvals API (status ' . $statusCode . ').';
            } elseif ($statusCode >= 300 || ($payload['status'] ?? '') !== 'ok') {
                $fetchError = $payload['error'] ?? 'Approvals API returned an error.';
            } else {
                $approvals         = $payload['approvals'] ?? [];
                $plantsMeta        = $payload['plants'] ?? [];
                $missingAttendance = $payload['missingAttendance'] ?? [];

                // merge any plants from API
                if (!empty($plantsMeta)) {
                    $apiPlantMap = [];
                    foreach ($plantsMeta as $item) {
                        $pid = isset($item['plantId']) ? (int) $item['plantId'] : (int) ($item['id'] ?? 0);
                        if ($pid <= 0) continue;
                        $apiPlantMap[$pid] = [
                            'id'   => $pid,
                            'name' => $item['plantName'] ?? $item['plant_name'] ?? ('Plant ' . $pid),
                        ];
                    }
                    if (!empty($apiPlantMap)) {
                        $existingMap = [];
                        foreach ($plantOptions as $plant) {
                            $existingMap[(int) $plant['id']] = $plant;
                        }
                        foreach ($apiPlantMap as $pid => $plant) {
                            $existingMap[$pid] = $plant;
                        }
                        ksort($existingMap);
                        $plantOptions = array_values($existingMap);
                    }
                }

                // Normalize statuses and count + normalize role for filters
                foreach ($approvals as &$entry) {
                    $status = ucfirst(strtolower(trim((string) ($entry['status'] ?? 'Pending'))));
                    if (!in_array($status, ['Pending','Approved','Rejected'], true)) {
                        $status = 'Pending';
                    }
                    $entry['status'] = $status;
                    $statusCounts[$status] = ($statusCounts[$status] ?? 0) + 1;

                    $rawRole = strtolower(trim((string)($entry['role'] ?? '')));
                    if ($rawRole === '' || $rawRole === 'driver' || $rawRole === 'drivers') {
                        $role = 'Driver';
                    } elseif ($rawRole === 'helper' || $rawRole === 'helpers' || $rawRole === 'assistant' || $rawRole === 'asst' || $rawRole === 'attendant') {
                        $role = 'Helper';
                    } elseif ($rawRole === 'supervisor' || $rawRole === 'supervisors') {
                        $role = 'Supervisor';
                    } else {
                        $role = 'Driver';
                    }
                    $entry['role'] = $role;
                }
                unset($entry);

                foreach ($missingAttendance as &$person) {
                    $rawRole = strtolower(trim((string)($person['role'] ?? '')));
                    if ($rawRole === '' || $rawRole === 'driver' || $rawRole === 'drivers') {
                        $role = 'Driver';
                    } elseif ($rawRole === 'helper' || $rawRole === 'helpers' || $rawRole === 'assistant' || $rawRole === 'asst' || $rawRole === 'attendant') {
                        $role = 'Helper';
                    } elseif ($rawRole === 'supervisor' || $rawRole === 'supervisors') {
                        $role = 'Supervisor';
                    } else {
                        $role = 'Driver';
                    }
                    $person['role'] = $role;
                }
                unset($person);
            }
        }
        curl_close($ch);
    }
}

$rangeLabel = sprintf(
    'Showing records from %s to %s (%d day%s)',
    $fromDate,
    $toDate,
    $rangeDays,
    $rangeDays === 1 ? '' : 's'
);

$selectedPlantName = null;
if ($plantFilter) {
    foreach ($plantOptions as $plant) {
        if ((int) $plant['id'] === $plantFilter) {
            $selectedPlantName = $plant['name'];
            break;
        }
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title> Attendance Approvals</title>

<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet" />
<link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet" />
<link href="/DriverDocs/assets/css/custom.css" rel="stylesheet" />
<link rel="icon" href="/images/logo_new.png" type="image/x-icon" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Josefin+Sans:wght@300;400;500;600;700&display=swap" rel="stylesheet">

<style>
body{
    margin:0;
    background:#f5f6f8;
    font-family:'Josefin Sans',system-ui,sans-serif;
    padding-top:56px;
}
.page-gutter{ padding:6px 12px 0; }
.header-blue{ background:#cfe2ff; border:1px solid #9ec5fe; border-radius:10px; }
.page-header {
    margin-bottom: 1.5rem;
    margin-left: .8rem;
}
@media (min-width:768px){
    .page-header { margin-left: 1.4rem; }
}
.page-header h1 {
    letter-spacing: 0.02em;
    color:#0f172a;
}
.filters-card {
    border-radius: 18px;
    box-shadow: 0 10px 24px rgba(15, 23, 42, 0.07);
    border: none;
}
.approvals-card,
.missing-card {
    border-radius: 16px;
    border: none;
    box-shadow: 0 8px 22px rgba(15, 23, 42, 0.06);
}
.stats-card {
    border-radius: 18px;
    padding: 1.3rem 1.6rem;
    color: white;
    position: relative;
    overflow: hidden;
}
.stats-card::after {
    content:'';
    position:absolute;
    inset:-40%;
    opacity:0.18;
    background:radial-gradient(circle at 0 0, #ffffff, transparent 55%),
               radial-gradient(circle at 100% 100%, #ffffff, transparent 55%);
}
.stats-card p {
    margin: 0;
    text-transform: uppercase;
    letter-spacing: .08em;
    font-size: .72rem;
    opacity: 0.9;
}
.stats-card h3 {
    font-size: 1.7rem;
    margin: .5rem 0 0;
}
.avatar {
    width: 44px;
    height: 44px;
    border-radius: 50%;
    background-color: #e3f2fd;
    background-position: center;
    background-size: cover;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    font-weight: 600;
    color: #0d47a1;
    font-size: .9rem;
}
.table thead {
    background-color: #eff4fb;
}
.table thead th {
    border: none;
    font-size: .78rem;
    text-transform: uppercase;
    letter-spacing: .08em;
    color: #64748b;
}
.table thead th.sortable {
    cursor: pointer;
    user-select: none;
}
.table thead th.sortable::after {
    content: '⇅';
    font-size: .65rem;
    margin-left: .35rem;
    opacity: 0.6;
}
.table thead th.sortable[data-sort-dir="asc"]::after { content: '↑'; }
.table thead th.sortable[data-sort-dir="desc"]::after { content: '↓'; }
.table tbody td {
    vertical-align: middle;
    font-size: .9rem;
}
.role-toggle {
    border-radius: 999px;
    background: #e5edff;
    padding: 4px;
    display: inline-flex;
    gap: 4px;
}
.role-pill {
    border-radius: 999px;
    border: none;
    padding: 6px 14px;
    font-size: .8rem;
    text-transform: uppercase;
    letter-spacing: .08em;
    background: transparent;
    color: #1e293b;
    cursor: pointer;
}
.role-pill.active {
    background: #0f172a;
    color: #f9fafb;
    box-shadow: 0 10px 20px rgba(15, 23, 42, 0.35);
}
.badge-pending-checkout {
    background: #fee2e2;
    color: #b91c1c;
    border-radius: 999px;
    padding: 4px 10px;
    font-size: .75rem;
    font-weight: 600;
    animation: pulse-tag 1.4s infinite;
}
@keyframes pulse-tag {
    0%   { transform: scale(1); box-shadow: 0 0 0 0 rgba(248,113,113,0.6); }
    50%  { transform: scale(1.04); box-shadow: 0 0 0 10px rgba(248,113,113,0); }
    100% { transform: scale(1); box-shadow: 0 0 0 0 rgba(248,113,113,0); }
}
.photo-links a { text-decoration: none; }
.section-title { font-size: 1rem; font-weight: 600; }

/* minimal side space in full layout */
body > .container-fluid.page-wrapper { padding-left: 0.5rem; padding-right: 0.5rem; }

/* main inner – extra side space so header not on edge */
main.main > .container-fluid { padding-left: .75rem; padding-right: .75rem; }
@media (min-width:992px){
    main.main > .container-fluid { padding-left: 1.75rem; padding-right: 1.75rem; }
}

/* Grow effect for attendance submissions search bar */
#table-search-input { transition: transform 0.18s ease, box-shadow 0.18s ease; }
#table-search-input:focus { transform: scale(1.03); box-shadow: 0 0 0 3px rgba(59,130,246,0.3); }

/* Small floating preview window on hover */
.photo-hover-preview {
    position: fixed;
    z-index: 1050;
    pointer-events: none;
    background: #ffffff;
    border-radius: 12px;
    box-shadow: 0 12px 30px rgba(15, 23, 42, 0.35);
    padding: 6px;
    max-width: 260px;
    max-height: 260px;
    border: 1px solid rgba(148, 163, 184, 0.6);
}
.photo-hover-preview img {
    display: block;
    max-width: 100%;
    max-height: 240px;
    object-fit: contain;
    border-radius: 8px;
}

/* ================= Mobile-friendly Attendance table, 2-column card ================= */
@media (max-width: 767.98px) {
    .mobile-card-table thead { display: none; }
    .mobile-card-table, .mobile-card-table tbody { display: block; width: 100%; }

    .mobile-card-table tr[data-row-type="approval"] {
        display: grid !important;
        grid-template-columns: minmax(0,1.1fr) minmax(0,0.9fr);
        gap: 10px 14px;
        margin: 0.75rem 0;
        padding: 0.9rem 0.9rem;
        border-radius: 16px;
        background: linear-gradient(135deg,#f1f5f9,#e0f2fe);
        box-shadow: 0 8px 20px rgba(15, 23, 42, 0.07);
        border: 1px solid rgba(148, 163, 184, 0.25);
    }
    .mobile-card-table tr[data-row-type="approval"]:last-child { margin-bottom: 0; }
    .mobile-card-table td { padding: 0 !important; border: none !important; }
    .mobile-card-table td::before {
        content: attr(data-label);
        display: block;
        font-size: 0.68rem;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        color: #94a3b8;
        margin-bottom: 0.12rem;
    }
    .mobile-card-table td[data-label="Person"] {
        grid-column: 1 / span 2;
        padding-bottom: 0.5rem !important;
        margin-bottom: 0.4rem;
        border-bottom: 1px dashed #cbd5f5 !important;
    }
    .mobile-card-table td[data-label="Person"]::before { content: ''; display: none; }

    .mobile-card-table td[data-label="Notes"],
    .mobile-card-table td[data-label="Actions"] {
        grid-column: 1 / span 2;
        margin-top: 0.35rem;
    }
    .mobile-card-table td[data-label="Actions"] { margin-top: 0.6rem; }
    .mobile-card-table td[data-label="Person"] .avatar { width: 40px; height: 40px; }
    .approvals-card .card-body { padding: 0.5rem; }
    .approvals-card .table-responsive { border-radius: 14px; background: transparent; }
}

/* Tighter vertical padding for approvals table rows */
.approvals-card .table > :not(caption) > * > * { padding-top: 0.35rem; padding-bottom: 0.35rem; }

/* ================= Compact mode (reduce padding everywhere) ================= */
.page-header { margin-bottom: .75rem; margin-left: .5rem; }
@media (min-width:768px){ .page-header { margin-left: .75rem; } }
.page-header h1 { font-size: .88rem; }

body > .container-fluid.page-wrapper { padding-left: .35rem; padding-right: .35rem; }
main.main > .container-fluid { padding-left: .5rem; padding-right: .5rem; }
@media (min-width:992px){
    main.main > .container-fluid { padding-left: 1rem; padding-right: 1rem; }
}

.filters-card, .approvals-card, .missing-card { border-radius: 14px; }
.card .card-header { padding: .45rem .7rem; }
.filters-card .card-body { padding: .6rem .7rem; }
.approvals-card .card-body, .missing-card .card-body { padding: 0; }

/* Stats widgets */
.row.g-3 { --bs-gutter-x: .65rem; --bs-gutter-y: .65rem; }
.stats-card { padding: .72rem .85rem; border-radius: 16px; }
.stats-card p { font-size: .68rem; letter-spacing: .06em; }
.stats-card h3 { font-size: 1.22rem; margin-top: .28rem; }

/* Filters */
.filters-card .row { --bs-gutter-x: .55rem; --bs-gutter-y: .55rem; }
.filters-card .form-label { font-size: .76rem; margin-bottom: .15rem; }
.filters-card .form-control, .filters-card .form-select { font-size: .85rem; padding: .3rem .45rem; border-radius: .65rem; }
.filters-card .btn { padding: .35rem .6rem; font-size: .85rem; border-radius: .65rem; }
.role-toggle { padding: 3px; gap: 3px; }
.role-pill { padding: 5px 10px; font-size: .74rem; line-height: 1.1; }
.page-header .input-group-text { font-size: .78rem; padding: .26rem .45rem; }
.page-header .form-control, .page-header .form-select { font-size: .84rem; padding: .26rem .45rem; border-radius: .65rem; }

/* Search bar: remove aggressive grow */
#table-search-input { transition: box-shadow 0.12s ease; }
#table-search-input:focus { transform: none; box-shadow: 0 0 0 2px rgba(59,130,246,0.22); }

/* Tables */
.table thead th { font-size: .74rem; padding: .35rem .45rem; }
.table tbody td { font-size: .86rem; padding: .28rem .45rem; }
.approvals-card .table > :not(caption) > * > * { padding: .28rem .45rem; }
.missing-card .table > :not(caption) > * > * { padding: .28rem .45rem; }

/* Photo buttons (IN/OUT) compact */
.photo-links .btn.btn-sm {
    font-size: .72rem;
    padding: .18rem .4rem;
    line-height: 1.1;
}
</style>
</head>
<body>
<?php
// Go from /public_html/api/mobile → /public_html → /public_html/DriverDocs/includes
$driverDocsBase = dirname(__DIR__, 2) . '/DriverDocs';
include $driverDocsBase . '/includes/navbar.php';
?>
<div class="page-gutter">
<div class="container-fluid page-wrapper">
  <div class="row">
    <?php include $driverDocsBase . '/includes/sidebar.php'; ?>

    <main class="main col-md-9 col-lg-10">
      <div class="container-fluid py-1">

        <div class="pt-2 pb-2 mb-3 border rounded header-blue">
            <div class="d-flex flex-wrap align-items-center gap-2 px-2">
                <div class="d-flex align-items-center gap-2">
                    <button type="button" class="btn btn-sm btn-outline-secondary" id="toggleSidebarBtn" aria-label="Toggle sidebar" aria-pressed="false">
                        <i class="fas fa-bars"></i>
                    </button>
                    <i class="fas fa-clipboard-check"></i>
                    <h1 class="h6 mb-0 text-uppercase text-muted" style="letter-spacing:.06em;">Attendance Approvals</h1>
                </div>

                <form method="get"
                      id="filters-form"
                      class="d-flex flex-wrap align-items-center gap-2 ms-auto">

                    <div class="role-toggle">
                        <button type="button" class="role-pill <?= $roleFilterServer==='driver' ? 'active':'' ?>" data-role="driver">Drivers</button>
                        <button type="button" class="role-pill <?= $roleFilterServer==='helper' ? 'active':'' ?>" data-role="helper">Helpers</button>
                        <button type="button" class="role-pill <?= $roleFilterServer==='supervisor' ? 'active':'' ?>" data-role="supervisor">Supervisors</button>
                        <button type="button" class="role-pill <?= $roleFilterServer==='all' ? 'active':'' ?>" data-role="all">All</button>
                    </div>

                    <div class="input-group input-group-sm" style="width:auto; min-width:170px;">
                        <span class="input-group-text">Status</span>
                        <select class="form-select" name="status" id="status-select">
                            <?php foreach ($statusOptions as $option): ?>
                                <option value="<?= h($option) ?>" <?= $statusFilter === $option ? 'selected' : '' ?>><?= h($option) ?></option>
                            <?php endforeach; ?>
                        </select>
                    </div>

                    <div class="input-group input-group-sm" style="width:auto; min-width:210px;">
                        <span class="input-group-text">Plant</span>
                        <select class="form-select" name="plantId" id="plant-select">
                            <option value="">All</option>
                            <?php foreach ($plantOptions as $plant): ?>
                                <option value="<?= h((string) $plant['id']) ?>" <?= $plantFilter === (int) $plant['id'] ? 'selected' : '' ?>><?= h($plant['name']) ?></option>
                            <?php endforeach; ?>
                        </select>
                    </div>

                    <div class="input-group input-group-sm" style="width:auto">
                        <span class="input-group-text">From</span>
                        <input type="date" class="form-control" name="from" id="from-date" value="<?= h($fromDate) ?>">
                    </div>

                    <div class="input-group input-group-sm" style="width:auto">
                        <span class="input-group-text">To</span>
                        <input type="date" class="form-control" name="to" id="to-date" value="<?= h($toDate) ?>">
                    </div>

                    <button type="button" class="btn btn-sm btn-outline-primary" id="prevMonthBtn" title="Previous month">
                        <i class="fa-regular fa-calendar"></i> Prev month
                    </button>
                    <button type="button" class="btn btn-sm text-dark" id="currentMonthBtn" title="Current month" style="background:#87CEFA; border-color:#87CEFA;">
                        <i class="fa-regular fa-calendar-check"></i> Current month
                    </button>

                    <input type="hidden" name="search" id="search-hidden" value="<?= h($searchTerm) ?>">
                    <input type="hidden" name="role" id="role-hidden" value="<?= h($roleFilterServer) ?>">
                </form>
            </div>
        </div>

        <div class="page-header">
            <div class="text-muted small mt-2">
                <?= h($rangeLabel) ?>
                <?php if ($selectedPlantName): ?>
                    · <?= h($selectedPlantName) ?>
                <?php endif; ?>
                · Role: <span class="fw-semibold"><?= h(strtoupper($roleFilterServer)) ?></span>
            </div>
        </div>

        <?php if ($flash): ?>
            <div class="alert alert-<?= h($flash['type']) ?> alert-dismissible fade show" role="alert">
                <?= h($flash['message']) ?>
                <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
            </div>
        <?php endif; ?>

        <?php if ($fetchError): ?>
            <div class="alert alert-danger">
                Failed to load approvals: <?= h($fetchError) ?>
            </div>
        <?php endif; ?>

        <div class="row g-3 mb-4">
            <div class="col-md-4">
                <div class="stats-card" style="background: linear-gradient(135deg,#fb923c,#f97316,#facc15);">
                    <p>Pending</p>
                    <h3 id="pending-count"><?= h((string) ($statusCounts['Pending'] ?? 0)) ?></h3>
                </div>
            </div>
            <div class="col-md-4">
                <div class="stats-card" style="background: linear-gradient(135deg,#22c55e,#16a34a,#0f766e);">
                    <p>Approved</p>
                    <h3 id="approved-count"><?= h((string) ($statusCounts['Approved'] ?? 0)) ?></h3>
                </div>
            </div>
            <div class="col-md-4">
                <div class="stats-card" style="background: linear-gradient(135deg,#ef4444,#f97316,#f59e0b);">
                    <p>Rejected</p>
                    <h3 id="rejected-count"><?= h((string) ($statusCounts['Rejected'] ?? 0)) ?></h3>
                </div>
            </div>
        </div>

        <div id="photoHoverPreview" class="photo-hover-preview d-none">
            <img id="photoHoverImg" src="" alt="Attendance photo preview">
        </div>

        <div class="card approvals-card mb-4">
            <div class="card-header bg-white d-flex flex-column flex-md-row justify-content-between align-items-md-center gap-2">
                <div class="d-flex align-items-center justify-content-between w-100 w-md-auto">
                    <h2 class="h6 mb-0 text-uppercase text-muted">Attendance submissions</h2>
                    <span class="text-muted small d-md-none" id="total-count-mobile">
                        Total: <?= h((string) count($approvals)) ?>
                    </span>
                </div>
                <div class="w-100 w-md-50">
                    <input type="text"
                           id="table-search-input"
                           name="search"
                           class="form-control form-control-sm"
                           placeholder="Search within attendance submissions (name, plant, vehicle, status, notes)"
                           value="<?= h($searchTerm) ?>">
                </div>
                <span class="text-muted small d-none d-md-inline" id="total-count-desktop">
                    Total listed: <?= h((string) count($approvals)) ?>
                </span>
            </div>
            <div class="card-body p-0">
                <?php if (empty($approvals)): ?>
                    <div class="p-5 text-center text-muted">
                        No attendance submissions match the selected window.
                    </div>
                <?php else: ?>
                    <div class="table-responsive">
                        <table class="table align-middle mb-0 mobile-card-table">
                            <thead>
                            <tr>
                                <th class="sortable" data-sort="person">Person</th>
                                <th class="sortable" data-sort="plant">Plant &amp; Vehicle</th>
                                <th class="sortable" data-sort="date">In / Out</th>
                                <th>Working Hours</th>
                                <th>Photos</th>
                                <th class="sortable" data-sort="status">Status</th>
                                <th class="sortable" data-sort="notes">Notes</th>
                                <th>Actions</th>
                            </tr>
                            </thead>
                            <tbody id="approvals-tbody">
                            <?php foreach ($approvals as $approval): ?>
                                <?php
                                $roleLabel = (string) ($approval['role'] ?? 'Driver'); // already normalized
                                $roleSlug  = strtolower($roleLabel); // driver/helper/supervisor
                                $plantId   = isset($approval['plantId']) ? (int) $approval['plantId'] : 0;

                                $attendanceDate = '';
                                $sortDateKey    = '';
                                if (!empty($approval['inTime'])) {
                                    try {
                                        $dt = new DateTime($approval['inTime']);
                                        $attendanceDate = $dt->format('Y-m-d');
                                        $sortDateKey    = $dt->format('Y-m-d H:i:s');
                                    } catch (Throwable $e) {}
                                } elseif (!empty($approval['outTime'])) {
                                    try {
                                        $dt = new DateTime($approval['outTime']);
                                        $attendanceDate = $dt->format('Y-m-d');
                                        $sortDateKey    = $dt->format('Y-m-d H:i:s');
                                    } catch (Throwable $e) {}
                                }
                                if ($attendanceDate === '' && !empty($approval['attendanceDate'])) {
                                    try {
                                        $dt = new DateTime($approval['attendanceDate']);
                                        $attendanceDate = $dt->format('Y-m-d');
                                        if ($sortDateKey === '') $sortDateKey = $dt->format('Y-m-d 00:00:00');
                                    } catch (Throwable $e) {}
                                }

                                $hasCheckout = !empty($approval['outTime']);
                                $driverName  = (string) ($approval['driverName'] ?? '');
                                $plantName   = (string) ($approval['plantName'] ?? '');
                                $notesRaw    = (string) ($approval['notes'] ?? '');
                                $statusNorm  = ucfirst(strtolower(trim((string) ($approval['status'] ?? 'Pending'))));
                                if (!in_array($statusNorm, ['Pending','Approved','Rejected'], true)) $statusNorm = 'Pending';

                                $workingHours = formatWorkingHours($approval['inTime'] ?? null, $approval['outTime'] ?? null);
                                $differentDates = isDifferentInOutDate($approval['inTime'] ?? null, $approval['outTime'] ?? null);

                                $vehicleText = (string) ($approval['vehicleNumber'] ?? '');
                                $statusLower = mb_strtolower($statusNorm);
                                ?>
<tr
    data-row-type="approval"
    data-status="<?= h(strtolower($statusNorm)) ?>"
    data-role="<?= h($roleSlug) ?>"
    data-plant-id="<?= h((string)$plantId) ?>"
    data-date="<?= h($attendanceDate) ?>"
    data-person="<?= h(mb_strtolower($driverName)) ?>"
    data-plant="<?= h(mb_strtolower($plantName)) ?>"
    data-notes="<?= h(mb_strtolower($notesRaw)) ?>"
    data-status-sort="<?= h($statusLower) ?>"
    data-date-sort="<?= h($sortDateKey) ?>"
    data-name="<?= h(mb_strtolower($driverName)) ?>"
    data-vehicle="<?= h(mb_strtolower($vehicleText)) ?>"
    data-status-label="<?= h($statusLower) ?>"
>
    <td data-label="Person">
        <div class="d-flex align-items-center gap-3">
            <?php if (!empty($approval['profilePhoto'])): ?>
                <span class="avatar" style="background-image: url('<?= h($approval['profilePhoto']) ?>');"></span>
            <?php else: ?>
                <span class="avatar"><?= h(strtoupper(mb_substr((string)$driverName, 0, 1))) ?></span>
            <?php endif; ?>
            <div>
                <div class="fw-semibold"><?= h($driverName) ?></div>
                <div class="text-muted small">
                    #<?= h((string) $approval['driverId']) ?> · <?= h($roleLabel) ?>
                </div>
            </div>
        </div>
    </td>

    <td data-label="Plant &amp; Vehicle">
        <div class="fw-semibold"><?= h($plantName) ?></div>
        <div class="text-muted small">
            <?= h($vehicleText !== '' ? $vehicleText : 'Vehicle TBD') ?>
        </div>
    </td>

    <td data-label="In / Out" class="<?= $differentDates ? 'text-danger fw-semibold' : '' ?>">
        <div class="small d-flex flex-wrap align-items-center gap-2">
            <span class="text-muted">IN:</span>
            <span><?= h(formatDateTime($approval['inTime'])) ?></span>

            <span class="text-muted ms-3">OUT:</span>
            <span><?= h($approval['outTime'] ? formatDateTime($approval['outTime']) : '—') ?></span>
        </div>
    </td>

    <td data-label="Working Hours">
        <span class="small"><?= h($workingHours) ?></span>
    </td>

    <td class="photo-links" data-label="Photos">
        <div class="d-flex flex-column gap-2">
            <?php if (!empty($approval['inPhotoUrl'])): ?>
                <a class="btn btn-sm btn-outline-primary"
                   href="<?= h($approval['inPhotoUrl']) ?>"
                   data-photo-url="<?= h($approval['inPhotoUrl']) ?>">
                    IN
                </a>
            <?php endif; ?>
            <?php if (!empty($approval['outPhotoUrl'])): ?>
                <a class="btn btn-sm btn-outline-primary"
                   href="<?= h($approval['outPhotoUrl']) ?>"
                   data-photo-url="<?= h($approval['outPhotoUrl']) ?>">
                    OUT
                </a>
            <?php endif; ?>
            <?php if (empty($approval['inPhotoUrl']) && empty($approval['outPhotoUrl'])): ?>
                <span class="text-muted small">—</span>
            <?php endif; ?>
        </div>
    </td>

    <td data-label="Status">
        <span class="badge text-bg-<?= statusBadgeClass($statusNorm) ?>">
            <?= h($statusNorm) ?>
        </span>
        <div class="text-muted small mt-1">
            Source: <?= h(strtoupper($approval['source'] ?? 'mobile')) ?>
        </div>
    </td>

    <td class="small" data-label="Notes">
        <?= $notesRaw !== '' ? nl2br(h($notesRaw)) : '<span class="text-muted">—</span>' ?>
    </td>

    <td data-label="Actions">
        <?php if (!$hasCheckout): ?>
            <span class="badge-pending-checkout">Pending checkout</span>
        <?php else: ?>
            <form method="post" class="d-flex flex-column flex-lg-row gap-2 align-items-stretch" data-approval-form="1">
                <input type="hidden" name="attendance_id" value="<?= h((string) $approval['attendanceId']) ?>">
                <input type="hidden" name="csrf_token" value="<?= h($csrfToken) ?>">
                <input type="text" name="notes" class="form-control form-control-sm" placeholder="Optional note">
                <div class="d-flex gap-2">
                    <button class="btn btn-sm btn-outline-success"
                            type="submit" name="action" value="approve"
                            <?= strtolower($statusNorm) === 'approved' ? 'disabled' : '' ?>>
                        Approve
                    </button>
                    <button class="btn btn-sm btn-outline-danger"
                            type="submit" name="action" value="reject"
                            <?= strtolower($statusNorm) === 'rejected' ? 'disabled' : '' ?>>
                        Reject
                    </button>
                </div>
            </form>
        <?php endif; ?>
    </td>
</tr>
                            <?php endforeach; ?>
                            </tbody>
                        </table>
                    </div>
                <?php endif; ?>
            </div>
        </div>

        <div class="card missing-card">
            <div class="card-header bg-white">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h2 class="h6 mb-0 text-uppercase text-muted">No attendance recorded</h2>
                        <div class="text-muted small">
                            Based on <?= h($rangeLabel) ?><?php if ($selectedPlantName) echo ' · ' . h($selectedPlantName); ?>
                        </div>
                    </div>
                    <span class="badge bg-dark-subtle text-dark small">
                        <?= h((string) count($missingAttendance)) ?> person(s)
                    </span>
                </div>
            </div>
            <div class="card-body p-0">
                <?php if (empty($missingAttendance)): ?>
                    <div class="p-4 text-center text-muted">
                        Everyone has marked attendance for the selected window.
                    </div>
                <?php else: ?>
                    <div class="table-responsive">
                        <table class="table align-middle mb-0">
                            <thead>
                            <tr>
                                <th>Person</th>
                                <th>Role</th>
                                <th>Plant</th>
                            </tr>
                            </thead>
                            <tbody id="missing-tbody">
                            <?php foreach ($missingAttendance as $person): ?>
                                <?php
                                $mRole     = (string) ($person['role'] ?? 'Driver');
                                $mRoleSlug = strtolower($mRole);
                                $mPlantId  = isset($person['plantId']) ? (int) $person['plantId'] : 0;
                                $mName     = (string) ($person['name'] ?? '');
                                ?>
                                <tr
                                    data-row-type="missing"
                                    data-role="<?= h($mRoleSlug) ?>"
                                    data-plant-id="<?= h((string)$mPlantId) ?>"
                                    data-name="<?= h(mb_strtolower($mName)) ?>"
                                >
                                    <td class="fw-semibold"><?= h($mName) ?></td>
                                    <td><?= h($mRole) ?></td>
                                    <td><?= h($person['plantName']) ?></td>
                                </tr>
                            <?php endforeach; ?>
                            </tbody>
                        </table>
                    </div>
                <?php endif; ?>
            </div>
        </div>

      </div>
    </main>
  </div>
</div>
</div>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
<script>
document.addEventListener('DOMContentLoaded', function () {
    const statusSelect  = document.getElementById('status-select');
    const plantSelect   = document.getElementById('plant-select');
    const fromInput     = document.getElementById('from-date');
    const toInput       = document.getElementById('to-date');
    const rolePills     = document.querySelectorAll('.role-pill');
    const tableSearch   = document.getElementById('table-search-input');
    const filtersForm   = document.getElementById('filters-form');
    const searchHidden  = document.getElementById('search-hidden');
    const roleHidden    = document.getElementById('role-hidden');
    const prevMonthBtn  = document.getElementById('prevMonthBtn');
    const currentMonthBtn = document.getElementById('currentMonthBtn');

    const approvalsTbody = document.getElementById('approvals-tbody');
    const photoHoverPreview = document.getElementById('photoHoverPreview');
    const photoHoverImg     = document.getElementById('photoHoverImg');

    const pendingCountEl  = document.getElementById('pending-count');
    const approvedCountEl = document.getElementById('approved-count');
    const rejectedCountEl = document.getElementById('rejected-count');
    const totalMobileEl   = document.getElementById('total-count-mobile');
    const totalDesktopEl  = document.getElementById('total-count-desktop');

    let currentSortKey = null;
    let currentSortDir = 'asc';

    // IMPORTANT: default role comes from server (URL) so it persists on refresh
    let roleFilter = (roleHidden?.value || 'supervisor').toLowerCase();

    function recalcStatsAndTotals() {
        const rows = document.querySelectorAll('tr[data-row-type="approval"]');
        let pending = 0, approved = 0, rejected = 0;
        let visible = 0;

        rows.forEach(row => {
            const st = (row.dataset.statusLabel || '').toLowerCase();
            if (st === 'pending')  pending++;
            if (st === 'approved') approved++;
            if (st === 'rejected') rejected++;

            if (row.style.display !== 'none') visible++;
        });

        if (pendingCountEl)  pendingCountEl.textContent  = pending;
        if (approvedCountEl) approvedCountEl.textContent = approved;
        if (rejectedCountEl) rejectedCountEl.textContent = rejected;

        if (totalMobileEl)   totalMobileEl.textContent  = 'Total: ' + visible;
        if (totalDesktopEl)  totalDesktopEl.textContent = 'Total listed: ' + visible;
    }

    function applyFilters() {
        const tableSearchVal = (tableSearch?.value || '').trim().toLowerCase();
        const currentStatusFilter = (statusSelect?.value || 'Pending').toLowerCase();

        const rows = document.querySelectorAll('tr[data-row-type]');
        rows.forEach(row => {
            let show = true;

            const rowType    = row.dataset.rowType || '';
            const rowRole    = (row.dataset.role || '').toLowerCase();
            const rowName    = (row.dataset.name || '').toLowerCase();
            const rowPlant   = (row.dataset.plant || '').toLowerCase();
            const rowVehicle = (row.dataset.vehicle || '').toLowerCase();
            const rowNotes   = (row.dataset.notes || '').toLowerCase();
            const rowStatusLabel = (row.dataset.statusLabel || '').toLowerCase();

            // Role filter: driver/helper/supervisor/all
            if (roleFilter && roleFilter !== 'all') {
                if (rowRole !== roleFilter) show = false;
            }

            // Status filter only on approvals
            if (rowType === 'approval' && currentStatusFilter !== 'all') {
                if (rowStatusLabel !== currentStatusFilter) show = false;
            }

            // Search only on approvals
            if (rowType === 'approval' && tableSearchVal) {
                const haystack = [rowName, rowPlant, rowVehicle, rowNotes, rowStatusLabel].join(' ');
                if (!haystack.includes(tableSearchVal)) show = false;
            }

            row.style.display = show ? '' : 'none';
        });

        recalcStatsAndTotals();
    }

    function sortApprovals(sortKey) {
        if (!approvalsTbody) return;

        if (currentSortKey === sortKey) {
            currentSortDir = (currentSortDir === 'asc') ? 'desc' : 'asc';
        } else {
            currentSortKey = sortKey;
            currentSortDir = 'asc';
        }

        const rows = Array.from(approvalsTbody.querySelectorAll('tr[data-row-type="approval"]'));

        rows.sort((a, b) => {
            let aVal = '', bVal = '';

            if (sortKey === 'person') {
                aVal = (a.dataset.person || '').toLowerCase();
                bVal = (b.dataset.person || '').toLowerCase();
            } else if (sortKey === 'plant') {
                aVal = (a.dataset.plant || '').toLowerCase();
                bVal = (b.dataset.plant || '').toLowerCase();
            } else if (sortKey === 'status') {
                aVal = (a.dataset.statusSort || '').toLowerCase();
                bVal = (b.dataset.statusSort || '').toLowerCase();
            } else if (sortKey === 'notes') {
                aVal = (a.dataset.notes || '').toLowerCase();
                bVal = (b.dataset.notes || '').toLowerCase();
            } else if (sortKey === 'date') {
                aVal = a.dataset.dateSort || '';
                bVal = b.dataset.dateSort || '';
            }

            const cmp = aVal.localeCompare(bVal, undefined, { numeric: true, sensitivity: 'base' });
            return currentSortDir === 'asc' ? cmp : -cmp;
        });

        rows.forEach(r => approvalsTbody.appendChild(r));

        document.querySelectorAll('th.sortable').forEach(th => {
            if (th.dataset.sort === sortKey) th.setAttribute('data-sort-dir', currentSortDir);
            else th.removeAttribute('data-sort-dir');
        });

        applyFilters();
    }

    function autoSubmitFilters() {
        if (!filtersForm) return;
        if (searchHidden && tableSearch) searchHidden.value = tableSearch.value;
        if (roleHidden) roleHidden.value = roleFilter;
        filtersForm.submit();
    }

    // Role pills click: persist on refresh by submitting with role=...
    rolePills.forEach(pill => {
        pill.addEventListener('click', function () {
            rolePills.forEach(p => p.classList.remove('active'));
            this.classList.add('active');
            roleFilter = (this.dataset.role || '').toLowerCase();
            autoSubmitFilters(); // refresh + remember role
        });
    });

    if (statusSelect) statusSelect.addEventListener('change', autoSubmitFilters);
    if (plantSelect)  plantSelect.addEventListener('change', autoSubmitFilters);
    if (fromInput)    fromInput.addEventListener('change', autoSubmitFilters);
    if (toInput)      toInput.addEventListener('change', autoSubmitFilters);

    if (tableSearch)  tableSearch.addEventListener('input', applyFilters);

    document.querySelectorAll('th.sortable').forEach(th => {
        th.addEventListener('click', function () {
            const key = this.dataset.sort;
            if (key) sortApprovals(key);
        });
    });

    // Prev month button: sets from/to to previous month and submits
    if (prevMonthBtn && fromInput && toInput) {
        prevMonthBtn.addEventListener('click', function () {
            const now = new Date();
            const firstThisMonth = new Date(now.getFullYear(), now.getMonth(), 1);
            const firstPrevMonth = new Date(firstThisMonth.getFullYear(), firstThisMonth.getMonth() - 1, 1);
            const lastPrevMonth  = new Date(firstThisMonth.getFullYear(), firstThisMonth.getMonth(), 0);

            const fmt = (d) => {
                const yyyy = d.getFullYear();
                const mm = String(d.getMonth() + 1).padStart(2, '0');
                const dd = String(d.getDate()).padStart(2, '0');
                return `${yyyy}-${mm}-${dd}`;
            };

            fromInput.value = fmt(firstPrevMonth);
            toInput.value   = fmt(lastPrevMonth);
            autoSubmitFilters();
        });
    }

    // Current month button: sets from/to to current month and submits
    if (currentMonthBtn && fromInput && toInput) {
        currentMonthBtn.addEventListener('click', function () {
            const now = new Date();
            const firstThisMonth = new Date(now.getFullYear(), now.getMonth(), 1);
            const lastThisMonth  = new Date(now.getFullYear(), now.getMonth() + 1, 0);

            const fmt = (d) => {
                const yyyy = d.getFullYear();
                const mm = String(d.getMonth() + 1).padStart(2, '0');
                const dd = String(d.getDate()).padStart(2, '0');
                return `${yyyy}-${mm}-${dd}`;
            };

            fromInput.value = fmt(firstThisMonth);
            toInput.value   = fmt(lastThisMonth);
            autoSubmitFilters();
        });
    }

    // Hover photo preview
    const photoLinks = document.querySelectorAll('.photo-links a[data-photo-url]');

    function positionHoverPreview(e) {
        if (!photoHoverPreview) return;

        const offset = 16;
        let x = e.clientX + offset;
        let y = e.clientY + offset;

        photoHoverPreview.style.left = x + 'px';
        photoHoverPreview.style.top  = y + 'px';

        const rect = photoHoverPreview.getBoundingClientRect();

        if (x + rect.width > window.innerWidth - 8) x = e.clientX - rect.width - offset;
        if (y + rect.height > window.innerHeight - 8) y = e.clientY - rect.height - offset;

        photoHoverPreview.style.left = x + 'px';
        photoHoverPreview.style.top  = y + 'px';
    }

    photoLinks.forEach(link => {
        const url = link.dataset.photoUrl || link.getAttribute('href');

        link.addEventListener('mouseenter', function (e) {
            if (!url || !photoHoverPreview || !photoHoverImg) return;
            photoHoverImg.src = url;
            photoHoverPreview.classList.remove('d-none');
            positionHoverPreview(e);
        });

        link.addEventListener('mousemove', function (e) {
            positionHoverPreview(e);
        });

        link.addEventListener('mouseleave', function () {
            if (!photoHoverPreview || !photoHoverImg) return;
            photoHoverPreview.classList.add('d-none');
            photoHoverImg.src = '';
        });
    });

    function showTopAlert(type, message) {
        let alertBox = document.querySelector('#inline-flash');
        if (!alertBox) {
            alertBox = document.createElement('div');
            alertBox.id = 'inline-flash';
            alertBox.className = 'alert alert-' + type + ' alert-dismissible fade show mt-2';
            alertBox.role = 'alert';
            alertBox.innerHTML =
                '<span class="msg"></span>' +
                '<button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>';
            const header = document.querySelector('.page-header');
            if (header && header.parentNode) header.parentNode.insertBefore(alertBox, header.nextSibling);
            else document.body.prepend(alertBox);
        } else {
            alertBox.className = 'alert alert-' + type + ' alert-dismissible fade show mt-2';
        }
        const msgSpan = alertBox.querySelector('.msg');
        if (msgSpan) msgSpan.textContent = message;
    }

    function mapStatusToBadge(status) {
        const s = (status || '').toLowerCase();
        if (s === 'approved') return 'success';
        if (s === 'rejected') return 'danger';
        if (s === 'pending')  return 'warning';
        return 'secondary';
    }

    // AJAX approve/reject
    const approvalForms = document.querySelectorAll('form[data-approval-form="1"]');

    approvalForms.forEach(form => {
        form.addEventListener('submit', function (e) {
            e.preventDefault();

            const submitBtn = e.submitter || form.querySelector('button[type="submit"][name="action"]');
            const allButtons = form.querySelectorAll('button[type="submit"][name="action"]');

            const formData = new FormData(form);
            if (submitBtn && submitBtn.name === 'action') {
                formData.delete('action');
                formData.append('action', submitBtn.value);
            }
            formData.append('ajax', '1');

            allButtons.forEach(btn => btn.disabled = true);
            if (submitBtn) {
                submitBtn.dataset.originalText = submitBtn.textContent;
                submitBtn.textContent = 'Saving...';
            }

            fetch(window.location.href, {
                method: 'POST',
                body: formData,
                headers: { 'X-Requested-With': 'XMLHttpRequest' }
            })
            .then(res => res.json())
            .then(data => {
                if (!data || !data.status) throw new Error('Unexpected response from server.');

                if (data.status === 'ok') {
                    const newStatus = data.newStatus || '';
                    const row = form.closest('tr[data-row-type="approval"]');
                    if (row) {
                        row.dataset.status      = newStatus.toLowerCase();
                        row.dataset.statusLabel = newStatus.toLowerCase();
                        row.dataset.statusSort  = newStatus.toLowerCase();

                        const badge = row.querySelector('td[data-label="Status"] .badge');
                        if (badge) {
                            badge.textContent = newStatus;
                            badge.className = 'badge text-bg-' + mapStatusToBadge(newStatus);
                        }

                        const sourceDiv = row.querySelector('td[data-label="Status"] .text-muted.small');
                        if (sourceDiv) sourceDiv.textContent = 'Source: WEB';

                        allButtons.forEach(btn => btn.disabled = true);
                    }

                    showTopAlert('success', data.message || 'Attendance updated.');
                    applyFilters();
                } else {
                    showTopAlert('danger', data.message || 'Failed to update attendance.');
                    allButtons.forEach(btn => btn.disabled = false);
                }
            })
            .catch(err => {
                console.error(err);
                showTopAlert('danger', 'Something went wrong while saving. Please retry.');
                allButtons.forEach(btn => btn.disabled = false);
            })
            .finally(() => {
                if (submitBtn && submitBtn.dataset.originalText) {
                    submitBtn.textContent = submitBtn.dataset.originalText;
                }
            });
        });
    });

    // Initial filter (client-side) after load
    applyFilters();
});
</script>

<script>
(function initSidebarToggle(){
  const key = 'driverdocs_sidebar_hidden';
  const btn = document.getElementById('toggleSidebarBtn');
  if (!btn) return;

  const applyState = (hidden) => {
    document.body.classList.toggle('sidebar-hidden', hidden);
    btn.setAttribute('aria-pressed', hidden ? 'true' : 'false');
  };

  const saved = localStorage.getItem(key);
  if (saved === '1') applyState(true);

  btn.addEventListener('click', () => {
    const hidden = !document.body.classList.contains('sidebar-hidden');
    applyState(hidden);
    localStorage.setItem(key, hidden ? '1' : '0');
  });
})();
</script>

</body>
</html>
