<?php

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

$allowedProfile = 'neeraj';
$profile = strtolower(trim((string) ($_GET['profile'] ?? 'neeraj')));

if ($profile !== $allowedProfile) {
    http_response_code(403);
    echo json_encode(['ok' => false, 'error' => 'ESOP is available only for the Neeraj profile.']);
    exit;
}

$dataDir = __DIR__ . '/data';
$accountsFile = $dataDir . '/neeraj_esop_accounts.csv';
$recordsFile = $dataDir . '/neeraj_esop_records.csv';

function read_csv_rows(string $filePath): array
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

function write_csv_rows(string $filePath, array $rows, array $header): bool
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

function normalize_accounts(array $accounts): array
{
    $normalized = [];
    foreach ($accounts as $account) {
        $group = trim((string) ($account['group'] ?? ''));
        $label = trim((string) ($account['label'] ?? ''));
        $value = trim((string) ($account['value'] ?? ''));
        if ($group === '' || $label === '') {
            continue;
        }
        $normalized[] = [
            'group' => $group,
            'label' => $label,
            'value' => $value,
        ];
    }
    return $normalized;
}

function normalize_records(array $records): array
{
    $normalized = [];
    foreach ($records as $record) {
        $normalized[] = [
            's_no' => trim((string) ($record['s_no'] ?? '')),
            'year' => trim((string) ($record['year'] ?? '')),
            'investment' => trim((string) ($record['investment'] ?? '')),
            'remarks' => trim((string) ($record['remarks'] ?? '')),
            'euro_alloted' => trim((string) ($record['euro_alloted'] ?? '')),
            'maturity_date' => trim((string) ($record['maturity_date'] ?? '')),
            'expected_return' => trim((string) ($record['expected_return'] ?? '')),
            'amount_received' => trim((string) ($record['amount_received'] ?? '')),
        ];
    }
    return $normalized;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $rawBody = file_get_contents('php://input') ?: '';
    $payload = json_decode($rawBody, true);

    if (!is_array($payload)) {
        http_response_code(400);
        echo json_encode(['ok' => false, 'error' => 'Invalid JSON payload.']);
        exit;
    }

    $accounts = normalize_accounts(is_array($payload['accounts'] ?? null) ? $payload['accounts'] : []);
    $records = normalize_records(is_array($payload['records'] ?? null) ? $payload['records'] : []);

    if (!write_csv_rows($accountsFile, $accounts, ['group', 'label', 'value']) ||
        !write_csv_rows($recordsFile, $records, ['s_no', 'year', 'investment', 'remarks', 'euro_alloted', 'maturity_date', 'expected_return', 'amount_received'])) {
        http_response_code(500);
        echo json_encode(['ok' => false, 'error' => 'Failed to write ESOP CSV files.']);
        exit;
    }
}

$accountsRows = read_csv_rows($accountsFile);
$recordsRows = read_csv_rows($recordsFile);
$totalEuro = 0.0;

foreach ($recordsRows as $record) {
    $value = (float) str_replace(',', '', (string) ($record['euro_alloted'] ?? '0'));
    $totalEuro += $value;
}

echo json_encode([
    'ok' => true,
    'profile' => $allowedProfile,
    'accounts' => $accountsRows,
    'records' => $recordsRows,
    'total_euro_alloted' => number_format($totalEuro, 2, '.', ''),
], JSON_UNESCAPED_SLASHES);
