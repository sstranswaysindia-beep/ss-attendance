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

function h(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES, 'UTF-8');
}

function formatDate(?string $value): string
{
    if (!$value) {
        return '–';
    }
    try {
        $dt = new DateTime($value);
        return $dt->format('d M Y · H:i');
    } catch (Throwable $e) {
        return $value;
    }
}

$statusOptions = ['all', 'draft', 'submitted', 'approved', 'rejected'];
$statusFilter = strtolower(trim($_GET['status'] ?? 'draft'));
if (!in_array($statusFilter, $statusOptions, true)) {
    $statusFilter = 'draft';
}

$plantFilter = isset($_GET['plant']) ? (int)$_GET['plant'] : null;
$searchQuery = trim((string)($_GET['q'] ?? ''));
$limit = isset($_GET['limit']) ? (int)$_GET['limit'] : 50;
if ($limit <= 0 || $limit > 200) {
    $limit = 50;
}

$plants = [];
try {
    $plantResult = $conn->query('SELECT id, plant_name FROM plants ORDER BY plant_name ASC');
    if ($plantResult) {
        while ($row = $plantResult->fetch_assoc()) {
            $plants[(int)$row['id']] = $row['plant_name'] ?? ('Plant #' . $row['id']);
        }
        $plantResult->close();
    }
} catch (Throwable $e) {
    // ignore plant lookup failure; page can still render
}

$params = [];
$types = '';
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
    v.registration_no,
    p.plant_name,
    d.name AS driver_name,
    d.empid AS driver_code,
    COUNT(t.id) AS total_tyres,
    SUM(CASE WHEN t.status IS NOT NULL THEN 1 ELSE 0 END) AS answered_tyres,
    SUM(CASE WHEN t.status = 'issue' THEN 1 ELSE 0 END) AS issue_tyres,
    SUM(CASE WHEN t.status = 'caution' THEN 1 ELSE 0 END) AS caution_tyres
FROM tyre_inspections ti
LEFT JOIN tyre_inspection_tyres t ON t.inspection_id = ti.id
LEFT JOIN vehicles v ON v.id = ti.vehicle_id
LEFT JOIN plants p ON p.id = ti.plant_id
LEFT JOIN drivers d ON d.id = ti.driver_id
WHERE 1 = 1
";

if ($statusFilter !== 'all') {
    $sql .= ' AND ti.status = ?';
    $params[] = $statusFilter;
    $types .= 's';
}

if ($plantFilter) {
    $sql .= ' AND ti.plant_id = ?';
    $params[] = $plantFilter;
    $types .= 'i';
}

if ($searchQuery !== '') {
    if (ctype_digit($searchQuery)) {
        $sql .= ' AND ti.id = ?';
        $params[] = (int)$searchQuery;
        $types .= 'i';
    } else {
        $sql .= ' AND (v.vehicle_no LIKE ? OR COALESCE(p.plant_name, \'\') LIKE ?)';
        $like = '%' . $searchQuery . '%';
        $params[] = $like;
        $params[] = $like;
        $types .= 'ss';
    }
}

$sql .= '
GROUP BY ti.id
ORDER BY ti.updated_at DESC
LIMIT ?
';
$params[] = $limit;
$types .= 'i';

$inspections = [];
$errorMessage = null;

try {
    $stmt = $conn->prepare($sql);
    if ($params) {
        $stmt->bind_param($types, ...$params);
    }
    $stmt->execute();
    $result = $stmt->get_result();
    while ($row = $result->fetch_assoc()) {
        $inspections[] = $row;
    }
    $stmt->close();
} catch (Throwable $e) {
    $errorMessage = 'Unable to load inspections: ' . $e->getMessage();
}

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

foreach ($inspections as $row) {
    $summary['total']++;
    $status = strtolower($row['status'] ?? 'draft');
    if (isset($summary[$status])) {
        $summary[$status]++;
    }
    $summary['tyres_total'] += (int)$row['total_tyres'];
    $summary['tyres_done'] += (int)$row['answered_tyres'];
    $summary['tyres_issue'] += (int)$row['issue_tyres'];
    $summary['tyres_caution'] += (int)$row['caution_tyres'];
}

