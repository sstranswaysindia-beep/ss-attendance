<?php
declare(strict_types=1);

session_start();
if (empty($_SESSION['csrf_token'])) {
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
}
$csrfToken = $_SESSION['csrf_token'];

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

function formatDate(?string $value, string $fallback = '–'): string
{
    if (!$value) {
        return $fallback;
    }
    try {
        $dt = new DateTime($value);
        return $dt->format('d M Y');
    } catch (Throwable $e) {
        return $value;
    }
}

function buildPageUrl(array $overrides = []): string
{
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

function normalizeDate(string $raw): ?string
{
    if ($raw === '') {
        return null;
    }
    $dt = DateTime::createFromFormat('Y-m-d', $raw);
    if ($dt === false) {
        return null;
    }
    return $dt->format('Y-m-d');
}

function truncateText(?string $value, int $limit = 80): string
{
    if ($value === null) {
        return '';
    }
    $trimmed = trim($value);
    if ($trimmed === '') {
        return '';
    }
    if (strlen($trimmed) <= $limit) {
        return $trimmed;
    }
    return substr($trimmed, 0, max(1, $limit - 1)) . '…';
}

function bindParams(mysqli_stmt $stmt, string $types, array &$values): void
{
    if ($types === '' || empty($values)) {
        return;
    }
    $refs = [];
    foreach ($values as $key => $value) {
        $refs[$key] = &$values[$key];
    }
    $stmt->bind_param($types, ...$refs);
}

$sectionGuides = [
    'personal_hygiene' => 'Ask driver to wear FRC.',
    'ppes' => 'Ask driver to show PPEs and check condition of fire extinguisher.',
    'emergency_action' => 'Interview him on any applicable scenario.',
    'product_awareness' => 'Interview driver on hazards and what to do in case of leakage or spillage.',
    'cabin_housekeeping' => 'Check functioning of seat belt and overall cleanliness.',
    'accessories' => 'Check listed items for availability and condition.',
    'trem' => 'Driver should quickly produce TREM card.',
    'documents' => 'All statutory and commercial documents should be available.',
];

$questionLabels = [
    'tidy_uniform' => 'Tidy Uniform',
    'tidy_frc' => 'Tidy FRC (if applicable)',
    'ppe_condition' => 'PPE Condition',
    'ppe_available' => 'PPE Availability',
    'fire_extinguisher' => 'Fire Extinguisher',
    'emergency_plan' => 'Understands emergency action plan',
    'product_awareness' => 'Understands product hazards',
    'housekeeping' => 'Overall Cleanliness',
    'seat_condition' => 'Condition of Seats',
    'seat_belt' => 'Seat Belts Condition',
    'banned_substances' => 'Presence of banned substances',
    'valve_cleanliness' => 'Cleanliness of valve box',
    'waste_presence' => 'Presence of waste material',
    'filling_accessories' => 'Availability of filling accessories',
    'vitt_accessories' => 'VITT accessories (hose, nozzle, cones, etc.)',
    'pg_accessories' => 'PG Truck accessories',
    'vehicle_cleanliness' => 'Vehicle Cleanliness',
    'damage_check' => 'No damage to SUPD/RUPD/mudguards',
    'mirror_condition' => 'Condition of mirrors',
    'trem_card' => 'TREM card present',
    'statutory_docs' => 'RC, Pollution, Insurance, PESO, Rule 18 & 19, DL, Hazardous Training Certificate',
    'pod_docs' => 'POD, Invoices',
];

$flashSuccess = $_SESSION['spot_flash_success'] ?? null;
$flashError = $_SESSION['spot_flash_error'] ?? null;
unset($_SESSION['spot_flash_success'], $_SESSION['spot_flash_error']);

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['delete_audit_id'])) {
    $deleteId = filter_var($_POST['delete_audit_id'], FILTER_VALIDATE_INT);
    if ($deleteId && $deleteId > 0) {
        try {
            $conn->begin_transaction();
            $stmtAnswers = $conn->prepare('DELETE FROM safety_spot_audit_answers WHERE audit_id = ?');
            $stmtAnswers->bind_param('i', $deleteId);
            $stmtAnswers->execute();
            $stmtAnswers->close();

            $stmtSections = $conn->prepare('DELETE FROM safety_spot_audit_sections WHERE audit_id = ?');
            $stmtSections->bind_param('i', $deleteId);
            $stmtSections->execute();
            $stmtSections->close();

            $stmtAudit = $conn->prepare('DELETE FROM safety_spot_audits WHERE id = ? LIMIT 1');
            $stmtAudit->bind_param('i', $deleteId);
            $stmtAudit->execute();
            $affected = $stmtAudit->affected_rows;
            $stmtAudit->close();

            $conn->commit();
            if ($affected > 0) {
                $_SESSION['spot_flash_success'] = "Audit #{$deleteId} deleted.";
            } else {
                $_SESSION['spot_flash_error'] = "Audit #{$deleteId} was not found.";
            }
        } catch (Throwable $e) {
            $conn->rollback();
            $_SESSION['spot_flash_error'] = 'Failed to delete audit. Please try again.';
        }
    } else {
        $_SESSION['spot_flash_error'] = 'Invalid audit id.';
    }
    header('Location: ' . buildPageUrl(['audit' => null]));
    exit;
}

