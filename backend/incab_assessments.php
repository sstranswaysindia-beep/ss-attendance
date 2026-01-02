<?php
declare(strict_types=1);

session_start();
if (empty($_SESSION['csrf_token'])) {
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
}

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

function h(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES, 'UTF-8');
}

function fmtDate(?string $value): string
{
    if (!$value) return '–';
    try {
        return (new DateTime($value))->format('d M Y');
    } catch (Throwable $e) {
        return $value;
    }
}

function fmtDateTime(?string $value): string
{
    if (!$value) return '–';
    try {
        return (new DateTime($value))->format('d M Y, H:i');
    } catch (Throwable $e) {
        return $value;
    }
}

function bindParams(mysqli_stmt $stmt, string $types, array &$values): void
{
    if ($types === '' || empty($values)) {
        return;
    }
    $refs = [];
    foreach ($values as $k => $v) {
        $refs[$k] = &$values[$k];
    }
    $stmt->bind_param($types, ...$refs);
}

$plants = [];
$drivers = [];
$assessors = [];
try {
    if ($rs = $conn->query('SELECT id, plant_name FROM plants ORDER BY plant_name ASC')) {
        while ($row = $rs->fetch_assoc()) {
            $plants[(int)$row['id']] = trim($row['plant_name'] ?? '') ?: ('Plant #' . (int)$row['id']);
        }
        $rs->close();
    }
    if ($rs = $conn->query("SELECT id, COALESCE(NULLIF(name,''), CONCAT('Driver #', id)) AS name FROM drivers ORDER BY name ASC")) {
        while ($row = $rs->fetch_assoc()) {
            $drivers[(int)$row['id']] = trim($row['name'] ?? '') ?: ('Driver #' . (int)$row['id']);
        }
        $rs->close();
    }
    if ($rs = $conn->query("SELECT id, COALESCE(NULLIF(full_name,''), username) AS name FROM users ORDER BY name ASC")) {
        while ($row = $rs->fetch_assoc()) {
            $assessors[(int)$row['id']] = trim($row['name'] ?? '') ?: ('User #' . (int)$row['id']);
        }
        $rs->close();
    }
} catch (Throwable $e) {
    // ignore directory load errors
}

$plantFilter = isset($_GET['plant']) ? (int)$_GET['plant'] : null;
if ($plantFilter !== null && $plantFilter <= 0) $plantFilter = null;
$driverFilter = isset($_GET['driver']) ? (int)$_GET['driver'] : null;
if ($driverFilter !== null && $driverFilter <= 0) $driverFilter = null;
$assessorFilter = isset($_GET['assessor']) ? (int)$_GET['assessor'] : null;
if ($assessorFilter !== null && $assessorFilter <= 0) $assessorFilter = null;

$defaultFrom = date('Y-m-01');
$defaultTo = date('Y-m-t');
$fromDate = $_GET['from'] ?? $defaultFrom;
$toDate = $_GET['to'] ?? $defaultTo;
$search = trim((string)($_GET['q'] ?? ''));

$limitOptions = [25, 50, 100, 200];
$limit = isset($_GET['limit']) ? (int)$_GET['limit'] : 50;
if (!in_array($limit, $limitOptions, true)) $limit = 50;
$page = isset($_GET['page']) ? (int)$_GET['page'] : 1;
if ($page < 1) $page = 1;
$offset = ($page - 1) * $limit;

$where = [];
$params = [];
$types = '';

if ($plantFilter) {
    $where[] = 'a.plant_id = ?';
    $params[] = $plantFilter;
    $types .= 'i';
}
if ($driverFilter) {
    $where[] = 'a.driver_id = ?';
    $params[] = $driverFilter;
    $types .= 'i';
}
if ($assessorFilter) {
    $where[] = 'a.assessor_user_id = ?';
    $params[] = $assessorFilter;
    $types .= 'i';
}
if ($fromDate) {
    $where[] = 'a.assessment_date >= ?';
    $params[] = $fromDate;
    $types .= 's';
}
if ($toDate) {
    $where[] = 'a.assessment_date <= ?';
    $params[] = $toDate;
    $types .= 's';
}
if ($search !== '') {
    if (ctype_digit($search)) {
        $where[] = 'a.id = ?';
        $params[] = (int)$search;
        $types .= 'i';
    } else {
        $like = '%' . $search . '%';
        $where[] = "(COALESCE(d.name,'') LIKE ? OR COALESCE(v.vehicle_no,'') LIKE ? OR COALESCE(p.plant_name,'') LIKE ? OR COALESCE(a.weather,'') LIKE ?)";
        array_push($params, $like, $like, $like, $like);
        $types .= 'ssss';
    }
}
$whereSql = $where ? ('WHERE ' . implode(' AND ', $where)) : '';