$completionPct = $summary['tyres_total'] > 0
    ? round(($summary['tyres_done'] / $summary['tyres_total']) * 100)
    : 0;

?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Safety Inspections Dashboard</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
    <style>
        body {
            background: #f3f6fb;
            font-family: 'Inter', 'Segoe UI', sans-serif;
        }
        .page-header {
            margin-bottom: 24px;
        }
        .stat-card {
            border-radius: 18px;
            padding: 18px;
            background: #fff;
            box-shadow: 0 6px 20px rgba(15, 23, 42, 0.08);
        }
        .stat-label {
            font-size: 0.85rem;
            text-transform: uppercase;
            letter-spacing: 0.08em;
            color: #64748b;
        }
        .stat-value {
            font-size: 1.9rem;
            font-weight: 700;
            color: #0f172a;
        }
        .badge-status {
            text-transform: capitalize;
            font-size: 0.75rem;
            padding: 0.35rem 0.65rem;
            border-radius: 999px;
        }
        .badge-draft     { background: #fde68a; color: #92400e; }
        .badge-submitted { background: #c7d2fe; color: #1d4ed8; }
        .badge-approved  { background: #bbf7d0; color: #047857; }
        .badge-rejected  { background: #fecaca; color: #b91c1c; }
        .issue-chip {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 4px 10px;
            border-radius: 999px;
            font-size: 0.75rem;
            font-weight: 600;
            background: #fee2e2;
            color: #b91c1c;
        }
        .caution-chip {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 4px 10px;
            border-radius: 999px;
            font-size: 0.75rem;
            font-weight: 600;
            background: #fef3c7;
            color: #92400e;
        }
        .table thead th {
            text-transform: uppercase;
            font-size: 0.75rem;
            color: #64748b;
            border-bottom: none;
            letter-spacing: 0.08em;
        }
        .table tbody td {
            vertical-align: middle;
            border-color: #e2e8f0;
        }
        .progress {
            height: 6px;
            background: #e2e8f0;
        }
        .progress-bar {
            border-radius: 999px;
        }
    </style>
</head>
<body>
<div class="container-fluid py-4">
    <div class="page-header d-flex flex-column flex-md-row align-items-md-center justify-content-between gap-3">
        <div>
            <h1 class="h3 mb-1">Safety Inspections</h1>
            <p class="text-muted mb-0">Track tyre checklist progress across your fleet.</p>
        </div>
        <form class="row gy-2 gx-2 align-items-center" method="get">
            <div class="col-auto">
                <input type="text" name="q" class="form-control" placeholder="Search inspection or vehicle"
                       value="<?= h($searchQuery) ?>">
            </div>
            <div class="col-auto">
                <select name="status" class="form-select">
                    <?php foreach ($statusOptions as $option): ?>
                        <option value="<?= h($option) ?>" <?= $statusFilter === $option ? 'selected' : '' ?>>
                            <?= ucfirst($option) ?>
                        </option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="col-auto">
                <select name="plant" class="form-select">
                    <option value="">All plants</option>
                    <?php foreach ($plants as $id => $name): ?>
                        <option value="<?= $id ?>" <?= ($plantFilter === $id) ? 'selected' : '' ?>>
                            <?= h($name) ?>
                        </option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="col-auto">
                <select name="limit" class="form-select">
                    <?php foreach ([25, 50, 100, 200] as $opt): ?>
                        <option value="<?= $opt ?>" <?= $limit === $opt ? 'selected' : '' ?>>
                            Show <?= $opt ?>
                        </option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="col-auto">
                <button type="submit" class="btn btn-primary">
                    <i class="fa-solid fa-filter me-2"></i>Apply
                </button>
            </div>
        </form>
    </div>

    <div class="row g-3 mb-4">
        <div class="col-md-3 col-sm-6">
            <div class="stat-card">
                <div class="stat-label">Total inspections</div>
                <div class="stat-value"><?= $summary['total'] ?></div>
                <div class="text-muted small">Draft: <?= $summary['draft'] ?> · Submitted: <?= $summary['submitted'] ?></div>
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
                <div class="text-muted small">Across all draft inspections</div>
            </div>
        </div>
        <div class="col-md-3 col-sm-6">
            <div class="stat-card">
                <div class="stat-label text-danger">Issue tyres</div>
                <div class="stat-value text-danger"><?= $summary['tyres_issue'] ?></div>
                <div class="text-muted small">Requires immediate attention</div>
            </div>
        </div>
    </div>

    <?php if ($errorMessage): ?>
        <div class="alert alert-danger d-flex align-items-center" role="alert">
            <i class="fa-solid fa-triangle-exclamation me-2"></i>
            <?= h($errorMessage) ?>
        </div>
    <?php endif; ?>

    <?php if (!$errorMessage && empty($inspections)): ?>
        <div class="alert alert-info">
            <i class="fa-solid fa-circle-info me-2"></i>
            No inspections found for the selected filters.
        </div>
    <?php else: ?>
        <div class="card shadow-sm border-0">
            <div class="card-body p-0">
                <div class="table-responsive">
                    <table class="table align-middle mb-0">
                        <thead>
                        <tr>
                            <th scope="col">Inspection</th>
                            <th scope="col">Vehicle</th>
                            <th scope="col">Plant</th>
                            <th scope="col">Driver</th>
                            <th scope="col">Tyres (done)</th>
                            <th scope="col">Alerts</th>
                            <th scope="col">Status</th>
                            <th scope="col">Last update</th>
                        </tr>
                        </thead>
                        <tbody>
                        <?php foreach ($inspections as $row): ?>
                            <?php
                            $totalTyres = (int)$row['total_tyres'];
                            $answeredTyres = (int)$row['answered_tyres'];
                            $issueTyres = (int)$row['issue_tyres'];
                            $cautionTyres = (int)$row['caution_tyres'];
                            $progress = $totalTyres > 0 ? round(($answeredTyres / $totalTyres) * 100) : 0;
                            $status = strtolower($row['status'] ?? 'draft');
                            $statusClass = 'badge-status badge-' . $status;
                            ?>
                            <tr>
                                <td>
                                    <div class="fw-semibold text-dark">#<?= (int)$row['id'] ?></div>
                                    <div class="text-muted small">Started <?= formatDate($row['started_at']) ?></div>
                                </td>
                                <td>
                                    <div class="fw-semibold"><?= h($row['vehicle_no'] ?? ('Vehicle #' . $row['vehicle_id'])) ?></div>
                                    <?php if (!empty($row['registration_no'])): ?>
                                        <div class="text-muted small"><?= h($row['registration_no']) ?></div>
                                    <?php endif; ?>
                                </td>
                                <td><?= h($row['plant_name'] ?? ('Plant #' . $row['plant_id'])) ?></td>
                                <td>
                                    <?php if (!empty($row['driver_name'])): ?>
                                        <?= h($row['driver_name']) ?>
                                        <div class="text-muted small"><?= h($row['driver_code'] ?? '') ?></div>
                                    <?php else: ?>
                                        <span class="text-muted">–</span>
                                    <?php endif; ?>
                                </td>
                                <td style="width: 180px;">
                                    <div class="fw-semibold"><?= $answeredTyres ?> / <?= $totalTyres ?></div>
                                    <div class="progress mt-1">
                                        <div class="progress-bar bg-success" role="progressbar" style="width: <?= $progress ?>%;"></div>
                                    </div>
                                </td>
                                <td>
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
                                <td>
                                    <span class="<?= $statusClass ?>"><?= ucfirst($status) ?></span>
                                </td>
                                <td>
                                    <?= formatDate($row['updated_at']) ?>
                                    <?php if (!empty($row['overall_note'])): ?>
                                        <div class="text-muted small fst-italic"><?= h($row['overall_note']) ?></div>
                                    <?php endif; ?>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    <?php endif; ?>
</div>
</body>
</html>