$categoryOptions = ['ALL', 'VITT', 'PG'];
$categoryFilter = strtoupper(trim((string)($_GET['category'] ?? 'ALL')));
if (!in_array($categoryFilter, $categoryOptions, true)) {
    $categoryFilter = 'ALL';
}

$plantFilter = isset($_GET['plant']) ? (int)$_GET['plant'] : null;
if ($plantFilter !== null && $plantFilter <= 0) {
    $plantFilter = null;
}

$driverFilter = isset($_GET['driver']) ? (int)$_GET['driver'] : null;
if ($driverFilter !== null && $driverFilter <= 0) {
    $driverFilter = null;
}

$defaultFrom = date('Y-m-01');
$defaultTo = date('Y-m-t');
$fromRaw = isset($_GET['from']) ? trim((string)$_GET['from']) : $defaultFrom;
$toRaw = isset($_GET['to']) ? trim((string)$_GET['to']) : $defaultTo;
$fromDate = normalizeDate($fromRaw) ?: $defaultFrom;
$toDate = normalizeDate($toRaw) ?: $defaultTo;

$searchQuery = trim((string)($_GET['q'] ?? ''));

$limitOptions = [25, 50, 100, 200];
$limit = isset($_GET['limit']) ? (int)$_GET['limit'] : 50;
if (!in_array($limit, $limitOptions, true)) {
    $limit = 50;
}

$page = isset($_GET['page']) ? (int)$_GET['page'] : 1;
if ($page < 1) {
    $page = 1;
}
$offset = ($page - 1) * $limit;

$filterClauses = [];
$filterParams = [];
$filterTypes = '';

if ($plantFilter) {
    $filterClauses[] = 'a.plant_id = ?';
    $filterParams[] = $plantFilter;
    $filterTypes .= 'i';
}

if ($driverFilter) {
    $filterClauses[] = 'a.driver_id = ?';
    $filterParams[] = $driverFilter;
    $filterTypes .= 'i';
}

if ($categoryFilter !== 'ALL') {
    $filterClauses[] = 'a.truck_category = ?';
    $filterParams[] = $categoryFilter;
    $filterTypes .= 's';
}

if ($fromDate) {
    $filterClauses[] = 'a.assessment_date >= ?';
    $filterParams[] = $fromDate;
    $filterTypes .= 's';
}

if ($toDate) {
    $filterClauses[] = 'a.assessment_date <= ?';
    $filterParams[] = $toDate;
    $filterTypes .= 's';
}

if ($searchQuery !== '') {
    if (ctype_digit($searchQuery)) {
        $filterClauses[] = 'a.id = ?';
        $filterParams[] = (int)$searchQuery;
        $filterTypes .= 'i';
    } else {
        $filterClauses[] = "(
            COALESCE(NULLIF(a.vehicle_number, ''), v.vehicle_no) LIKE ? OR
            COALESCE(p.plant_name, '') LIKE ? OR
            COALESCE(d.name, '') LIKE ? OR
            COALESCE(a.highlights, '') LIKE ? OR
            COALESCE(a.assessed_by, '') LIKE ?
        )";
        $like = '%' . $searchQuery . '%';
        array_push($filterParams, $like, $like, $like, $like, $like);
        $filterTypes .= 'sssss';
    }
}

$filterSql = $filterClauses ? (' AND ' . implode(' AND ', $filterClauses)) : '';

