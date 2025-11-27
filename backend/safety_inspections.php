<?php
declare(strict_types=1);

session_start();

$authPath = __DIR__ . '/../includes/auth.php';
if (file_exists($authPath)) {
    require_once $authPath;
    if (function_exists('checkRole')) {
        checkRole(['admin', 'supervisor']);
    }
}

require_once __DIR__ . '/../../conf/config.php';

if (!isset($conn) || !($conn instanceof mysqli)) {
    die('Database connection ($conn) not available');
}

mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

/* ---------- helpers ---------- */
function h(string $value): string { return htmlspecialchars($value, ENT_QUOTES, 'UTF-8'); }

function formatDate(?string $value): string {
    if (!$value) return '–';
    try {
        $dt = new DateTime($value);
        return $dt->format('d M Y · H:i');
    } catch (Throwable $e) { return $value; }
}

function buildPageUrl(array $overrides = []): string {
    $params = $_GET;
    foreach ($overrides as $key => $value) {
        if ($value === null || $value === '' || ($key === 'page' && (int)$value === 1)) {
            unset($params[$key]);
        } else {
            $params[$key] = $value;
        }
    }
    $query = http_build_query($params);
    return $query ? ('?' . $query) : '?';
}

$flashSuccess = $_SESSION['safety_flash_success'] ?? null;
$flashError   = $_SESSION['safety_flash_error'] ?? null;
unset($_SESSION['safety_flash_success'], $_SESSION['safety_flash_error']);

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['delete_inspection_id'])) {
    $deleteId = filter_var($_POST['delete_inspection_id'], FILTER_VALIDATE_INT);
    if ($deleteId && $deleteId > 0) {
        try {
            $stmtDelete = $conn->prepare('DELETE FROM tyre_inspections WHERE id = ? LIMIT 1');
            if ($stmtDelete) {
                $stmtDelete->bind_param('i', $deleteId);
                $stmtDelete->execute();
                $affected = $stmtDelete->affected_rows;
                $stmtDelete->close();

                if ($affected > 0) {
                    $_SESSION['safety_flash_success'] = "Inspection #{$deleteId} deleted.";
                } else {
                    $_SESSION['safety_flash_error'] = "Inspection #{$deleteId} was not found.";
                }
            } else {
                $_SESSION['safety_flash_error'] = 'Unable to prepare delete statement.';
            }
        } catch (Throwable $e) {
            error_log('[safety/delete] ' . $e->getMessage());
            $_SESSION['safety_flash_error'] = 'Failed to delete inspection. Please try again.';
        }
    } else {
        $_SESSION['safety_flash_error'] = 'Invalid inspection id.';
    }

    header('Location: ' . buildPageUrl());
    exit;
}

/* ---------- filters ---------- */
$statusOptions = ['all', 'draft', 'submitted', 'approved', 'rejected'];
$statusFilter  = strtolower(trim($_GET['status'] ?? 'draft'));
if (!in_array($statusFilter, $statusOptions, true)) $statusFilter = 'draft';

$plantFilter   = isset($_GET['plant']) ? (int)$_GET['plant'] : null;
$driverFilter  = isset($_GET['driver']) ? (int)$_GET['driver'] : null; // keep for main list
$searchQuery   = trim((string)($_GET['q'] ?? ''));
$limit         = isset($_GET['limit']) ? (int)$_GET['limit'] : 50;
if ($limit <= 0 || $limit > 200) $limit = 50;

$page = isset($_GET['page']) ? (int)$_GET['page'] : 1;
if ($page < 1) $page = 1;

$filterClauses = [];
$filterParams  = [];
$filterTypes   = '';

if ($statusFilter !== 'all') {
    $filterClauses[] = 'ti.status = ?';
    $filterParams[] = $statusFilter;
    $filterTypes .= 's';
}

if ($plantFilter) {
    $filterClauses[] = 'ti.plant_id = ?';
    $filterParams[] = $plantFilter;
    $filterTypes .= 'i';
}

if ($driverFilter) {
    $filterClauses[] = 'ti.driver_id = ?';
    $filterParams[] = $driverFilter;
    $filterTypes .= 'i';
}

