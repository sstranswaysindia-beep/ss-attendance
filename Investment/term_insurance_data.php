<?php

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

$allowedProfile = 'neeraj';
$profile = strtolower(trim((string) ($_GET['profile'] ?? ($_POST['profile'] ?? 'neeraj'))));

if ($profile !== $allowedProfile) {
    http_response_code(403);
    echo json_encode(['ok' => false, 'error' => 'Term Insurance is available only for the Vikas profile.']);
    exit;
}

$dataDir = __DIR__ . '/data';
$uploadDir = __DIR__ . '/uploads/term_insurance/' . $allowedProfile;
$accountsFile = $dataDir . '/neeraj_term_insurance_accounts.csv';
$recordsFile = $dataDir . '/neeraj_term_insurance_records.csv';

if (!is_dir($uploadDir)) {
    mkdir($uploadDir, 0775, true);
}

function term_read_csv_rows(string $filePath): array
{
    if (!is_file($filePath)) {
        return [];
    }
    $handle = fopen($filePath, 'rb');
    if ($handle === false) {
        return [];
    }
    $header = fgetcsv($handle, 0, ',', '"', '\\');
    if ($header === false) {
        fclose($handle);
        return [];
    }
    $rows = [];
    while (($row = fgetcsv($handle, 0, ',', '"', '\\')) !== false) {
        $entry = [];
        foreach ($header as $index => $column) {
            $entry[$column] = $row[$index] ?? '';
        }
        $rows[] = $entry;
    }
    fclose($handle);
    return $rows;
}

function term_write_csv_rows(string $filePath, array $rows, array $header): bool
{
    $handle = fopen($filePath, 'wb');
    if ($handle === false) {
        return false;
    }
    fputcsv($handle, $header, ',', '"', '\\');
    foreach ($rows as $row) {
        $line = [];
        foreach ($header as $column) {
            $line[] = (string) ($row[$column] ?? '');
        }
        fputcsv($handle, $line, ',', '"', '\\');
    }
    fclose($handle);
    return true;
}

function term_normalize_accounts(array $accounts): array
{
    $normalized = [];
    foreach ($accounts as $account) {
        $label = trim((string) ($account['label'] ?? ''));
        if ($label === '') {
            continue;
        }
        $normalized[] = [
            'label' => $label,
            'value' => trim((string) ($account['value'] ?? '')),
        ];
    }
    return $normalized;
}

function term_normalize_records(array $records): array
{
    $normalized = [];
    foreach ($records as $record) {
        $normalized[] = [
            's_no' => trim((string) ($record['s_no'] ?? '')),
            'year' => trim((string) ($record['year'] ?? '')),
            'premium' => trim((string) ($record['premium'] ?? '')),
            'receipt' => trim((string) ($record['receipt'] ?? '')),
            'pin' => trim((string) ($record['pin'] ?? '')),
        ];
    }
    return $normalized;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && (string) ($_POST['action'] ?? '') === 'upload') {
    $field = trim((string) ($_POST['field'] ?? ''));
    if ($field !== 'receipt') {
        http_response_code(400);
        echo json_encode(['ok' => false, 'error' => 'Invalid upload field.']);
        exit;
    }
    if (!isset($_FILES['file']) || !is_array($_FILES['file'])) {
        http_response_code(400);
        echo json_encode(['ok' => false, 'error' => 'No file uploaded.']);
        exit;
    }
    $file = $_FILES['file'];
    if (($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
        http_response_code(400);
        echo json_encode(['ok' => false, 'error' => 'Upload failed.']);
        exit;
    }
    $originalName = (string) ($file['name'] ?? 'document');
    $extension = strtolower(pathinfo($originalName, PATHINFO_EXTENSION));
    $safeExtension = preg_replace('/[^a-z0-9]/', '', $extension) ?: 'bin';
    $filename = 'receipt_' . date('Ymd_His') . '_' . bin2hex(random_bytes(4)) . '.' . $safeExtension;
    $targetPath = $uploadDir . '/' . $filename;
    if (!move_uploaded_file((string) $file['tmp_name'], $targetPath)) {
        http_response_code(500);
        echo json_encode(['ok' => false, 'error' => 'Unable to store uploaded file.']);
        exit;
    }
    echo json_encode([
        'ok' => true,
        'profile' => $allowedProfile,
        'file_path' => 'uploads/term_insurance/' . $allowedProfile . '/' . $filename,
    ], JSON_UNESCAPED_SLASHES);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $rawBody = file_get_contents('php://input') ?: '';
    $payload = json_decode($rawBody, true);
    if (!is_array($payload)) {
      http_response_code(400);
      echo json_encode(['ok' => false, 'error' => 'Invalid JSON payload.']);
      exit;
    }
    $accounts = term_normalize_accounts(is_array($payload['accounts'] ?? null) ? $payload['accounts'] : []);
    $records = term_normalize_records(is_array($payload['records'] ?? null) ? $payload['records'] : []);
    if (!term_write_csv_rows($accountsFile, $accounts, ['label', 'value']) ||
        !term_write_csv_rows($recordsFile, $records, ['s_no', 'year', 'premium', 'receipt', 'pin'])) {
        http_response_code(500);
        echo json_encode(['ok' => false, 'error' => 'Failed to write Term Insurance CSV files.']);
        exit;
    }
}

$accountsRows = term_read_csv_rows($accountsFile);
$recordsRows = term_normalize_records(term_read_csv_rows($recordsFile));
$totalPremium = 0.0;
foreach ($recordsRows as $record) {
    $totalPremium += (float) str_replace(',', '', (string) ($record['premium'] ?? '0'));
}

echo json_encode([
    'ok' => true,
    'profile' => $allowedProfile,
    'accounts' => $accountsRows,
    'records' => $recordsRows,
    'total_premium' => number_format($totalPremium, 0, '.', ''),
], JSON_UNESCAPED_SLASHES);
