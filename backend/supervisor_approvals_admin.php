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
    if (!$value) {
        return '—';
    }
    try {
        $dt = new DateTime($value);
        return $dt->format('d M Y · h:i A');
    } catch (Throwable $e) {
        return $value;
    }
}

function statusBadgeClass(string $status): string {
    switch (strtolower($status)) {
        case 'approved':
            return 'success';
        case 'rejected':
            return 'danger';
        case 'pending':
            return 'warning';
        default:
            return 'secondary';
    }
}

/* ----------------- POST: Approve / Reject ----------------- */
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['attendance_id'], $_POST['action'])) {
    $token = (string) ($_POST['csrf_token'] ?? '');
    if (!hash_equals($csrfToken, $token)) {
        supervisorRedirectWithFlash('danger', 'Invalid or expired form token. Please try again.');
    }
    if ($currentUserId <= 0) {
        supervisorRedirectWithFlash('danger', 'Your admin session is missing a user id. Please log in again.');
    }

    $attendanceId = filter_var($_POST['attendance_id'], FILTER_VALIDATE_INT);
    $action = strtolower(trim((string) $_POST['action']));
    $notes = trim((string) ($_POST['notes'] ?? ''));

    if (!$attendanceId || $attendanceId <= 0) {
        supervisorRedirectWithFlash('danger', 'Invalid attendance id.');
    }
    if (!in_array($action, ['approve', 'reject'], true)) {
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
            supervisorRedirectWithFlash('danger', 'Attendance record not found.');
        }

        if ($action === 'approve' && empty($attendanceRow['out_time'])) {
            supervisorRedirectWithFlash(
                'danger',
                'Cannot approve until an OUT punch has been submitted.'
            );
        }

        $newStatus = $action === 'approve' ? 'Approved' : 'Rejected';

        $updateStmt = $conn->prepare(
            'UPDATE attendance
                SET approval_status = ?,
                    notes = CASE WHEN ? <> "" THEN ? ELSE notes END,
                    closed_by_id = ?,
                    closed_at = NOW()
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

        // Try to link to attendance_adjust_requests by ID in notes (#123)
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
        supervisorRedirectWithFlash('success', $message);
    } catch (Throwable $e) {
        supervisorRedirectWithFlash('danger', 'Failed to update attendance: ' . $e->getMessage());
    }
}

/* ----------------- Filters: Status ----------------- */
$statusOptions = ['Pending', 'Approved', 'Rejected', 'All'];
$statusRaw = isset($_GET['status']) ? (string) $_GET['status'] : 'Pending';
$statusFilter = ucfirst(strtolower($statusRaw));
if (!in_array($statusFilter, $statusOptions, true)) {
    $statusFilter = 'Pending';
}

/* ----------------- Filters: Date (From / To) ----------------- */
$fromRaw = isset($_GET['from']) ? trim((string) $_GET['from']) : '';
$toRaw   = isset($_GET['to'])   ? trim((string) $_GET['to'])   : '';

$today = new DateTimeImmutable('today');

