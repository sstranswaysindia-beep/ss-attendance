<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

if (!isset($conn) || !$conn instanceof mysqli) {
    http_response_code(500);
    echo 'Database connection not available';
    exit;
}

$modules = [];
try {
    $res = $conn->query("
        SELECT id, code, title, description, audio_url, sort_order, is_active,
               CHAR_LENGTH(transcript) AS transcript_length,
               transcript
        FROM safety_training_modules
        ORDER BY sort_order ASC, id ASC
    ");
    if ($res) {
        while ($row = $res->fetch_assoc()) {
            $modules[] = $row;
        }
        $res->close();
    }
} catch (Throwable $e) {
    http_response_code(500);
    echo 'Failed to fetch modules: ' . htmlspecialchars($e->getMessage(), ENT_QUOTES, 'UTF-8');
    exit;
}

function h(?string $value): string
{
    return htmlspecialchars((string)$value, ENT_QUOTES, 'UTF-8');
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Safety Training Modules Admin</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="bg-light">
<div class="container py-4">
    <div class="d-flex align-items-center justify-content-between mb-3">
        <div>
            <h1 class="h4 mb-0">Safety Training Modules</h1>
            <small class="text-muted">List view (edit by updating DB seed / API)</small>
        </div>
        <a class="btn btn-sm btn-outline-primary" href="./training_modules.php" target="_blank" rel="noreferrer">View JSON API</a>
    </div>

    <div class="table-responsive shadow-sm bg-white rounded">
        <table class="table table-hover align-middle mb-0">
            <thead class="table-light">
            <tr>
                <th scope="col">#</th>
                <th scope="col">Code</th>
                <th scope="col">Title</th>
                <th scope="col">Description</th>
                <th scope="col">Sort</th>
                <th scope="col">Active</th>
                <th scope="col">Audio URL</th>
                <th scope="col">Transcript (preview)</th>
            </tr>
            </thead>
            <tbody>
            <?php foreach ($modules as $index => $module): ?>
                <?php
                $preview = mb_substr((string)$module['transcript'], 0, 240);
                if (mb_strlen((string)$module['transcript']) > 240) {
                    $preview .= '…';
                }
                ?>
                <tr>
                    <td><?= $index + 1 ?></td>
                    <td class="fw-semibold"><?= h($module['code']) ?></td>
                    <td><?= h($module['title']) ?></td>
                    <td style="max-width: 220px;"><?= h($module['description']) ?></td>
                    <td><?= (int)$module['sort_order'] ?></td>
                    <td>
                        <?php if ((int)$module['is_active'] === 1): ?>
                            <span class="badge bg-success">Active</span>
                        <?php else: ?>
                            <span class="badge bg-secondary">Hidden</span>
                        <?php endif; ?>
                    </td>
                    <td style="max-width: 220px; word-break: break-all;"><?= h($module['audio_url']) ?></td>
                    <td style="max-width: 360px; white-space: pre-wrap;"><?= h($preview) ?></td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table>
    </div>

    <div class="alert alert-info mt-3">
        To edit content, update the seed in <code>backend/api/safety/create_training_tables.sql</code> and re-run it,
        or modify rows directly in <code>safety_training_modules</code>.
    </div>
</div>
</body>
</html>