if ($searchQuery !== '') {
    if (ctype_digit($searchQuery)) {
        $filterClauses[] = 'ti.id = ?';
        $filterParams[] = (int)$searchQuery;
        $filterTypes .= 'i';
    } else {
        $filterClauses[] = '('
            . 'v.vehicle_no LIKE ? OR '
            . 'COALESCE(p.plant_name, \'\') LIKE ? OR '
            . 'COALESCE(d.name, \'\') LIKE ? OR '
            . 'COALESCE(d.empid, \'\') LIKE ?'
            . ')';
        $like = '%' . $searchQuery . '%';
        array_push($filterParams, $like, $like, $like, $like);
        $filterTypes .= 'ssss';
    }
}

$filterSql = $filterClauses ? (' AND ' . implode(' AND ', $filterClauses)) : '';
$offset = ($page - 1) * $limit;
if ($offset < 0) $offset = 0;

/* ---------- lookups ---------- */
$plants = [];
$drivers = [];
try {
    if ($rs = $conn->query('SELECT id, plant_name FROM plants ORDER BY plant_name ASC')) {
        while ($r = $rs->fetch_assoc()) $plants[(int)$r['id']] = $r['plant_name'] ?: ('Plant #'.$r['id']);
        $rs->close();
    }
    if ($rs = $conn->query("SELECT id, COALESCE(NULLIF(name,''), CONCAT('Driver #', id)) AS name, COALESCE(empid,'') empid FROM drivers ORDER BY name ASC")) {
        while ($r = $rs->fetch_assoc()) {
            $label = trim($r['name'] . ($r['empid'] ? (' · '.$r['empid']) : ''));
            $drivers[(int)$r['id']] = $label ?: ('Driver #'.$r['id']);
        }
        $rs->close();
    }
} catch (Throwable $e) { /* non-fatal */ }

/* ---------- summary & totals (filtered set) ---------- */
$summary = [
    'total' => 0,
    'draft' => 0,
    'submitted' => 0,
    'approved' => 0,
    'rejected' => 0,
    'tyres_total' => 0,
    'tyres_done' => 0,
    'tyres_issue' => 0,
    'tyres_caution' => 0,
];
$totalRows = 0;

try {
    $summarySql = "
    SELECT
        COUNT(DISTINCT ti.id) AS total_inspections,
        COUNT(DISTINCT CASE WHEN ti.status = 'draft' THEN ti.id END) AS draft_count,
        COUNT(DISTINCT CASE WHEN ti.status = 'submitted' THEN ti.id END) AS submitted_count,
        COUNT(DISTINCT CASE WHEN ti.status = 'approved' THEN ti.id END) AS approved_count,
        COUNT(DISTINCT CASE WHEN ti.status = 'rejected' THEN ti.id END) AS rejected_count,
        COUNT(t.id) AS tyres_total,
        SUM(CASE WHEN t.status IS NOT NULL THEN 1 ELSE 0 END) AS tyres_done,
        SUM(CASE WHEN t.status = 'issue' THEN 1 ELSE 0 END) AS tyres_issue,
        SUM(CASE WHEN t.status = 'caution' THEN 1 ELSE 0 END) AS tyres_caution
    FROM tyre_inspections ti
    LEFT JOIN tyre_inspection_tyres t ON t.inspection_id = ti.id
    LEFT JOIN vehicles v  ON v.id  = ti.vehicle_id
    LEFT JOIN plants  p   ON p.id  = ti.plant_id
    LEFT JOIN drivers d   ON d.id  = ti.driver_id
    WHERE 1=1 {$filterSql}
    ";

    $summaryStmt = $conn->prepare($summarySql);
    if ($filterParams) {
        $summaryStmt->bind_param($filterTypes, ...$filterParams);
    }
    $summaryStmt->execute();
    $summaryRow = $summaryStmt->get_result()->fetch_assoc();
    $summaryStmt->close();

    if ($summaryRow) {
        $summary['total']        = (int)($summaryRow['total_inspections'] ?? 0);
        $summary['draft']        = (int)($summaryRow['draft_count'] ?? 0);
        $summary['submitted']    = (int)($summaryRow['submitted_count'] ?? 0);
        $summary['approved']     = (int)($summaryRow['approved_count'] ?? 0);
        $summary['rejected']     = (int)($summaryRow['rejected_count'] ?? 0);
        $summary['tyres_total']  = (int)($summaryRow['tyres_total'] ?? 0);
        $summary['tyres_done']   = (int)($summaryRow['tyres_done'] ?? 0);
        $summary['tyres_issue']  = (int)($summaryRow['tyres_issue'] ?? 0);
        $summary['tyres_caution']= (int)($summaryRow['tyres_caution'] ?? 0);
        $totalRows = $summary['total'];
    }
} catch (Throwable $e) {
    $totalRows = 0;
}