if ($fromRaw === '' && $toRaw === '') {
    // default: last 30 days
    $toDateObj   = $today;
    $fromDateObj = $today->modify('-29 days');
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
if ($plantFilter !== null && $plantFilter <= 0) {
    $plantFilter = null;
}

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
    $apiParams = [
        'adminUserId' => $currentUserId,
        'status'      => $statusFilter,
        'fromDate'    => $fromDate,
        'toDate'      => $toDate,
    ];
    if ($plantFilter) {
        $apiParams['plantId'] = (string) $plantFilter;
    }

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

                // Normalize statuses and count
                foreach ($approvals as &$entry) {
                    $status = ucfirst(strtolower(trim((string) ($entry['status'] ?? 'Pending'))));
                    $entry['status'] = $status;
                    $statusCounts[$status] = ($statusCounts[$status] ?? 0) + 1;

                    if (!isset($entry['role']) || $entry['role'] === '') {
                        $entry['role'] = 'Driver';
                    }
                }
                unset($entry);

                foreach ($missingAttendance as &$person) {
                    if (!isset($person['role']) || $person['role'] === '') {
                        $person['role'] = 'Driver';
                    }
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
<title>Attendance Approvals</title>

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
}
.page-header {
    margin-bottom: 1.5rem;
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
.sidebar,
.sidebar * {
    background-color: #ffffff !important;
}
.stats-card {
    border-radius: 16px;
    padding: 1.25rem 1.5rem;
    color: white;
}
.stats-card p {
    margin: 0;
    text-transform: uppercase;
    letter-spacing: .08em;
    font-size: .72rem;
    opacity: 0.9;
}
.stats-card h3 {
    font-size: 1.6rem;
    margin: .4rem 0 0;
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
.table thead th.sortable[data-sort-dir="asc"]::after {
    content: '↑';
}
.table thead th.sortable[data-sort-dir="desc"]::after {
    content: '↓';
}
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
.photo-links a {
    text-decoration: none;
}
.section-title {
    font-size: 1rem;
    font-weight: 600;
}
#photoPreviewCard img {
    max-height: 420px;
    object-fit: contain;
}
/* Increase side space inside main content column */
main.main > .container-fluid {
    padding-left: 1.5rem;
    padding-right: 1.5rem;
}
@media (min-width: 992px) {
    main.main > .container-fluid {
        padding-left: 2.5rem;
        padding-right: 2.5rem;
    }
}
/* Grow effect for attendance submissions search bar */
#table-search-input {
    transition: transform 0.18s ease, box-shadow 0.18s ease;
}
#table-search-input:focus {
    transform: scale(1.03);
    box-shadow: 0 0 0 3px rgba(59,130,246,0.3);
}
</style>
</head>
<body>
<?php
// Go from /public_html/api/mobile → /public_html → /public_html/DriverDocs/includes
$driverDocsBase = dirname(__DIR__, 2) . '/DriverDocs';
include $driverDocsBase . '/includes/navbar.php';
?>
<div class="container-fluid">
  <div class="row">
    <?php
    include $driverDocsBase . '/includes/sidebar.php';
    ?>

    <!-- main with increased side padding -->
    <main class="main col-md-9 col-lg-10">
      <div class="container-fluid py-4">

        <!-- Plain text header -->
        <div class="page-header">
            <h1 class="h4 mb-1">Attendance Approvals</h1>
            <p class="mb-0 text-muted">
                Review supervisor and driver attendance submissions, then act on pending checkouts.
            </p>
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

        <!-- KPI cards (Pending / Approved / Rejected) -->
        <div class="row g-3 mb-4">
            <div class="col-md-4">
                <div class="stats-card" style="background: linear-gradient(135deg,#f97316,#facc15);">
                    <p>Pending</p>
                    <h3><?= h((string) ($statusCounts['Pending'] ?? 0)) ?></h3>
                </div>
            </div>
            <div class="col-md-4">
                <div class="stats-card" style="background: linear-gradient(135deg,#10b981,#22c55e);">
                    <p>Approved</p>
                    <h3><?= h((string) ($statusCounts['Approved'] ?? 0)) ?></h3>
                </div>
            </div>
            <div class="col-md-4">
                <div class="stats-card" style="background: linear-gradient(135deg,#ef4444,#f97316);">
                    <p>Rejected</p>
                    <h3><?= h((string) ($statusCounts['Rejected'] ?? 0)) ?></h3>
                </div>
            </div>
        </div>

        <!-- Photo preview panel -->
        <div id="photoPreviewCard" class="card mb-4 d-none">
            <div class="card-header d-flex justify-content-between align-items-center">
                <span class="h6 mb-0 text-muted">Photo preview</span>
                <button type="button" class="btn btn-sm btn-outline-secondary" id="photoPreviewClose">
                    Close
                </button>
            </div>
            <div class="card-body text-center bg-light">
                <img id="photoPreviewImg" src="" alt="Attendance photo preview" class="img-fluid rounded shadow-sm">
            </div>
        </div>

        <!-- Filters + Role toggle -->
        <div class="card filters-card mb-4">
            <div class="card-body">
                <div class="d-flex flex-column flex-md-row align-items-md-center mb-3 gap-3">
                    <div class="section-title mb-0">Filters</div>
                    <div class="ms-md-auto d-flex flex-row gap-2 align-items-center">
                        <div class="role-toggle">
                            <!-- default: Supervisors active -->
                            <button type="button"
                                    class="role-pill"
                                    data-role="driver">
                                Drivers
                            </button>
                            <button type="button"
                                    class="role-pill active"
                                    data-role="supervisor">
                                Supervisors
                            </button>
                        </div>
                    </div>
                </div>

                <form class="row g-3 align-items-end" method="get" id="filters-form">
                    <div class="col-md-3">
                        <label class="form-label fw-semibold">Status</label>
                        <select class="form-select" name="status" id="status-select">
                            <?php foreach ($statusOptions as $option): ?>
                                <option value="<?= h($option) ?>" <?= $statusFilter === $option ? 'selected' : '' ?>>
                                    <?= h($option) ?>
                                </option>
                            <?php endforeach; ?>
                        </select>
                    </div>

                    <div class="col-md-3">
                        <label class="form-label fw-semibold">Plant</label>
                        <select class="form-select" name="plantId" id="plant-select">
                            <option value="">All plants</option>
                            <?php foreach ($plantOptions as $plant): ?>
                                <option value="<?= h((string) $plant['id']) ?>"
                                    <?= $plantFilter === (int) $plant['id'] ? 'selected' : '' ?>>
                                    <?= h($plant['name']) ?>
                                </option>
                            <?php endforeach; ?>
                        </select>
                    </div>

                    <div class="col-md-3">
                        <label class="form-label fw-semibold">From date</label>
                        <input type="date"
                               class="form-control"
                               name="from"
                               id="from-date"
                               value="<?= h($fromDate) ?>">
                    </div>

                    <div class="col-md-3">
                        <label class="form-label fw-semibold">To date</label>
                        <input type="date"
                               class="form-control"
                               name="to"
                               id="to-date"
                               value="<?= h($toDate) ?>">
                    </div>
                </form>
                <div class="text-muted small mt-2">
                    <?= h($rangeLabel) ?>
                    <?php if ($selectedPlantName): ?>
                        · <?= h($selectedPlantName) ?>
                    <?php endif; ?>
                </div>
            </div>
        </div>

        <!-- Approvals table -->
        <div class="card approvals-card mb-4">
            <div class="card-header bg-white d-flex flex-column flex-md-row justify-content-between align-items-md-center gap-2">
                <div class="d-flex align-items-center justify-content-between w-100 w-md-auto">
                    <h2 class="h6 mb-0 text-uppercase text-muted">Attendance submissions</h2>
                    <span class="text-muted small d-md-none">Total: <?= h((string) count($approvals)) ?></span>
                </div>
                <!-- Full-width search bar in Attendance submissions card with grow effect -->
                <div class="w-100 w-md-50">
                    <input type="text"
                           id="table-search-input"
                           class="form-control form-control-sm"
                           placeholder="Search within attendance submissions (name, plant, vehicle, status, notes)">
                </div>
                <span class="text-muted small d-none d-md-inline">Total listed: <?= h((string) count($approvals)) ?></span>
            </div>
            <div class="card-body p-0">
                <?php if (empty($approvals)): ?>
                    <div class="p-5 text-center text-muted">
                        No attendance submissions match the selected window.
                    </div>
                <?php else: ?>
                    <div class="table-responsive">
                        <table class="table align-middle mb-0">
                            <thead>
                            <tr>
                                <th class="sortable" data-sort="person">Person</th>
                                <th class="sortable" data-sort="plant">Plant &amp; Vehicle</th>
                                <th class="sortable" data-sort="date">In / Out</th>
                                <th>Photos</th>
                                <th class="sortable" data-sort="status">Status</th>
                                <th class="sortable" data-sort="notes">Notes</th>
                                <th>Actions</th>
                            </tr>
                            </thead>
                            <tbody id="approvals-tbody">
                            <?php foreach ($approvals as $approval): ?>
                                <?php
                                $roleLabel = (string) ($approval['role'] ?? 'Driver');
                                $roleSlug  = strtolower($roleLabel);
                                $plantId   = isset($approval['plantId']) ? (int) $approval['plantId'] : 0;

                                // derive attendance date for JS sort/search
                                $attendanceDate = '';
                                $sortDateKey    = '';
                                if (!empty($approval['inTime'])) {
                                    try {
                                        $dt = new DateTime($approval['inTime']);
                                        $attendanceDate = $dt->format('Y-m-d');
                                        $sortDateKey    = $dt->format('Y-m-d H:i:s');
                                    } catch (Throwable $e) {
                                        $attendanceDate = '';
                                    }
                                } elseif (!empty($approval['outTime'])) {
                                    try {
                                        $dt = new DateTime($approval['outTime']);
                                        $attendanceDate = $dt->format('Y-m-d');
                                        $sortDateKey    = $dt->format('Y-m-d H:i:s');
                                    } catch (Throwable $e) {
                                        $attendanceDate = '';
                                    }
                                }

                                // Fallback if API sends a pure date field
                                if ($attendanceDate === '' && !empty($approval['attendanceDate'])) {
                                    try {
                                        $dt = new DateTime($approval['attendanceDate']);
                                        $attendanceDate = $dt->format('Y-m-d');
                                        if ($sortDateKey === '') {
                                            $sortDateKey = $dt->format('Y-m-d 00:00:00');
                                        }
                                    } catch (Throwable $e) {
                                        // ignore
                                    }
                                }

                                $hasCheckout = !empty($approval['outTime']);
                                $driverName  = (string) ($approval['driverName'] ?? '');
                                $plantName   = (string) ($approval['plantName'] ?? '');
                                $notesRaw    = (string) ($approval['notes'] ?? '');
                                $statusNorm  = ucfirst(strtolower(trim((string) ($approval['status'] ?? 'Pending'))));

                                // helper strings for combined search
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
                                    <td>
                                        <div class="d-flex align-items-center gap-3">
                                            <?php if (!empty($approval['profilePhoto'])): ?>
                                                <span class="avatar"
                                                      style="background-image: url('<?= h($approval['profilePhoto']) ?>');"></span>
                                            <?php else: ?>
                                                <span class="avatar">
                                                    <?= h(strtoupper(mb_substr((string)$driverName, 0, 1))) ?>
                                                </span>
                                            <?php endif; ?>
                                            <div>
                                                <div class="fw-semibold"><?= h($driverName) ?></div>
                                                <div class="text-muted small">
                                                    #<?= h((string) $approval['driverId']) ?> · <?= h($roleLabel) ?>
                                                </div>
                                            </div>
                                        </div>
                                    </td>
                                    <td>
                                        <div class="fw-semibold"><?= h($plantName) ?></div>
                                        <div class="text-muted small">
                                            <?= h($vehicleText !== '' ? $vehicleText : 'Vehicle TBD') ?>
                                        </div>
                                    </td>
                                    <td>
                                        <div class="small">
                                            <div class="text-muted">IN</div>
                                            <div><?= h(formatDateTime($approval['inTime'])) ?></div>
                                        </div>
                                        <div class="small mt-2">
                                            <div class="text-muted">OUT</div>
                                            <div><?= h($approval['outTime'] ? formatDateTime($approval['outTime']) : '—') ?></div>
                                        </div>
                                    </td>
                                    <td class="photo-links">
                                        <div class="d-flex flex-column gap-2">
                                            <?php if (!empty($approval['inPhotoUrl'])): ?>
                                                <a class="btn btn-sm btn-outline-primary"
                                                   href="<?= h($approval['inPhotoUrl']) ?>"
                                                   data-photo-url="<?= h($approval['inPhotoUrl']) ?>">
                                                    IN Photo
                                                </a>
                                            <?php endif; ?>
                                            <?php if (!empty($approval['outPhotoUrl'])): ?>
                                                <a class="btn btn-sm btn-outline-primary"
                                                   href="<?= h($approval['outPhotoUrl']) ?>"
                                                   data-photo-url="<?= h($approval['outPhotoUrl']) ?>">
                                                    OUT Photo
                                                </a>
                                            <?php endif; ?>
                                            <?php if (empty($approval['inPhotoUrl']) && empty($approval['outPhotoUrl'])): ?>
                                                <span class="text-muted small">—</span>
                                            <?php endif; ?>
                                        </div>
                                    </td>
                                    <td>
                                        <span class="badge text-bg-<?= statusBadgeClass($statusNorm) ?>">
                                            <?= h($statusNorm) ?>
                                        </span>
                                        <div class="text-muted small mt-1">
                                            Source: <?= h(strtoupper($approval['source'] ?? 'mobile')) ?>
                                        </div>
                                    </td>
                                    <td class="small">
                                        <?= $notesRaw !== '' ? nl2br(h($notesRaw)) : '<span class="text-muted">—</span>' ?>
                                    </td>
                                    <td>
                                        <?php if (!$hasCheckout): ?>
                                            <!-- Booming / pulse effect only here (Pending checkout label in Actions column) -->
                                            <span class="badge-pending-checkout">
                                                Pending checkout
                                            </span>
                                        <?php else: ?>
                                            <form method="post" class="d-flex flex-column flex-lg-row gap-2 align-items-stretch">
                                                <input type="hidden" name="attendance_id" value="<?= h((string) $approval['attendanceId']) ?>">
                                                <input type="hidden" name="csrf_token" value="<?= h($csrfToken) ?>">
                                                <input type="text"
                                                       name="notes"
                                                       class="form-control form-control-sm"
                                                       placeholder="Optional note">
                                                <div class="d-flex gap-2">
                                                    <button class="btn btn-sm btn-outline-success"
                                                            type="submit"
                                                            name="action"
                                                            value="approve"
                                                            <?= strtolower($statusNorm) === 'approved' ? 'disabled' : '' ?>>
                                                        Approve
                                                    </button>
                                                    <button class="btn btn-sm btn-outline-danger"
                                                            type="submit"
                                                            name="action"
                                                            value="reject"
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

        <!-- Missing attendance -->
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

      </div><!-- /.container-fluid inner -->
    </main>
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

    const approvalsTbody = document.getElementById('approvals-tbody');
    const missingTbody   = document.getElementById('missing-tbody');

    const photoPreviewCard = document.getElementById('photoPreviewCard');
    const photoPreviewImg  = document.getElementById('photoPreviewImg');
    const photoPreviewClose = document.getElementById('photoPreviewClose');

    // Sorting state
    let currentSortKey = null;
    let currentSortDir = 'asc';

    // Default filter = supervisor (based on active pill)
    let roleFilter = (document.querySelector('.role-pill.active')?.dataset.role || 'supervisor').toLowerCase();

    function applyFilters() {
        const tableSearchVal = (tableSearch?.value || '').trim().toLowerCase();

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

            // Role filter (Driver / Supervisor)
            if (roleFilter && rowRole && rowRole !== roleFilter) {
                show = false;
            }

            // Table search filter: within attendance submissions data
            if (rowType === 'approval' && tableSearchVal) {
                const haystack = [
                    rowName,
                    rowPlant,
                    rowVehicle,
                    rowNotes,
                    rowStatusLabel
                ].join(' ');
                if (!haystack.includes(tableSearchVal)) {
                    show = false;
                }
            }

            row.style.display = show ? '' : 'none';
        });
    }

    // Sorting for approvals table
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
            let aVal = '';
            let bVal = '';

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

        // Update header indicators
        document.querySelectorAll('th.sortable').forEach(th => {
            if (th.dataset.sort === sortKey) {
                th.setAttribute('data-sort-dir', currentSortDir);
            } else {
                th.removeAttribute('data-sort-dir');
            }
        });
    }

    // Role pills click
    rolePills.forEach(pill => {
        pill.addEventListener('click', function () {
            rolePills.forEach(p => p.classList.remove('active'));
            this.classList.add('active');
            roleFilter = (this.dataset.role || '').toLowerCase();
            applyFilters();
        });
    });

    // Auto-submit filters form when Status / Plant / From / To change
    function autoSubmitFilters() {
        if (filtersForm) {
            filtersForm.submit();
        }
    }

    if (statusSelect) statusSelect.addEventListener('change', autoSubmitFilters);
    if (plantSelect)  plantSelect.addEventListener('change', autoSubmitFilters);
    if (fromInput)    fromInput.addEventListener('change', autoSubmitFilters);
    if (toInput)      toInput.addEventListener('change', autoSubmitFilters);

    if (tableSearch)  tableSearch.addEventListener('input', applyFilters);

    // Header sort click handlers
    document.querySelectorAll('th.sortable').forEach(th => {
        th.addEventListener('click', function () {
            const key = this.dataset.sort;
            if (key) {
                sortApprovals(key);
                applyFilters(); // keep filters applied after sort
            }
        });
    });

    // Photo preview handlers
    const photoLinks = document.querySelectorAll('.photo-links a[data-photo-url]');
    photoLinks.forEach(link => {
        link.addEventListener('click', function (e) {
            e.preventDefault();
            const url = this.dataset.photoUrl || this.getAttribute('href');
            if (!url || !photoPreviewCard || !photoPreviewImg) return;
            photoPreviewImg.src = url;
            photoPreviewCard.classList.remove('d-none');
            photoPreviewCard.scrollIntoView({ behavior: 'smooth', block: 'center' });
        });
    });

    if (photoPreviewClose) {
        photoPreviewClose.addEventListener('click', function () {
            if (photoPreviewCard) {
                photoPreviewCard.classList.add('d-none');
                photoPreviewImg.src = '';
            }
        });
    }

    // Initial filters: Supervisor + any search
    applyFilters();
});
</script>
</body>
</html>
