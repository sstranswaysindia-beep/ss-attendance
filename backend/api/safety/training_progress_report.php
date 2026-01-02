<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

if (!isset($conn) || !$conn instanceof mysqli) {
    http_response_code(500);
    echo 'Database connection not available';
    exit;
}

if (!safety_table_exists($conn, 'safety_training_modules') || !safety_table_exists($conn, 'safety_training_progress')) {
    http_response_code(500);
    echo 'Training tables not installed';
    exit;
}

function h(?string $v): string {
    return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8');
}

$rows = [];
try {
    $sql = "
        SELECT
            m.id,
            m.code,
            m.title,
            m.sort_order,
            COUNT(DISTINCT p.identity_key) AS started_count,
            COUNT(DISTINCT CASE WHEN p.completed = 1 THEN p.identity_key END) AS completed_count
        FROM safety_training_modules m
        LEFT JOIN safety_training_progress p ON p.module_id = m.id
        GROUP BY m.id, m.code, m.title, m.sort_order
        ORDER BY m.sort_order ASC, m.id ASC
    ";
    $res = $conn->query($sql);
    if ($res) {
        while ($row = $res->fetch_assoc()) {
            $rows[] = $row;
        }
        $res->close();
    }
} catch (Throwable $e) {
    http_response_code(500);
    echo 'Failed to fetch progress: ' . h($e->getMessage());
    exit;
}

$totalStarted = array_sum(array_map(static fn($r) => (int)$r['started_count'], $rows));
$totalCompleted = array_sum(array_map(static fn($r) => (int)$r['completed_count'], $rows));
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Safety Training Progress</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="bg-light">
<div class="container py-4">
    <div class="d-flex align-items-center justify-content-between mb-3">
        <div>
            <h1 class="h4 mb-0">Safety Training Progress</h1>
            <small class="text-muted">Distinct users/drivers per module</small>
        </div>
        <a class="btn btn-sm btn-outline-primary" href="./training_modules_admin.php">Modules Admin</a>
    </div>

    <div class="alert alert-info py-2">
        <div class="d-flex justify-content-between">
            <span>Total started (distinct identity keys across modules): <strong><?= $totalStarted ?></strong></span>
            <span>Total completed (distinct completions across modules): <strong><?= $totalCompleted ?></strong></span>
        </div>
    </div>

    <div class="table-responsive shadow-sm bg-white rounded">
        <table class="table table-hover align-middle mb-0">
            <thead class="table-light">
            <tr>
                <th>#</th>
                <th>Code</th>
                <th>Title</th>
                <th>Sort</th>
                <th>Started (distinct)</th>
                <th>Completed (distinct)</th>
                <th>Completion %</th>
            </tr>
            </thead>
            <tbody>
            <?php foreach ($rows as $idx => $r): ?>
                <?php
                $started = (int)$r['started_count'];
                $completed = (int)$r['completed_count'];
                $pct = $started > 0 ? round(($completed / $started) * 100) : 0;
                ?>
                <tr>
                    <td><?= $idx + 1 ?></td>
                    <td class="fw-semibold"><?= h($r['code']) ?></td>
                    <td><?= h($r['title']) ?></td>
                    <td><?= (int)$r['sort_order'] ?></td>
                    <td><?= $started ?></td>
                    <td><?= $completed ?></td>
                    <td>
                        <span class="badge <?= $pct >= 80 ? 'bg-success' : ($pct >= 40 ? 'bg-warning text-dark' : 'bg-secondary') ?>">
                            <?= $pct ?>%
                        </span>
                    </td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table>
    </div>
</div>
</body>
</html>
