<?php
declare(strict_types=1);

ini_set('display_errors', '1');
ini_set('display_startup_errors', '1');
error_reporting(E_ALL);
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

require __DIR__ . '/../includes/auth.php';
checkRole(['admin', 'supervisor']);

require __DIR__ . '/../../conf/config.php';
if (!isset($conn) || !($conn instanceof mysqli)) {
    die('Database connection ($conn) not available');
}

$ACTIVE_MENU = 'send_advance';

$uploadSummary = [
    'processed' => 0,
    'inserted' => 0,
    'skipped' => 0,
    'errors' => [],
    'rows' => [],
];

$maxSortOrder = (int) ($conn->query('SELECT COALESCE(MAX(sort_order), 0) FROM transaction_descriptions')->fetch_column() ?? 0);

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    try {
        if (empty($_FILES['advance_file']) || $_FILES['advance_file']['error'] !== UPLOAD_ERR_OK) {
            throw new RuntimeException('Please select a valid Excel/CSV file to upload.');
        }

        $tmpPath = $_FILES['advance_file']['tmp_name'];
        $originalName = (string) ($_FILES['advance_file']['name'] ?? '');
        $extension = strtolower(pathinfo($originalName, PATHINFO_EXTENSION));

        if (!in_array($extension, ['xlsx', 'xlsm', 'csv'], true)) {
            throw new RuntimeException('Unsupported file type. Please upload an .xlsx, .xlsm, or .csv file.');
        }

        $records = parseSpreadsheet($tmpPath, $extension);
        if (count($records) === 0) {
            throw new RuntimeException('No rows found in the uploaded file.');
        }

        $driverByIdStmt = $conn->prepare('SELECT id, empid, name FROM drivers WHERE id = ? LIMIT 1');
        $driverByEmpStmt = $conn->prepare('SELECT id, empid, name FROM drivers WHERE empid = ? LIMIT 1');
        $insertStmt = $conn->prepare(
            'INSERT INTO advance_transactions (driver_id, type, amount, description, created_at)
             VALUES (?, \'advance_received\', ?, ?, NOW())'
        );
        $ensureDescriptionStmt = $conn->prepare(
            'INSERT IGNORE INTO transaction_descriptions (label, sort_order) VALUES (?, ?)'
        );

        foreach ($records as $index => $row) {
            $rowNumber = $index + 2; // account for header row
            $uploadSummary['processed']++;

            $driverIdRaw = trim((string) ($row['driverid'] ?? $row['id'] ?? ''));
            $empIdRaw = trim((string) ($row['empid'] ?? $row['employeeid'] ?? $row['employee_id'] ?? ''));
            $descriptionRaw = trim((string) ($row['description'] ?? $row['desc'] ?? ''));
            $amountRaw = trim((string) ($row['amount'] ?? ''));

            if ($driverIdRaw === '' && $empIdRaw === '') {
                $uploadSummary['errors'][] = "Row {$rowNumber}: missing driver ID / employee ID.";
                $uploadSummary['skipped']++;
                continue;
            }

            if ($descriptionRaw === '') {
                $uploadSummary['errors'][] = "Row {$rowNumber}: description is required.";
                $uploadSummary['skipped']++;
                continue;
            }

            if ($amountRaw === '') {
                $uploadSummary['errors'][] = "Row {$rowNumber}: amount is required.";
                $uploadSummary['skipped']++;
                continue;
            }

            $amountSanitized = str_replace([',', '₹', ' '], '', $amountRaw);
            if (!is_numeric($amountSanitized)) {
                $uploadSummary['errors'][] = "Row {$rowNumber}: amount '{$amountRaw}' is not numeric.";
                $uploadSummary['skipped']++;
                continue;
            }
            $amount = (float) $amountSanitized;
            if ($amount <= 0) {
                $uploadSummary['errors'][] = "Row {$rowNumber}: amount must be greater than zero.";
                $uploadSummary['skipped']++;
                continue;
            }

            $driverRecord = null;
            if ($driverIdRaw !== '' && ctype_digit($driverIdRaw)) {
                $driverId = (int) $driverIdRaw;
                $driverByIdStmt->bind_param('i', $driverId);
                $driverByIdStmt->execute();
                $driverRecord = $driverByIdStmt->get_result()->fetch_assoc();
            }

            if (!$driverRecord && $empIdRaw !== '') {
                $driverByEmpStmt->bind_param('s', $empIdRaw);
                $driverByEmpStmt->execute();
                $driverRecord = $driverByEmpStmt->get_result()->fetch_assoc();
            }

            if (!$driverRecord) {
                $uploadSummary['errors'][] = "Row {$rowNumber}: driver not found (ID: '{$driverIdRaw}', Emp ID: '{$empIdRaw}').";
                $uploadSummary['skipped']++;
                continue;
            }

            $description = strtoupper($descriptionRaw);
            $descriptionParam = $description;
            $sortOrderParam = $maxSortOrder + 1;
            $ensureDescriptionStmt->bind_param('si', $descriptionParam, $sortOrderParam);
            $ensureDescriptionStmt->execute();
            if ($ensureDescriptionStmt->affected_rows > 0) {
                $maxSortOrder = $sortOrderParam;
            }

            $insertStmt->bind_param('ids', $driverRecord['id'], $amount, $description);
            $insertStmt->execute();

            $uploadSummary['inserted']++;
            $uploadSummary['rows'][] = [
                'row' => $rowNumber,
                'driver_id' => $driverRecord['id'],
                'empid' => $driverRecord['empid'] ?? '',
                'name' => $driverRecord['name'] ?? '',
                'description' => $description,
                'amount' => $amount,
            ];
        }

        $driverByIdStmt->close();
        $driverByEmpStmt->close();
        $insertStmt->close();
        $ensureDescriptionStmt->close();
    } catch (Throwable $error) {
        $uploadSummary['errors'][] = $error->getMessage();
    }
}