$plants = [];
$drivers = [];
try {
    if ($rs = $conn->query('SELECT id, plant_name FROM plants ORDER BY plant_name ASC')) {
        while ($row = $rs->fetch_assoc()) {
            $name = trim($row['plant_name'] ?? '') ?: ('Plant #' . (int)$row['id']);
            $plants[(int)$row['id']] = $name;
        }
        $rs->close();
    }
    if ($rs = $conn->query("SELECT id, COALESCE(NULLIF(name,''), CONCAT('Driver #', id)) AS name FROM drivers ORDER BY name ASC")) {
        while ($row = $rs->fetch_assoc()) {
            $drivers[(int)$row['id']] = trim($row['name'] ?? '') ?: ('Driver #' . (int)$row['id']);
        }
        $rs->close();
    }
} catch (Throwable $e) {
    // ignore lookup failures
}

$summary = [
    'total' => 0,
    'recent' => 0,
    'avg_score' => 0,
    'plants' => 0,
];

try {
    $summarySql = "
        SELECT
            COUNT(*) AS total_audits,
            COUNT(DISTINCT a.plant_id) AS plant_count,
            AVG(a.total_score) AS avg_score,
            SUM(CASE WHEN a.assessment_date >= DATE_SUB(CURDATE(), INTERVAL 7 DAY) THEN 1 ELSE 0 END) AS recent_count
        FROM safety_spot_audits a
        LEFT JOIN plants p ON p.id = a.plant_id
        LEFT JOIN vehicles v ON v.id = a.vehicle_id
        LEFT JOIN drivers d ON d.id = a.driver_id
        WHERE 1=1 {$filterSql}
    ";

    $summaryStmt = $conn->prepare($summarySql);
    if ($filterTypes !== '' && !empty($filterParams)) {
        bindParams($summaryStmt, $filterTypes, $filterParams);
    }
    $summaryStmt->execute();
    $summaryRow = $summaryStmt->get_result()->fetch_assoc();
    $summaryStmt->close();

    if ($summaryRow) {
        $summary['total'] = (int)($summaryRow['total_audits'] ?? 0);
        $summary['plants'] = (int)($summaryRow['plant_count'] ?? 0);
        $summary['recent'] = (int)($summaryRow['recent_count'] ?? 0);
        $avgScore = $summaryRow['avg_score'];
        if ($avgScore !== null) {
            $summary['avg_score'] = round((float)$avgScore, 1);
        }
    }
} catch (Throwable $e) {
    $summaryError = $e->getMessage();
}

$listSql = "
    SELECT
        a.id,
        a.plant_id,
        a.vehicle_id,
        a.vehicle_number,
        a.driver_id,
        a.assessment_date,
        a.target_date,
        a.total_score,
        a.truck_category,
        a.language_code,
        a.highlights,
        a.assessed_by,
        a.action_plan,
        a.created_by,
        p.plant_name,
        v.vehicle_no,
        d.name AS driver_name,
        d.empid
    FROM safety_spot_audits a
    LEFT JOIN plants p ON p.id = a.plant_id
    LEFT JOIN vehicles v ON v.id = a.vehicle_id
    LEFT JOIN drivers d ON d.id = a.driver_id
    WHERE 1=1 {$filterSql}
    ORDER BY a.assessment_date DESC, a.id DESC
    LIMIT ? OFFSET ?
";

$listParams = $filterParams;
$listTypes = $filterTypes . 'ii';
$listParams[] = $limit;
$listParams[] = $offset;

$audits = [];
try {
    $listStmt = $conn->prepare($listSql);
    bindParams($listStmt, $listTypes, $listParams);
    $listStmt->execute();
    $result = $listStmt->get_result();
    while ($row = $result->fetch_assoc()) {
        $audits[] = $row;
    }
    $listStmt->close();
} catch (Throwable $e) {
    $listError = $e->getMessage();
}

$totalRows = $summary['total'];
$totalPages = (int)max(1, ceil($totalRows / $limit));
if ($page > $totalPages) {
    $page = $totalPages;
}

$selectedAuditId = isset($_GET['audit']) ? (int)$_GET['audit'] : null;
$selectedAudit = null;
$selectedSections = [];
$selectedError = null;