$summary = ['total' => 0, 'recent' => 0];
try {
    $summaryStmt = $conn->prepare("
        SELECT
            COUNT(*) AS total_count,
            SUM(CASE WHEN a.assessment_date >= DATE_SUB(CURDATE(), INTERVAL 7 DAY) THEN 1 ELSE 0 END) AS recent_count
        FROM in_cab_assessments a
        {$whereSql}
    ");
    if ($types !== '') bindParams($summaryStmt, $types, $params);
    $summaryStmt->execute();
    $row = $summaryStmt->get_result()->fetch_assoc();
    $summaryStmt->close();
    if ($row) {
        $summary['total'] = (int)($row['total_count'] ?? 0);
        $summary['recent'] = (int)($row['recent_count'] ?? 0);
    }
} catch (Throwable $e) {
    $summaryError = $e->getMessage();
}

$listSql = "
    SELECT
        a.*,
        p.plant_name,
        v.vehicle_no,
        d.name AS driver_name,
        u.full_name AS assessor_name
    FROM in_cab_assessments a
    LEFT JOIN plants p ON p.id = a.plant_id
    LEFT JOIN vehicles v ON v.id = a.vehicle_id
    LEFT JOIN drivers d ON d.id = a.driver_id
    LEFT JOIN users u ON u.id = a.assessor_user_id
    {$whereSql}
    ORDER BY a.assessment_date DESC, a.id DESC
    LIMIT ? OFFSET ?
";

$listParams = $params;
$listTypes = $types . 'ii';
$listParams[] = $limit;
$listParams[] = $offset;

$assessments = [];
try {
    $stmt = $conn->prepare($listSql);
    bindParams($stmt, $listTypes, $listParams);
    $stmt->execute();
    $res = $stmt->get_result();
    while ($row = $res->fetch_assoc()) {
        $assessments[] = $row;
    }
    $stmt->close();
} catch (Throwable $e) {
    $listError = $e->getMessage();
}

$totalRows = $summary['total'];
$totalPages = (int)max(1, ceil($totalRows / $limit));
if ($page > $totalPages) $page = $totalPages;

$selectedId = isset($_GET['assessment']) ? (int)$_GET['assessment'] : null;
$selectedAssessment = null;
$selectedItems = [];
if ($selectedId) {
    try {
        $detailStmt = $conn->prepare("
            SELECT
                a.*,
                p.plant_name,
                v.vehicle_no,
                d.name AS driver_name,
                u.full_name AS assessor_name
            FROM in_cab_assessments a
            LEFT JOIN plants p ON p.id = a.plant_id
            LEFT JOIN vehicles v ON v.id = a.vehicle_id
            LEFT JOIN drivers d ON d.id = a.driver_id
            LEFT JOIN users u ON u.id = a.assessor_user_id
            WHERE a.id = ?
            LIMIT 1
        ");
        $detailStmt->bind_param('i', $selectedId);
        $detailStmt->execute();
        $selectedAssessment = $detailStmt->get_result()->fetch_assoc();
        $detailStmt->close();

        if ($selectedAssessment) {
            $itemsStmt = $conn->prepare("
                SELECT section_key, item_code, question_text, result
                FROM in_cab_assessment_items
                WHERE assessment_id = ?
                ORDER BY id ASC
            ");
            $itemsStmt->bind_param('i', $selectedId);
            $itemsStmt->execute();
            $itemsRes = $itemsStmt->get_result();
            while ($row = $itemsRes->fetch_assoc()) {
                $selectedItems[] = $row;
            }
            $itemsStmt->close();
        }
    } catch (Throwable $e) {
        $detailError = $e->getMessage();
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>In-Cab Assessments</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="bg-light">
<nav class="navbar navbar-dark" style="background:#12355B;">
    <div class="container-fluid">
        <span class="navbar-brand mb-0 h4">In-Cab Assessments</span>
        <div class="text-white-50 small">
            Total: <?=h((string)$summary['total'])?> | Last 7 days: <?=h((string)$summary['recent'])?>
        </div>
    </div>
</nav>

<div class="container-fluid py-3">
    <?php if (!empty($summaryError)): ?>
        <div class="alert alert-warning">Summary error: <?=h($summaryError)?></div>
    <?php endif; ?>
    <?php if (!empty($listError)): ?>
        <div class="alert alert-danger">Failed to load list: <?=h($listError)?></div>
    <?php endif; ?>

    <form class="card card-body mb-3 shadow-sm">
        <div class="row g-2">
            <div class="col-sm-2">
                <label class="form-label">Plant</label>
                <select name="plant" class="form-select">
                    <option value="">All</option>
                    <?php foreach ($plants as $id => $name): ?>
                        <option value="<?=$id?>" <?=$plantFilter===$id?'selected':''?>><?=h($name)?></option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="col-sm-2">
                <label class="form-label">Driver</label>
                <select name="driver" class="form-select">
                    <option value="">All</option>
                    <?php foreach ($drivers as $id => $name): ?>
                        <option value="<?=$id?>" <?=$driverFilter===$id?'selected':''?>><?=h($name)?></option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="col-sm-2">
                <label class="form-label">Assessor</label>
                <select name="assessor" class="form-select">
                    <option value="">All</option>
                    <?php foreach ($assessors as $id => $name): ?>
                        <option value="<?=$id?>" <?=$assessorFilter===$id?'selected':''?>><?=h($name)?></option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="col-sm-2">
                <label class="form-label">From</label>
                <input type="date" name="from" value="<?=h($fromDate)?>" class="form-control">
            </div>
            <div class="col-sm-2">
                <label class="form-label">To</label>
                <input type="date" name="to" value="<?=h($toDate)?>" class="form-control">
            </div>
            <div class="col-sm-2">
                <label class="form-label">Search</label>
                <input type="text" name="q" value="<?=h($search)?>" class="form-control" placeholder="Driver / vehicle / id">
            </div>
            <div class="col-sm-2">
                <label class="form-label">Per Page</label>
                <select name="limit" class="form-select">
                    <?php foreach ($limitOptions as $opt): ?>
                        <option value="<?=$opt?>" <?=$limit===$opt?'selected':''?>><?=$opt?></option>
                    <?php endforeach; ?>
                </select>
            </div>
        </div>
        <div class="mt-3 d-flex gap-2">
            <button class="btn btn-primary">Apply Filters</button>
            <a class="btn btn-outline-secondary" href="incab_assessments.php">Reset</a>
        </div>
    </form>

    <div class="card shadow-sm">
        <div class="card-body table-responsive p-0">
            <table class="table table-striped table-hover mb-0 align-middle">
                <thead class="table-light">
                    <tr>
                        <th>ID</th>
                        <th>Date</th>
                        <th>Driver</th>
                        <th>Vehicle</th>
                        <th>Plant</th>
                        <th>Assessor</th>
                        <th>Start → End</th>
                        <th>Weather</th>
                        <th>Notes</th>
                        <th></th>
                    </tr>
                </thead>
                <tbody>
                    <?php if (empty($assessments)): ?>
                        <tr><td colspan="10" class="text-center text-muted py-4">No assessments found.</td></tr>
                    <?php endif; ?>
                    <?php foreach ($assessments as $row): ?>
                        <tr>
                            <td><?=h((string)$row['id'])?></td>
                            <td><?=h(fmtDate($row['assessment_date'] ?? null))?></td>
                            <td><?=h($row['driver_name'] ?? '')?></td>
                            <td><?=h($row['vehicle_no'] ?? '')?></td>
                            <td><?=h($row['plant_name'] ?? '')?></td>
                            <td><?=h($row['assessor_name'] ?? '')?></td>
                            <td>
                                <div class="small text-nowrap"><?=h(fmtDateTime($row['start_time'] ?? null))?></div>
                                <div class="small text-nowrap">→ <?=h(fmtDateTime($row['end_time'] ?? null))?></div>
                            </td>
                            <td><?=h($row['weather'] ?? '')?></td>
                            <td><?=h(mb_strimwidth((string)($row['overall_notes'] ?? ''), 0, 60, '…'))?></td>
                            <td>
                                <a class="btn btn-sm btn-outline-primary" href="incab_assessments.php?<?=http_build_query(array_merge($_GET, ['assessment' => $row['id']]))?>">View</a>
                            </td>
                        </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        </div>
    </div>

    <?php if ($totalPages > 1): ?>
        <nav class="mt-3">
            <ul class="pagination">
                <?php for ($p = 1; $p <= $totalPages; $p++): ?>
                    <li class="page-item <?=$p===$page?'active':''?>">
                        <a class="page-link" href="?<?=http_build_query(array_merge($_GET, ['page'=>$p]))?>"><?=$p?></a>
                    </li>
                <?php endfor; ?>
            </ul>
        </nav>
    <?php endif; ?>

    <?php if ($selectedAssessment): ?>
        <div class="offcanvas offcanvas-end show" tabindex="-1" style="visibility:visible; width:480px;" aria-labelledby="detailOffcanvas">
            <div class="offcanvas-header">
                <h5 class="offcanvas-title" id="detailOffcanvas">Assessment #<?=h((string)$selectedAssessment['id'])?></h5>
                <a href="incab_assessments.php?<?=http_build_query(array_diff_key($_GET, ['assessment'=>true]))?>" class="btn-close"></a>
            </div>
            <div class="offcanvas-body">
                <div class="mb-3">
                    <div class="small text-muted">Date</div>
                    <div><?=h(fmtDate($selectedAssessment['assessment_date'] ?? null))?></div>
                </div>
                <div class="mb-3">
                    <div class="small text-muted">Driver</div>
                    <div><?=h($selectedAssessment['driver_name'] ?? '')?></div>
                </div>
                <div class="mb-3">
                    <div class="small text-muted">Vehicle</div>
                    <div><?=h($selectedAssessment['vehicle_no'] ?? '')?></div>
                </div>
                <div class="mb-3">
                    <div class="small text-muted">Plant</div>
                    <div><?=h($selectedAssessment['plant_name'] ?? '')?></div>
                </div>
                <div class="mb-3">
                    <div class="small text-muted">Assessor</div>
                    <div><?=h($selectedAssessment['assessor_name'] ?? '')?></div>
                </div>
                <div class="mb-3">
                    <div class="small text-muted">Time Window</div>
                    <div><?=h(fmtDateTime($selectedAssessment['start_time'] ?? null))?> → <?=h(fmtDateTime($selectedAssessment['end_time'] ?? null))?></div>
                </div>
                <div class="mb-3">
                    <div class="small text-muted">Weather / Location</div>
                    <div><?=h($selectedAssessment['weather'] ?? '')?> <?=h($selectedAssessment['location_text'] ?? '')?></div>
                </div>
                <div class="mb-3">
                    <div class="small text-muted">Notes</div>
                    <div><?=h($selectedAssessment['overall_notes'] ?? '')?></div>
                </div>
                <h6 class="mt-4">Answers</h6>
                <?php if (empty($selectedItems)): ?>
                    <div class="text-muted">No answers stored.</div>
                <?php else: ?>
                    <div class="list-group small">
                        <?php foreach ($selectedItems as $item): ?>
                            <div class="list-group-item">
                                <div class="fw-semibold"><?=h($item['question_text'] ?? '')?></div>
                                <div class="text-muted">[<?=h($item['section_key'] ?? '')?>] <?=h($item['item_code'] ?? '')?></div>
                                <div class="badge bg-primary mt-1"><?=h($item['result'] ?? '')?></div>
                            </div>
                        <?php endforeach; ?>
                    </div>
                <?php endif; ?>
            </div>
        </div>
        <div class="modal-backdrop fade show"></div>
    <?php endif; ?>
</div>
</body>
</html>