function parseSpreadsheet(string $path, string $extension): array
{
    if ($extension === 'csv') {
        return parseCsvFile($path);
    }

    if (in_array($extension, ['xlsx', 'xlsm'], true)) {
        return parseXlsxFile($path);
    }

    throw new RuntimeException('Unsupported file extension.');
}

function parseCsvFile(string $path): array
{
    $handle = fopen($path, 'r');
    if ($handle === false) {
        throw new RuntimeException('Unable to open CSV file.');
    }

    $rows = [];
    while (($data = fgetcsv($handle)) !== false) {
        $rows[] = array_map(static fn ($value) => is_string($value) ? trim($value) : $value, $data);
    }
    fclose($handle);

    return normalizeRows($rows);
}

function parseXlsxFile(string $path): array
{
    if (!class_exists('ZipArchive')) {
        throw new RuntimeException('ZipArchive extension is required to parse XLSX files.');
    }

    $zip = new ZipArchive();
    if ($zip->open($path) !== true) {
        throw new RuntimeException('Unable to open XLSX file.');
    }

    $sheetXml = $zip->getFromName('xl/worksheets/sheet1.xml');
    if ($sheetXml === false) {
        $zip->close();
        throw new RuntimeException('Worksheet sheet1.xml not found in XLSX.');
    }

    $sharedStrings = [];
    $sharedXml = $zip->getFromName('xl/sharedStrings.xml');
    if ($sharedXml !== false) {
        $sharedDoc = new SimpleXMLElement($sharedXml);
        foreach ($sharedDoc->si as $item) {
            if (isset($item->t)) {
                $sharedStrings[] = (string) $item->t;
                continue;
            }
            $buffer = '';
            foreach ($item->r as $run) {
                $buffer .= (string) $run->t;
            }
            $sharedStrings[] = $buffer;
        }
    }

    $zip->close();

    libxml_use_internal_errors(true);
    $sheetDoc = new SimpleXMLElement($sheetXml);
    libxml_clear_errors();

    $rows = [];
    if (isset($sheetDoc->sheetData->row)) {
        foreach ($sheetDoc->sheetData->row as $row) {
            $cells = [];
            $maxIndex = 0;

            foreach ($row->c as $cell) {
                $ref = (string) $cell['r'];
                $colLetters = preg_replace('/\d+/', '', $ref);
                $colIndex = columnLettersToIndex($colLetters);
                $value = readCellValue($cell, $sharedStrings);
                $cells[$colIndex] = $value;
                $maxIndex = max($maxIndex, $colIndex);
            }

            if (!empty($cells)) {
                $rowValues = array_fill(0, $maxIndex + 1, '');
                foreach ($cells as $idx => $value) {
                    $rowValues[$idx] = trim((string) $value);
                }
                $rows[] = $rowValues;
            }
        }
    }

    return normalizeRows($rows);
}