if ($selectedAuditId) {
    try {
        $detailStmt = $conn->prepare("
            SELECT
                a.*, p.plant_name, v.vehicle_no,
                d.name AS driver_name, d.empid
            FROM safety_spot_audits a
            LEFT JOIN plants p ON p.id = a.plant_id
            LEFT JOIN vehicles v ON v.id = a.vehicle_id
            LEFT JOIN drivers d ON d.id = a.driver_id
            WHERE a.id = ?
            LIMIT 1
        ");
        $detailStmt->bind_param('i', $selectedAuditId);
        $detailStmt->execute();
        $selectedAudit = $detailStmt->get_result()->fetch_assoc() ?: null;
        $detailStmt->close();

        if ($selectedAudit) {
            $sectionsStmt = $conn->prepare('SELECT section_key, section_label, average_score, comments FROM safety_spot_audit_sections WHERE audit_id = ? ORDER BY id ASC');
            $sectionsStmt->bind_param('i', $selectedAuditId);
            $sectionsStmt->execute();
            $sectionsRes = $sectionsStmt->get_result();
            while ($row = $sectionsRes->fetch_assoc()) {
                $key = $row['section_key'] ?: uniqid('section_', false);
                $selectedSections[$key] = [
                    'key' => $row['section_key'],
                    'label' => $row['section_label'] ?: ($row['section_key'] ?: 'Section'),
                    'score' => (int)$row['average_score'],
                    'comments' => $row['comments'] ?? '',
                    'answers' => [],
                    'guide' => $sectionGuides[$row['section_key']] ?? '',
                ];
            }
            $sectionsStmt->close();

            $answersStmt = $conn->prepare('SELECT section_key, question_key, choice_value, numeric_score, extra_comment FROM safety_spot_audit_answers WHERE audit_id = ? ORDER BY id ASC');
            $answersStmt->bind_param('i', $selectedAuditId);
            $answersStmt->execute();
            $answersRes = $answersStmt->get_result();
            while ($row = $answersRes->fetch_assoc()) {
                $sectionKey = $row['section_key'];
                if (!isset($selectedSections[$sectionKey])) {
                    $selectedSections[$sectionKey] = [
                        'key' => $sectionKey,
                        'label' => $sectionKey ?: 'Section',
                        'score' => null,
                        'comments' => '',
                        'answers' => [],
                        'guide' => $sectionGuides[$sectionKey] ?? '',
                    ];
                }
                $selectedSections[$sectionKey]['answers'][] = $row;
            }
            $answersStmt->close();
        } else {
            $selectedError = 'Audit #' . $selectedAuditId . ' was not found.';
        }
    } catch (Throwable $e) {
        $selectedError = $e->getMessage();
    }
}

?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Spot Audits — Safety</title>
<link href="https://fonts.googleapis.com/css2?family=Josefin+Sans:wght@400;600;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<style>
    :root{ --ink:#0f172a; --muted:#64748b; --bg:#f5f7fb; --line:#e2e8f0; --accent:#0ea5e9; }
    body{ background:var(--bg); font-family:'Josefin Sans',system-ui,-apple-system,Segoe UI,Roboto,sans-serif; }
    .page-header{ margin-bottom:24px; }
    .crumbs{ color:var(--muted); font-size:.9rem; }
    .stat-card{ border-radius:18px; padding:18px; color:#fff; box-shadow:0 6px 20px rgba(15,23,42,.08); }
    .stat-label{ font-size:.8rem; text-transform:uppercase; letter-spacing:.08em; opacity:.9; }
    .stat-value{ font-size:1.8rem; font-weight:700; }
    .stat-card small{ color:rgba(255,255,255,.85)!important; }
    .grad-1{ background:linear-gradient(135deg,#2563eb,#60a5fa); }
    .grad-2{ background:linear-gradient(135deg,#0ea5e9,#38bdf8); }
    .grad-3{ background:linear-gradient(135deg,#f97316,#fb923c); }
    .grad-4{ background:linear-gradient(135deg,#22c55e,#4ade80); }
    .table thead th{ text-transform:uppercase; font-size:.72rem; letter-spacing:.08em; color:var(--muted); border-bottom:none; }
    .table tbody td{ vertical-align:middle; border-color:var(--line); }
    .badge-category{ border-radius:999px; padding:.3rem .75rem; font-size:.75rem; text-transform:uppercase; }
    .badge-VITT{ background:#dbeafe; color:#1d4ed8; }
    .badge-PG{ background:#fee2e2; color:#b91c1c; }
    .detail-card{ border-radius:20px; background:#fff; box-shadow:0 15px 45px rgba(15,23,42,.12); }
    .section-block{ border:1px solid var(--line); border-radius:14px; padding:16px; margin-bottom:14px; background:rgba(14,165,233,.04); }
    .answers-list{ list-style:none; padding-left:0; margin-bottom:0; }
    .answers-list li{ padding:6px 0; border-bottom:1px dashed var(--line); }
    .answers-list li:last-child{ border-bottom:none; }
    .filter-toolbar .form-control,
    .filter-toolbar .form-select{ border-radius:10px; }
</style>
</head>
<body>
<div class="container-fluid py-4">
    <div class="page-header d-flex align-items-center gap-3">
        <a href="https://sstranswaysindia.com/DriverDocs/safety.php" class="btn btn-outline-secondary">
            <i class="fa-solid fa-arrow-left-long"></i>
        </a>
        <div>
            <div class="crumbs mb-1"><i class="fa-solid fa-clipboard-check me-2"></i>Safety / Spot Audits</div>
            <h1 class="h3 mb-1">Spot Audits</h1>
            <p class="text-muted mb-0">Browse submitted spot audits, filter by plant, driver, category, or date, and review individual answers.</p>
        </div>
    </div>

    <?php if ($flashSuccess): ?>
        <div class="alert alert-success"><i class="fa-solid fa-circle-check me-2"></i><?= h($flashSuccess) ?></div>
    <?php endif; ?>
    <?php if ($flashError): ?>
        <div class="alert alert-danger"><i class="fa-solid fa-triangle-exclamation me-2"></i><?= h($flashError) ?></div>
    <?php endif; ?>

    <div class="row g-3 mb-4">
        <div class="col-sm-6 col-lg-3">
            <div class="stat-card grad-1">
                <div class="stat-label">Total audits</div>
                <div class="stat-value"><?= number_format($summary['total']) ?></div>
                <small class="text-muted">Across all filters</small>
            </div>
        </div>
        <div class="col-sm-6 col-lg-3">
            <div class="stat-card grad-2">
                <div class="stat-label">Unique plants</div>
                <div class="stat-value"><?= number_format($summary['plants']) ?></div>
                <small class="text-muted">Plants represented</small>
            </div>
        </div>
        <div class="col-sm-6 col-lg-3">
            <div class="stat-card grad-3">
                <div class="stat-label">Average score</div>
                <div class="stat-value"><?= $summary['avg_score'] ? h((string)$summary['avg_score']) : '–' ?></div>
                <small class="text-muted">Out of total score</small>
            </div>
        </div>
        <div class="col-sm-6 col-lg-3">
            <div class="stat-card grad-4">
                <div class="stat-label">Last 7 days</div>
                <div class="stat-value"><?= number_format($summary['recent']) ?></div>
                <small class="text-muted">Audits submitted</small>
            </div>
        </div>
    </div>

    <?php if ($selectedError): ?>
        <div class="alert alert-danger"><i class="fa-solid fa-triangle-exclamation me-2"></i><?= h($selectedError) ?></div>
    <?php endif; ?>

    <?php if ($selectedAudit): ?>
        <div class="detail-card p-4 mb-4">
            <div class="d-flex justify-content-between align-items-start flex-wrap gap-3">
                <div>
                    <div class="text-secondary">Audit #<?= h((string)$selectedAudit['id']) ?></div>
                    <h2 class="h4 mb-1"><?= h($selectedAudit['plant_name'] ?: ('Plant #' . $selectedAudit['plant_id'])) ?></h2>
                    <div class="text-muted">Assessed on <?= formatDate($selectedAudit['assessment_date']) ?> · by <?= h($selectedAudit['assessed_by'] ?: 'Not specified') ?></div>
                </div>
                <div class="text-end">
                    <div class="badge badge-category badge-<?= h($selectedAudit['truck_category'] ?? 'VITT') ?>">
                        <?= h($selectedAudit['truck_category'] ?? 'VITT') ?>
                    </div>
                    <div class="fs-3 fw-bold text-primary mt-2">Score: <?= h((string)$selectedAudit['total_score']) ?></div>
                    <div class="d-flex flex-wrap gap-2 justify-content-end mt-2">
                        <!-- UPDATED: use JS + fetch to generate & download PDF -->
                         <form method="post"
      action="https://sstranswaysindia.com/DriverDocs/api/spot_audit_pdf.php"
      class="d-inline spot-pdf-form">
    <input type="hidden" name="csrf_token" value="<?= h($csrfToken) ?>">
    <input type="hidden" name="audit_id" value="<?= (int)$selectedAudit['id'] ?>">
    <input type="hidden" name="share_public" value="1">
    <button type="button" class="btn btn-sm btn-success btn-generate-spot-pdf">
        <i class="fa-solid fa-file-pdf me-1"></i>Generate PDF
    </button>
</form>


                        <a class="btn btn-outline-secondary btn-sm" href="<?= h(buildPageUrl(['audit' => null])) ?>">Close detail</a>
                        <form method="post" onsubmit="return confirm('Delete audit #<?= h((string)$selectedAudit['id']) ?>?');">
                            <input type="hidden" name="delete_audit_id" value="<?= (int)$selectedAudit['id'] ?>">
                            <button type="submit" class="btn btn-sm btn-danger">
                                <i class="fa-solid fa-trash-can me-1"></i>Delete
                            </button>
                        </form>
                    </div>
                </div>
            </div>
            <div class="row mt-3">
                <div class="col-md-4">
                    <div class="mb-2"><strong>Vehicle:</strong> <?= h($selectedAudit['vehicle_number'] ?: ($selectedAudit['vehicle_no'] ?? 'N/A')) ?></div>
                    <div class="mb-2"><strong>Driver:</strong> <?= h($selectedAudit['driver_name'] ?: ('Driver #' . $selectedAudit['driver_id'])) ?></div>
                    <div class="mb-2"><strong>Language:</strong> <?= strtoupper(h($selectedAudit['language_code'] ?? 'en')) ?></div>
                </div>
                <div class="col-md-4">
                    <div class="mb-2"><strong>Transporter:</strong> <?= h($selectedAudit['transporter_name'] ?? 'SS Transways India') ?></div>
                    <div class="mb-2"><strong>Target date:</strong> <?= formatDate($selectedAudit['target_date']) ?></div>
                    <div class="mb-2"><strong>Highlights:</strong> <?= nl2br(h($selectedAudit['highlights'] ?? 'None')) ?></div>
                </div>
                <div class="col-md-4">
                    <div class="mb-2"><strong>Action plan:</strong></div>
                    <div class="bg-light rounded p-2" style="min-height:60px;">
                        <?= nl2br(h($selectedAudit['action_plan'] ?? 'No action plan recorded')) ?>
                    </div>
                </div>
            </div>
            <?php if (!empty($selectedSections)): ?>
                <div class="mt-4">
                    <h5 class="mb-3">Section responses</h5>
                    <div class="row">
                        <?php foreach ($selectedSections as $section): ?>
                            <div class="col-md-6">
                                <div class="section-block">
                                    <div class="d-flex justify-content-between align-items-center mb-2">
                                        <div class="fw-semibold"><?= h($section['label']) ?></div>
                                        <?php if ($section['score'] !== null): ?>
                                            <span class="badge bg-primary-subtle text-primary">Score: <?= h((string)$section['score']) ?></span>
                                        <?php endif; ?>
                                    </div>
                                    <?php if (!empty($section['guide'])): ?>
                                        <div class="text-muted small mb-2"><?= h($section['guide']) ?></div>
                                    <?php endif; ?>
                                    <?php if (!empty($section['answers'])): ?>
                                        <ul class="answers-list">
                                            <?php foreach ($section['answers'] as $answer): ?>
                                                <li>
                                                    <?php
                                                        $questionKey = $answer['question_key'] ?? '';
                                                        $questionLabel = $questionLabels[$questionKey] ?? $questionKey;
                                                    ?>
                                                    <div class="fw-semibold"><?= h($questionLabel) ?></div>
                                                    <div class="text-muted small">Choice: <?= h($answer['choice_value'] ?? '') ?><?php if ($answer['numeric_score'] !== null): ?> · Score <?= h((string)$answer['numeric_score']) ?><?php endif; ?></div>
                                                    <?php if (!empty($answer['extra_comment'])): ?>
                                                        <div class="small mt-1">Comment: <?= h($answer['extra_comment']) ?></div>
                                                    <?php endif; ?>
                                                </li>
                                            <?php endforeach; ?>
                                        </ul>
                                    <?php else: ?>
                                        <div class="text-muted">No answers recorded.</div>
                                    <?php endif; ?>
                                    <?php if (!empty($section['comments'])): ?>
                                        <div class="mt-2 small text-muted">Notes: <?= h($section['comments']) ?></div>
                                    <?php endif; ?>
                                </div>
                            </div>
                        <?php endforeach; ?>
                    </div>
                </div>
            <?php else: ?>
                <div class="alert alert-info mt-3 mb-0"><i class="fa-solid fa-circle-info me-2"></i>No section responses stored for this audit.</div>
            <?php endif; ?>
        </div>
    <?php endif; ?>

    <?php if (!empty($listError)): ?>
        <div class="alert alert-danger"><i class="fa-solid fa-triangle-exclamation me-2"></i><?= h($listError) ?></div>
    <?php elseif (empty($audits)): ?>
        <div class="alert alert-info"><i class="fa-solid fa-circle-info me-2"></i>No spot audits found for the selected filters.</div>
    <?php else: ?>
        <form class="card shadow-sm border-0 mb-3 filter-toolbar" id="filterToolbar" method="get">
            <div class="card-body row g-2 align-items-center">
                <div class="col-12 col-lg-3">
                    <input type="text" class="form-control filter-control" name="q" placeholder="Search audit, plant, vehicle" value="<?= h($searchQuery) ?>">
                </div>
                <div class="col-6 col-lg-1">
                    <select name="category" class="form-select filter-control">
                        <option value="ALL" <?= $categoryFilter === 'ALL' ? 'selected' : '' ?>>All</option>
                        <option value="VITT" <?= $categoryFilter === 'VITT' ? 'selected' : '' ?>>VITT</option>
                        <option value="PG" <?= $categoryFilter === 'PG' ? 'selected' : '' ?>>PG</option>
                    </select>
                </div>
                <div class="col-6 col-lg-2">
                    <select name="plant" class="form-select filter-control">
                        <option value="">All plants</option>
                        <?php foreach ($plants as $id => $name): ?>
                            <option value="<?= $id ?>" <?= $plantFilter === $id ? 'selected' : '' ?>><?= h($name) ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <div class="col-6 col-lg-2">
                    <select name="driver" class="form-select filter-control">
                        <option value="">All drivers</option>
                        <?php foreach ($drivers as $id => $name): ?>
                            <option value="<?= $id ?>" <?= $driverFilter === $id ? 'selected' : '' ?>><?= h($name) ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <div class="col-6 col-lg-1">
                    <input type="date" class="form-control filter-control" name="from" value="<?= h($fromDate ?? '') ?>" placeholder="From">
                </div>
                <div class="col-6 col-lg-1">
                    <input type="date" class="form-control filter-control" name="to" value="<?= h($toDate ?? '') ?>" placeholder="To">
                </div>
                <div class="col-6 col-lg-2 d-flex align-items-center gap-2">
                    <select name="limit" class="form-select filter-control flex-grow-1">
                        <?php foreach ($limitOptions as $opt): ?>
                            <option value="<?= $opt ?>" <?= $limit === $opt ? 'selected' : '' ?>><?= $opt ?>/pg</option>
                        <?php endforeach; ?>
                    </select>
                    <a href="spot_audits.php" class="btn btn-outline-secondary">
                        <i class="fa-solid fa-rotate-left"></i>
                    </a>
                </div>
            </div>
        </form>

        <div class="card shadow-sm border-0 mb-4">
            <div class="card-body p-0">
                <div class="table-responsive">
                    <table class="table align-middle mb-0">
                        <thead>
                            <tr>
                                <th>Audit</th>
                                <th>Plant / Vehicle</th>
                                <th>Driver</th>
                                <th>Score</th>
                                <th>Category</th>
                                <th>Assessment date</th>
                                <th>Highlights</th>
                                <th>Report</th>
                                <th class="text-end">Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($audits as $audit): ?>
                                <?php
                                    $vehicleLabel = $audit['vehicle_number'] ?: ($audit['vehicle_no'] ?? ('Vehicle #' . ($audit['vehicle_id'] ?: 0)));
                                    $plantLabel = $audit['plant_name'] ?: ('Plant #' . ($audit['plant_id'] ?: 0));
                                    $driverLabel = $audit['driver_name'] ?: ($audit['driver_id'] ? ('Driver #' . $audit['driver_id']) : '—');
                                    $category = $audit['truck_category'] ?: 'VITT';
                                ?>
                                <tr>
                                    <td>
                                        <div class="fw-semibold">#<?= h((string)$audit['id']) ?></div>
                                        <small class="text-muted">Language <?= strtoupper(h($audit['language_code'] ?? 'EN')) ?></small>
                                    </td>
                                    <td>
                                        <div class="fw-semibold"><?= h($plantLabel) ?></div>
                                        <small class="text-muted">Vehicle: <?= h($vehicleLabel) ?></small>
                                    </td>
                                    <td>
                                        <div><?= h($driverLabel) ?></div>
                                        <?php if (!empty($audit['empid'])): ?>
                                            <small class="text-muted">EmpID: <?= h($audit['empid']) ?></small>
                                        <?php endif; ?>
                                    </td>
                                    <td class="fw-bold text-primary"><?= h((string)$audit['total_score']) ?></td>
                                    <td><span class="badge badge-category badge-<?= h($category) ?>"><?= h($category) ?></span></td>
                                    <td><?= formatDate($audit['assessment_date']) ?></td>
                                    <td><?= h(truncateText($audit['highlights'] ?? '', 60)) ?></td>
                                    <td>
                                        <!-- UPDATED: use JS + fetch to generate & download PDF -->
                                        <form method="post"
      action="https://sstranswaysindia.com/DriverDocs/api/spot_audit_pdf.php"
      class="d-flex gap-2 spot-pdf-form">
    <input type="hidden" name="csrf_token" value="<?= h($csrfToken) ?>">
    <input type="hidden" name="audit_id" value="<?= (int)$audit['id'] ?>">
    <input type="hidden" name="share_public" value="1">
    <button type="button" class="btn btn-sm btn-outline-success btn-generate-spot-pdf">
        <i class="fa-solid fa-file-lines me-1"></i>Generate
    </button>
</form>

                                    </td>
                                    <td class="text-end">
                                        <a class="btn btn-sm btn-outline-primary" href="<?= h(buildPageUrl(['audit' => $audit['id']])) ?>">
                                            <i class="fa-solid fa-eye me-1"></i>View
                                        </a>
                                        <form method="post" class="d-inline" onsubmit="return confirm('Delete audit #<?= h((string)$audit['id']) ?>?');">
                                            <input type="hidden" name="delete_audit_id" value="<?= (int)$audit['id'] ?>">
                                            <button type="submit" class="btn btn-sm btn-danger">
                                                <i class="fa-solid fa-trash-can"></i>
                                            </button>
                                        </form>
                                    </td>
                                </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

        <?php if ($totalPages > 1): ?>
            <nav>
                <ul class="pagination">
                    <li class="page-item <?= $page <= 1 ? 'disabled' : '' ?>">
                        <a class="page-link" href="<?= h(buildPageUrl(['page' => $page - 1])) ?>">Previous</a>
                    </li>
                    <?php for ($i = 1; $i <= $totalPages; $i++): ?>
                        <li class="page-item <?= $i === $page ? 'active' : '' ?>">
                            <a class="page-link" href="<?= h(buildPageUrl(['page' => $i])) ?>"><?= $i ?></a>
                        </li>
                    <?php endfor; ?>
                    <li class="page-item <?= $page >= $totalPages ? 'disabled' : '' ?>">
                        <a class="page-link" href="<?= h(buildPageUrl(['page' => $page + 1])) ?>">Next</a>
                    </li>
                </ul>
            </nav>
        <?php endif; ?>
    <?php endif; ?>
</div>
<script>
  (function(){
    const form = document.getElementById('filterToolbar');
    if(!form) return;
    let debounce;
    form.querySelectorAll('.filter-control').forEach(control => {
      const eventName = control.tagName === 'INPUT' && control.type === 'text' ? 'input' : 'change';
      control.addEventListener(eventName, () => {
        clearTimeout(debounce);
        const submit = () => form.submit();
        if (eventName === 'input') {
          debounce = setTimeout(submit, 500);
        } else {
          submit();
        }
      });
    });
  })();
</script>

<!-- NEW: JS for PDF generation + download -->
<script>
(function () {
    const forms = document.querySelectorAll('.spot-pdf-form');
    if (!forms.length) return;

    forms.forEach(form => {
        const btn = form.querySelector('.btn-generate-spot-pdf');
        if (!btn) return;

        btn.addEventListener('click', async function () {
            const originalHtml = btn.innerHTML;
            btn.disabled = true;
            btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin me-1"></i>Generating...';

            try {
                const formData = new FormData(form);
                const res = await fetch(form.action, {
                    method: 'POST',
                    body: formData
                });

                let data;
                try {
                    data = await res.json();
                } catch (err) {
                    alert('Unexpected response from server.');
                    console.error('JSON parse error:', err);
                    return;
                }

                if (!res.ok || !data || !data.success) {
                    const msg = (data && data.message) ? data.message : 'Failed to generate PDF.';
                    alert(msg);
                    console.error('Spot audit PDF error:', data);
                    return;
                }

                const downloadUrl = data.download || data.preview;
                if (!downloadUrl) {
                    alert('PDF generated but no download URL returned.');
                    console.error('Missing download URL:', data);
                    return;
                }

                const a = document.createElement('a');
                a.href = downloadUrl;
                a.target = '_blank';
                a.rel = 'noopener';
                document.body.appendChild(a);
                a.click();
                a.remove();

            } catch (err) {
                console.error('Spot audit PDF request failed:', err);
                alert('Error connecting to server. Please try again.');
            } finally {
                btn.disabled = false;
                btn.innerHTML = originalHtml;
            }
        });
    });
})();
</script>
</body>
</html>