$totalPages = $totalRows > 0 ? (int)ceil($totalRows / $limit) : 1;
if ($totalPages < 1) $totalPages = 1;
if ($page > $totalPages) {
    $page = $totalPages;
}
if ($page < 1) $page = 1;
$offset = ($page - 1) * $limit;
if ($offset < 0) $offset = 0;
$completionPct = $summary['tyres_total'] > 0
    ? (int)round(($summary['tyres_done'] / $summary['tyres_total']) * 100)
    : 0;

/* ---------- main inspections query ---------- */
$inspections = [];
$errorMessage = null;

try {
    $sql = "
    SELECT
        ti.id,
        ti.vehicle_id,
        ti.plant_id,
        ti.driver_id,
        ti.status,
        ti.started_at,
        ti.submitted_at,
        ti.updated_at,
        ti.overall_note,
        v.vehicle_no,
        p.plant_name,
        d.name AS driver_name,
        d.empid AS driver_code,
        COUNT(t.id) AS total_tyres,
        SUM(CASE WHEN t.status IS NOT NULL THEN 1 ELSE 0 END) AS answered_tyres,
        SUM(CASE WHEN t.status = 'issue' THEN 1 ELSE 0 END) AS issue_tyres,
        SUM(CASE WHEN t.status = 'caution' THEN 1 ELSE 0 END) AS caution_tyres
    FROM tyre_inspections ti
    LEFT JOIN tyre_inspection_tyres t ON t.inspection_id = ti.id
    LEFT JOIN vehicles v  ON v.id  = ti.vehicle_id
    LEFT JOIN plants  p   ON p.id  = ti.plant_id
    LEFT JOIN drivers d   ON d.id  = ti.driver_id
    WHERE 1=1 {$filterSql}
    GROUP BY ti.id
    ORDER BY ti.updated_at DESC
    LIMIT ? OFFSET ?
    ";

    $paramsMain = array_merge($filterParams, [$limit, $offset]);
    $typesMain  = $filterTypes . 'ii';

    $stmt = $conn->prepare($sql);
    $stmt->bind_param($typesMain, ...$paramsMain);
    $stmt->execute();
    $res = $stmt->get_result();
    while ($row = $res->fetch_assoc()) $inspections[] = $row;
    $stmt->close();
} catch (Throwable $e) {
    $errorMessage = 'Unable to load inspections: ' . $e->getMessage();
}

$shownCount  = count($inspections);
$startRecord = $totalRows > 0 ? $offset + 1 : 0;
$endRecord   = $totalRows > 0 ? min($offset + $shownCount, $totalRows) : 0;

/* ---------- vehicles not inspected in last 15 days (respects plant filter) ---------- */
/* We compute last_inspected_at per vehicle (max of updated/submitted/started), then filter older than 15 days or never */
$staleVehicles = [];
try {
    $params2 = [];
    $types2  = '';
    $sql2 = "
    WITH last_ins AS (
        SELECT
            ti.vehicle_id,
            MAX(
                COALESCE(ti.updated_at, ti.submitted_at, ti.started_at)
            ) AS last_dt
        FROM tyre_inspections ti
        GROUP BY ti.vehicle_id
    )
    SELECT
        v.id AS vehicle_id,
        v.vehicle_no,
        p.plant_name,
        li.last_dt
    FROM vehicles v
    LEFT JOIN plants p ON p.id = v.plant_id
    LEFT JOIN last_ins li ON li.vehicle_id = v.id
    WHERE 1=1
    ";
    if ($plantFilter) {
        $sql2 .= " AND v.plant_id = ? ";
        $params2[] = $plantFilter;
        $types2 .= 'i';
    }
    $sql2 .= "
    AND (li.last_dt IS NULL OR li.last_dt < (NOW() - INTERVAL 15 DAY))
    ORDER BY p.plant_name ASC, v.vehicle_no ASC
    LIMIT 500
    ";

    $stmt2 = $conn->prepare($sql2);
    if ($params2) $stmt2->bind_param($types2, ...$params2);
    $stmt2->execute();
    $res2 = $stmt2->get_result();
    while ($row = $res2->fetch_assoc()) $staleVehicles[] = $row;
    $stmt2->close();
} catch (Throwable $e) {
    // do not block page; show nothing if error
}