function columnLettersToIndex(string $letters): int
{
    $letters = strtoupper($letters);
    $index = 0;
    $length = strlen($letters);
    for ($i = 0; $i < $length; $i++) {
        $index = $index * 26 + (ord($letters[$i]) - ord('@'));
    }
    return $index - 1;
}

function readCellValue(SimpleXMLElement $cell, array $sharedStrings): string
{
    $type = (string) $cell['t'];
    if ($type === 's') {
        $sharedIndex = (int) ($cell->v ?? 0);
        return $sharedStrings[$sharedIndex] ?? '';
    }

    if ($type === 'b') {
        return ((string) ($cell->v ?? '0')) === '1' ? 'TRUE' : 'FALSE';
    }

    if (isset($cell->v)) {
        return (string) $cell->v;
    }

    if (isset($cell->is->t)) {
        return (string) $cell->is->t;
    }

    return '';
}

function normalizeRows(array $rows): array
{
    if (empty($rows)) {
        return [];
    }

    $header = array_shift($rows);
    $normalizedHeader = array_map('normalizeHeaderKey', $header);

    $records = [];
    foreach ($rows as $row) {
        if (!is_array($row)) {
            continue;
        }
        $record = [];
        foreach ($normalizedHeader as $index => $key) {
            if ($key === '') {
                continue;
            }
            $record[$key] = array_key_exists($index, $row) ? trim((string) $row[$index]) : '';
        }
        $records[] = $record;
    }

    return $records;
}

function normalizeHeaderKey(?string $value): string
{
    if ($value === null) {
        return '';
    }
    $key = strtolower(trim($value));
    $key = preg_replace('/[^a-z0-9]+/', '', $key);
    return $key;
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
  <title>Bulk Send Advance · Dashboard</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
  <style>
    body { background:#f5f6f8; }
    .page-gutter { padding:20px 12px; }
    .card-upload { border-radius:16px; border:none; box-shadow:0 10px 25px rgba(15,23,42,.08); }
    .card-upload .card-header { background:linear-gradient(135deg,#0d6efd,#6610f2); color:#fff; border-radius:16px 16px 0 0; }
    .status-list { max-height:280px; overflow:auto; }
    .status-list .item { border-radius:12px; background:#f8f9fa; padding:12px; margin-bottom:8px; border-left:4px solid #198754; }
    .status-list .item.error { border-color:#dc3545; }
    .table thead th { background:#f1f3f5; }
  </style>
</head>
<body>
  <?php include 'includes/navbar.php'; ?>
  <div class="page-gutter">
    <div class="container-fluid">
      <div class="row gx-3">
        <?php include 'includes/sidebar.php'; ?>

        <main class="main-like main col-md-9 ms-sm-auto col-lg-10 px-2">
          <div class="d-flex justify-content-between align-items-center pt-2 pb-2 mb-3 border-bottom">
            <div class="d-flex align-items-center gap-2">
              <i class="fas fa-file-import"></i>
              <h1 class="h4 mb-0">Bulk Send Advance</h1>
            </div>
            <div>
              <a href="index.php" class="btn btn-outline-secondary btn-sm">
                <i class="fas fa-arrow-left me-1"></i> Back to Dashboard
              </a>
            </div>
          </div>

          <div class="card card-upload mb-4">
            <div class="card-header">
              <div class="d-flex align-items-center gap-2">
                <i class="fas fa-upload"></i>
                <span>Upload Excel / CSV</span>
              </div>
            </div>
            <div class="card-body">
              <p class="mb-3 text-muted">
                Upload an Excel (<code>.xlsx</code>) or CSV file with the following columns:
                <strong>ID</strong>, <strong>EMP_ID</strong>, <strong>NAME</strong>,
                <strong>PLANT</strong>, <strong>DESCRIPTION</strong>, <strong>AMOUNT</strong>.
                Each row will create a <em>YOU GOT</em> entry in Khata Book.
              </p>

              <form method="post" enctype="multipart/form-data" class="row g-3">
                <div class="col-12 col-lg-8">
                  <div class="form-floating">
                    <input type="file" class="form-control" id="advance_file" name="advance_file" accept=".xlsx,.xlsm,.csv" required>
                    <label for="advance_file">Choose Excel or CSV file</label>
                  </div>
                </div>
                <div class="col-12 col-lg-4 d-flex align-items-end">
                  <button type="submit" class="btn btn-primary w-100">
                    <i class="fas fa-paper-plane me-1"></i> Upload & Create Entries
                  </button>
                </div>
              </form>
              <div class="mt-2">
                <a href="assets/sample_send_advance.csv" class="link-primary" download>
                  <i class="fas fa-download me-1"></i>Download sample template
                </a>
              </div>

              <?php if ($_SERVER['REQUEST_METHOD'] === 'POST'): ?>
                <hr class="my-4">

                <div class="row">
                  <div class="col-12 col-lg-4">
                    <h5 class="h6 text-muted mb-3">Summary</h5>
                    <ul class="list-group mb-3">
                      <li class="list-group-item d-flex justify-content-between align-items-center">
                        Rows Processed
                        <span class="badge bg-secondary rounded-pill"><?= (int) $uploadSummary['processed'] ?></span>
                      </li>
                      <li class="list-group-item d-flex justify-content-between align-items-center">
                        Entries Created
                        <span class="badge bg-success rounded-pill"><?= (int) $uploadSummary['inserted'] ?></span>
                      </li>
                      <li class="list-group-item d-flex justify-content-between align-items-center">
                        Skipped / Errors
                        <span class="badge bg-danger rounded-pill"><?= (int) $uploadSummary['skipped'] ?></span>
                      </li>
                    </ul>

                    <?php if (!empty($uploadSummary['errors'])): ?>
                      <div class="status-list">
                        <?php foreach ($uploadSummary['errors'] as $message): ?>
                          <div class="item error">
                            <i class="fas fa-triangle-exclamation text-danger me-2"></i><?= htmlspecialchars($message, ENT_QUOTES, 'UTF-8') ?>
                          </div>
                        <?php endforeach; ?>
                      </div>
                    <?php endif; ?>
                  </div>

                  <div class="col-12 col-lg-8">
                    <h5 class="h6 text-muted mb-3">Entries Created</h5>
                    <?php if (!empty($uploadSummary['rows'])): ?>
                      <div class="table-responsive">
                        <table class="table table-sm table-striped">
                          <thead>
                            <tr>
                              <th>#</th>
                              <th>Driver ID</th>
                              <th>Emp ID</th>
                              <th>Name</th>
                              <th>Description</th>
                              <th class="text-end">Amount</th>
                            </tr>
                          </thead>
                          <tbody>
                            <?php foreach ($uploadSummary['rows'] as $row): ?>
                              <tr>
                                <td><?= (int) $row['row'] ?></td>
                                <td><?= htmlspecialchars((string) $row['driver_id'], ENT_QUOTES, 'UTF-8') ?></td>
                                <td><?= htmlspecialchars((string) $row['empid'], ENT_QUOTES, 'UTF-8') ?></td>
                                <td><?= htmlspecialchars((string) $row['name'], ENT_QUOTES, 'UTF-8') ?></td>
                                <td><?= htmlspecialchars((string) $row['description'], ENT_QUOTES, 'UTF-8') ?></td>
                                <td class="text-end">₹<?= number_format((float) $row['amount'], 2) ?></td>
                              </tr>
                            <?php endforeach; ?>
                          </tbody>
                        </table>
                      </div>
                    <?php else: ?>
                      <div class="alert alert-info">
                        No entries were created.
                      </div>
                    <?php endif; ?>
                  </div>
                </div>
              <?php endif; ?>
            </div>
          </div>
        </main>
      </div>
    </div>
  </div>

  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