?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Tyre Checklist — Safety Inspections</title>

<link href="https://fonts.googleapis.com/css2?family=Josefin+Sans:wght@400;600;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">

<style>
    :root{ --ink:#0f172a; --muted:#64748b; --bg:#f5f7fb; --line:#e2e8f0; }
    body{ background:var(--bg); font-family:'Josefin Sans',system-ui,-apple-system,Segoe UI,Roboto,sans-serif; }
    .page-header{ margin-bottom:24px; }
    .crumbs{ color:var(--muted); font-size:.9rem; }
    .stat-card{ border-radius:18px; padding:18px; background:#fff; box-shadow:0 6px 20px rgba(15,23,42,.08); }
    .stat-label{ font-size:.82rem; text-transform:uppercase; letter-spacing:.08em; color:var(--muted); }
    .stat-value{ font-size:1.9rem; font-weight:700; color:var(--ink); }
    .badge-status{ text-transform:capitalize; font-size:.75rem; padding:.35rem .65rem; border-radius:999px; }
    .badge-draft{ background:#fde68a; color:#92400e; }
    .badge-submitted{ background:#c7d2fe; color:#1d4ed8; }
    .badge-approved{ background:#bbf7d0; color:#047857; }
    .badge-rejected{ background:#fecaca; color:#b91c1c; }
    .issue-chip,.caution-chip{ display:inline-flex; align-items:center; gap:6px; padding:4px 10px; border-radius:999px; font-size:.75rem; font-weight:600; }
    .issue-chip{ background:#fee2e2; color:#b91c1c; }
    .caution-chip{ background:#fef3c7; color:#92400e; }
    .table thead th{ text-transform:uppercase; font-size:.74rem; color:var(--muted); border-bottom:none; letter-spacing:.08em; white-space:nowrap; cursor:pointer; }
    .table tbody td{ vertical-align:middle; border-color:var(--line); }
    .progress{ height:6px; background:var(--line); }
    .progress-bar{ border-radius:999px; }
    .toolbar .form-select, .toolbar .form-control{ border-radius:10px; }
    .sort-hint{ font-size:.75rem; color:var(--muted); }
    .sticky-head thead th{ position:sticky; top:0; background:#fff; z-index:1; }
    .section-title{ font-weight:700; color:var(--ink); }
    .card-section{ border-radius:14px; overflow:hidden; }
</style>
</head>
<body>
<div class="container-fluid py-4">
    <div class="page-header d-flex flex-column flex-md-row align-items-md-center justify-content-between gap-3">
        <div>
            <div class="crumbs mb-1"><i class="fa-solid fa-helmet-safety me-2"></i>Safety / Tyre Checklist</div>
            <h1 class="h3 mb-1">Tyre Checklist — Safety Inspections</h1>
            <p class="text-muted mb-0">Track tyre checklist progress across your fleet. Filter by plant, status, or driver.</p>
        </div>

        <form class="row gy-2 gx-2 align-items-center toolbar" method="get">
            <div class="col-auto">
                <input type="text" name="q" class="form-control" placeholder="Search inspection, vehicle, plant, driver"
                       value="<?= h($searchQuery) ?>">
            </div>
            <div class="col-auto">
                <select name="status" class="form-select">
                    <?php foreach ($statusOptions as $option): ?>
                        <option value="<?= h($option) ?>" <?= $statusFilter === $option ? 'selected' : '' ?>><?= ucfirst($option) ?></option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="col-auto">
                <select name="plant" class="form-select">
                    <option value="">All plants</option>
                    <?php foreach ($plants as $id => $name): ?>
                        <option value="<?= $id ?>" <?= ($plantFilter === $id) ? 'selected' : '' ?>><?= h($name) ?></option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="col-auto">
                <select name="driver" class="form-select">
                    <option value="">All drivers</option>
                    <?php foreach ($drivers as $id => $label): ?>
                        <option value="<?= $id ?>" <?= ($driverFilter === $id) ? 'selected' : '' ?>><?= h($label) ?></option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="col-auto">
                <select name="limit" class="form-select">
                    <?php foreach ([25,50,100,200] as $opt): ?>
                        <option value="<?= $opt ?>" <?= $limit === $opt ? 'selected' : '' ?>>Show <?= $opt ?> / page</option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="col-auto">
                <button type="submit" class="btn btn-primary"><i class="fa-solid fa-filter me-2"></i>Apply</button>
            </div>
        </form>
    </div>

    <div class="row g-3 mb-4">
        <div class="col-md-3 col-sm-6">
            <div class="stat-card">
                <div class="stat-label">Total inspections</div>
                <div class="stat-value"><?= $summary['total'] ?></div>
                <div class="text-muted small">Draft: <?= $summary['draft'] ?> · Submitted: <?= $summary['submitted'] ?> · Approved: <?= $summary['approved'] ?> · Rejected: <?= $summary['rejected'] ?></div>
            </div>
        </div>
        <div class="col-md-3 col-sm-6">
            <div class="stat-card">
                <div class="stat-label">Tyre progress</div>
                <div class="stat-value"><?= $completionPct ?>%</div>
                <div class="text-muted small"><?= $summary['tyres_done'] ?> of <?= $summary['tyres_total'] ?> tyres answered</div>
            </div>
        </div>
        <div class="col-md-3 col-sm-6">
            <div class="stat-card">
                <div class="stat-label">Caution tyres</div>
                <div class="stat-value text-warning"><?= $summary['tyres_caution'] ?></div>
                <div class="text-muted small">Across filtered inspections</div>
            </div>
        </div>
        <div class="col-md-3 col-sm-6">
            <div class="stat-card">
                <div class="stat-label text-danger">Critical issues</div>
                <div class="stat-value text-danger"><?= $summary['tyres_issue'] ?></div>
                <div class="text-muted small">Requires immediate attention</div>
            </div>
        </div>
    </div>

    <?php if ($flashSuccess): ?>
        <div class="alert alert-success d-flex align-items-center" role="alert">
            <i class="fa-solid fa-circle-check me-2"></i><?= h($flashSuccess) ?>
        </div>
    <?php endif; ?>

    <?php if ($flashError): ?>
        <div class="alert alert-danger d-flex align-items-center" role="alert">
            <i class="fa-solid fa-triangle-exclamation me-2"></i><?= h($flashError) ?>
        </div>
    <?php endif; ?>

    <?php if ($errorMessage): ?>
        <div class="alert alert-danger d-flex align-items-center" role="alert">
            <i class="fa-solid fa-triangle-exclamation me-2"></i><?= h($errorMessage) ?>
        </div>
    <?php endif; ?>

    <?php if (!$errorMessage && empty($inspections)): ?>
        <div class="alert alert-info">
            <i class="fa-solid fa-circle-info me-2"></i>
            No inspections found for the selected filters.
        </div>
    <?php else: ?>
        <div class="card shadow-sm border-0 card-section mb-4">
            <div class="card-body p-0">
                <div class="d-flex justify-content-between align-items-center px-3 py-2 border-bottom">
                    <div class="sort-hint"><i class="fa-solid fa-arrow-up-a-z me-2"></i>Currently showing latest updates first. Click a column header or use the dropdowns to re-sort.</div>
                        <div class="d-flex gap-2 align-items-center">
                            <select id="sortCol" class="form-select form-select-sm">
                                <option value="0">Inspection</option>
                                <option value="1">Vehicle</option>
                                <option value="2">Plant</option>
                                <option value="3">Driver</option>
                                <option value="4">Tyres (done)</option>
                                <option value="5">Alerts</option>
                                <option value="6">Status</option>
                                <option value="7" selected>Last update</option>
                            </select>
                            <select id="sortDir" class="form-select form-select-sm">
                                <option value="asc">A → Z / Low → High</option>
                                <option value="desc" selected>Z → A / High → Low</option>
                            </select>
                        <button id="applySort" class="btn btn-sm btn-outline-secondary"><i class="fa-solid fa-sort"></i></button>
                    </div>
                </div>

                <div class="table-responsive">
                    <table class="table align-middle mb-0 sticky-head" id="inspectionsTable">
                        <thead>
                        <tr>
                            <th scope="col" data-col="0">Inspection</th>
                            <th scope="col" data-col="1">Vehicle</th>
                            <th scope="col" data-col="2">Plant</th>
                            <th scope="col" data-col="3">Driver</th>
                            <th scope="col" data-col="4">Tyres (done)</th>
                            <th scope="col" data-col="5">Alerts</th>
                            <th scope="col" data-col="6">Status</th>
                            <th scope="col" data-col="7">Last update</th>
                            <th scope="col" data-sortable="false" class="text-end">Actions</th>
                        </tr>
                        </thead>
                        <tbody>
                        <?php foreach ($inspections as $row): ?>
                            <?php
                            $totalTyres    = (int)$row['total_tyres'];
                            $answeredTyres = (int)$row['answered_tyres'];
                            $issueTyres    = (int)$row['issue_tyres'];
                            $cautionTyres  = (int)$row['caution_tyres'];
                            $progress      = $totalTyres > 0 ? round(($answeredTyres / $totalTyres) * 100) : 0;
                            $status        = strtolower($row['status'] ?? 'draft');
                            $statusKey     = in_array($status, ['draft', 'submitted', 'approved', 'rejected'], true) ? $status : 'draft';
                            $statusClass   = 'badge-status badge-' . $statusKey;

                            $vehicleLabel = $row['vehicle_no'] ?: ('Vehicle #'.(int)$row['vehicle_id']);
                            $plantLabel   = $row['plant_name'] ?: ('Plant #'.(int)$row['plant_id']);
                            $driverLabel  = !empty($row['driver_name'])
                                            ? trim($row['driver_name'] . (!empty($row['driver_code']) ? (' · '.$row['driver_code']) : ''))
                                            : '–';
                            ?>
                            <tr>
                                <td data-sort="<?= (int)$row['id'] ?>">
                                    <div class="fw-semibold text-dark">#<?= (int)$row['id'] ?></div>
                                    <div class="text-muted small">Started <?= formatDate($row['started_at']) ?></div>
                                </td>
                                <td data-sort="<?= h($vehicleLabel) ?>">
                                    <div class="fw-semibold"><?= h($vehicleLabel) ?></div>
                                </td>
                                <td data-sort="<?= h($plantLabel) ?>"><?= h($plantLabel) ?></td>
                                <td data-sort="<?= h($driverLabel) ?>"><?= h($driverLabel) ?></td>
                                <td style="width:180px;" data-sort="<?= $progress ?>">
                                    <div class="fw-semibold"><?= $answeredTyres ?> / <?= $totalTyres ?></div>
                                    <div class="progress mt-1">
                                        <div class="progress-bar bg-success" role="progressbar" style="width: <?= $progress ?>%;"></div>
                                    </div>
                                </td>
                                <td data-sort="<?= ($issueTyres*1000 + $cautionTyres) ?>">
                                    <?php if ($issueTyres > 0): ?>
                                        <span class="issue-chip"><i class="fa-solid fa-circle-exclamation"></i> <?= $issueTyres ?></span>
                                    <?php endif; ?>
                                    <?php if ($cautionTyres > 0): ?>
                                        <span class="caution-chip ms-1"><i class="fa-solid fa-triangle-exclamation"></i> <?= $cautionTyres ?></span>
                                    <?php endif; ?>
                                    <?php if ($issueTyres === 0 && $cautionTyres === 0): ?>
                                        <span class="text-muted small">No alerts</span>
                                    <?php endif; ?>
                                </td>
                                <td data-sort="<?= h($status) ?>">
                                    <span class="<?= $statusClass ?>"><?= ucfirst($status) ?></span>
                                </td>
                                <td data-sort="<?= strtotime($row['updated_at'] ?? '1970-01-01') ?>">
                                    <?= formatDate($row['updated_at']) ?>
                                    <?php if (!empty($row['overall_note'])): ?>
                                        <div class="text-muted small fst-italic"><?= h($row['overall_note']) ?></div>
                                    <?php endif; ?>
                                </td>
                                <td class="text-end">
                                    <form method="post" class="d-inline" onsubmit="return confirm('Delete inspection #<?= (int)$row['id'] ?>? This cannot be undone.');">
                                        <input type="hidden" name="delete_inspection_id" value="<?= (int)$row['id'] ?>">
                                        <button type="submit" class="btn btn-outline-danger btn-sm">
                                            <i class="fa-solid fa-trash-can me-1"></i>Delete
                                        </button>
                                    </form>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>

                <div class="d-flex flex-column flex-lg-row align-items-lg-center justify-content-between gap-3 px-3 py-3 border-top">
                    <div class="text-muted small">
                        <?php if ($totalRows > 0): ?>
                            Showing <?= number_format($startRecord) ?>–<?= number_format($endRecord) ?> of <?= number_format($totalRows) ?> inspections
                        <?php else: ?>
                            No inspections to display
                        <?php endif; ?>
                    </div>
                    <?php if ($totalPages > 1): ?>
                        <?php
                        $window = 2;
                        $startPage = max(1, $page - $window);
                        $endPage = min($totalPages, $page + $window);
                        ?>
                        <nav aria-label="Inspection pagination">
                            <ul class="pagination pagination-sm mb-0">
                                <li class="page-item <?= $page <= 1 ? 'disabled' : '' ?>">
                                    <a class="page-link" href="<?= h(buildPageUrl(['page' => $page > 1 ? $page - 1 : null])) ?>" aria-label="Previous">
                                        <span aria-hidden="true">&laquo;</span>
                                    </a>
                                </li>
                                <?php if ($startPage > 1): ?>
                                    <li class="page-item">
                                        <a class="page-link" href="<?= h(buildPageUrl(['page' => null])) ?>">1</a>
                                    </li>
                                    <?php if ($startPage > 2): ?>
                                        <li class="page-item disabled"><span class="page-link">…</span></li>
                                    <?php endif; ?>
                                <?php endif; ?>
                                <?php for ($p = $startPage; $p <= $endPage; $p++): ?>
                                    <li class="page-item <?= $p === $page ? 'active' : '' ?>">
                                        <a class="page-link" href="<?= h(buildPageUrl(['page' => $p === 1 ? null : $p])) ?>"><?= $p ?></a>
                                    </li>
                                <?php endfor; ?>
                                <?php if ($endPage < $totalPages): ?>
                                    <?php if ($endPage < $totalPages - 1): ?>
                                        <li class="page-item disabled"><span class="page-link">…</span></li>
                                    <?php endif; ?>
                                    <li class="page-item">
                                        <a class="page-link" href="<?= h(buildPageUrl(['page' => $totalPages === 1 ? null : $totalPages])) ?>"><?= $totalPages ?></a>
                                    </li>
                                <?php endif; ?>
                                <li class="page-item <?= $page >= $totalPages ? 'disabled' : '' ?>">
                                    <a class="page-link" href="<?= h(buildPageUrl(['page' => $page < $totalPages ? $page + 1 : null])) ?>" aria-label="Next">
                                        <span aria-hidden="true">&raquo;</span>
                                    </a>
                                </li>
                            </ul>
                        </nav>
                    <?php endif; ?>
                </div>

            </div>
        </div>
    <?php endif; ?>

    <!-- ===== Vehicles not inspected in last 15 days ===== -->
    <div class="card shadow-sm border-0 card-section">
        <div class="card-header bg-white">
            <h2 class="h5 section-title mb-0">
                <i class="fa-solid fa-clock-rotate-left me-2"></i>Vehicles not inspected in last 15 days
                <?php if ($plantFilter && isset($plants[$plantFilter])): ?>
                    <small class="text-muted">· <?= h($plants[$plantFilter]) ?></small>
                <?php endif; ?>
            </h2>
        </div>
        <div class="card-body p-0">
            <?php if (empty($staleVehicles)): ?>
                <div class="p-3 text-muted">Great! All vehicles have been inspected within the last 15 days.</div>
            <?php else: ?>
                <div class="table-responsive">
                    <table class="table align-middle mb-0 sticky-head" id="staleTable">
                        <thead>
                        <tr>
                            <th data-col="0">Vehicle</th>
                            <th data-col="1">Plant</th>
                            <th data-col="2">Last inspected</th>
                            <th data-col="3">Days since</th>
                        </tr>
                        </thead>
                        <tbody>
                        <?php foreach ($staleVehicles as $rv):
                            $last = $rv['last_dt'] ?? null;
                            $daysSince = '∞';
                            if ($last) {
                                $d1 = new DateTime($last);
                                $d2 = new DateTime('now');
                                $daysSince = (int)$d1->diff($d2)->format('%a');
                            }
                        ?>
                            <tr>
                                <td data-sort="<?= h($rv['vehicle_no']) ?>"><?= h($rv['vehicle_no']) ?></td>
                                <td data-sort="<?= h($rv['plant_name'] ?? '') ?>"><?= h($rv['plant_name'] ?? '') ?></td>
                                <td data-sort="<?= $last ? strtotime($last) : 0 ?>"><?= $last ? formatDate($last) : 'Never' ?></td>
                                <td data-sort="<?= is_numeric($daysSince) ? $daysSince : 99999 ?>"><?= is_numeric($daysSince) ? $daysSince : 'Never' ?></td>
                            </tr>
                        <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            <?php endif; ?>
        </div>
    </div>

</div>

<script>
/* ===== Generic table sorting for both tables ===== */
function makeSortable(tableId, defaultCol = null, defaultDir = 'asc'){
    const table = document.getElementById(tableId);
    if(!table) return;
    const tbody = table.querySelector('tbody');
    const getCellData = (row, idx) => {
        const cell = row.children[idx];
        if(!cell) return '';
        const key = cell.getAttribute('data-sort');
        return (key !== null) ? key : (cell.textContent || '').trim();
    };
    const sortRows = (idx, dir='asc') => {
        const rows = Array.from(tbody.querySelectorAll('tr'));
        const mult = dir === 'asc' ? 1 : -1;
        rows.sort((a,b) => {
            const A = getCellData(a, idx);
            const B = getCellData(b, idx);
            const nA = parseFloat(A), nB = parseFloat(B);
            const bothNumeric = !Number.isNaN(nA) && !Number.isNaN(nB) && A !== '' && B !== '';
            if (bothNumeric) return (nA - nB) * mult;
            const dA = parseInt(A, 10), dB = parseInt(B,10);
            if (!Number.isNaN(dA) && !Number.isNaN(dB) && (String(A).length >= 10 && String(B).length >= 10)) {
                return (dA - dB) * mult;
            }
            return String(A).localeCompare(String(B), undefined, {numeric:true, sensitivity:'base'}) * mult;
        });
        rows.forEach(r => tbody.appendChild(r));
    };
    // header click
    table.querySelectorAll('thead th').forEach((th, i) => {
        if (th.dataset.sortable === 'false') {
            th.style.cursor = 'default';
            return;
        }
        let state = 'asc';
        th.addEventListener('click', () => {
            state = (state === 'asc') ? 'desc' : 'asc';
            sortRows(i, state);
            if (tableId === 'inspectionsTable') {
                const selCol = document.getElementById('sortCol');
                const selDir = document.getElementById('sortDir');
                if (selCol) selCol.value = String(i);
                if (selDir) selDir.value = state;
            }
        });
    });
    // default
    if (defaultCol !== null) sortRows(defaultCol, defaultDir);
}

makeSortable('inspectionsTable', 7, 'desc');
makeSortable('staleTable', 0, 'asc');

// Toolbar dropdown sorter for inspections table
(function(){
    const table = document.getElementById('inspectionsTable');
    if(!table) return;
    const tbody = table.querySelector('tbody');
    const getCellData = (row, idx) => {
        const cell = row.children[idx];
        if(!cell) return '';
        const key = cell.getAttribute('data-sort');
        return (key !== null) ? key : (cell.textContent || '').trim();
    };
    const sortRows = (idx, dir='asc') => {
        const rows = Array.from(tbody.querySelectorAll('tr'));
        const mult = dir === 'asc' ? 1 : -1;
        rows.sort((a,b) => {
            const A = getCellData(a, idx);
            const B = getCellData(b, idx);
            const nA = parseFloat(A), nB = parseFloat(B);
            const bothNumeric = !Number.isNaN(nA) && !Number.isNaN(nB) && A !== '' && B !== '';
            if (bothNumeric) return (nA - nB) * mult;
            const dA = parseInt(A, 10), dB = parseInt(B,10);
            if (!Number.isNaN(dA) && !Number.isNaN(dB) && (String(A).length >= 10 && String(B).length >= 10)) {
                return (dA - dB) * mult;
            }
            return String(A).localeCompare(String(B), undefined, {numeric:true, sensitivity:'base'}) * mult;
        });
        rows.forEach(r => tbody.appendChild(r));
    };
    const btn = document.getElementById('applySort');
    const selCol = document.getElementById('sortCol');
    const selDir = document.getElementById('sortDir');
    if (btn && selCol && selDir) {
        btn.addEventListener('click', (e) => {
            e.preventDefault();
            sortRows(parseInt(selCol.value, 10), selDir.value);
        });
    }
})();
</script>
</body>
</html>
