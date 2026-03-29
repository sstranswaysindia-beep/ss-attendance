<?php

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

$allowedProfile = 'neeraj';
$profile = strtolower(trim((string) ($_GET['profile'] ?? 'neeraj')));

if ($profile !== $allowedProfile) {
    http_response_code(403);
    echo json_encode(['ok' => false, 'error' => 'Sukanya is available only for the Neeraj profile.']);
    exit;
}

$dataDir = __DIR__ . '/data';
$accountsFile = $dataDir . '/neeraj_sukanya_accounts.csv';
$recordsFile = $dataDir . '/neeraj_sukanya_records.csv';

function sukanya_read_csv_rows(string $filePath): array
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

function sukanya_write_csv_rows(string $filePath, array $rows, array $header): bool
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

function sukanya_normalize_accounts(array $accounts): array
{
    $normalized = [];
    foreach ($accounts as $account) {
        $label = trim((string) ($account['label'] ?? ''));
        $value = trim((string) ($account['value'] ?? ''));
        if ($label === '') {
            continue;
        }
        $normalized[] = [
            'label' => $label,
            'value' => $value,
        ];
    }
    return $normalized;
}

function sukanya_normalize_records(array $records): array
{
    $normalized = [];
    foreach ($records as $record) {
        $entry = [
            's_no' => trim((string) ($record['s_no'] ?? '')),
            'value_date' => trim((string) ($record['value_date'] ?? '')),
            'transaction_date' => trim((string) ($record['transaction_date'] ?? '')),
            'cheque_number' => trim((string) ($record['cheque_number'] ?? '')),
            'transaction_remarks' => trim((string) ($record['transaction_remarks'] ?? '')),
            'withdrawal_amount_inr' => trim((string) ($record['withdrawal_amount_inr'] ?? '')),
            'deposit_amount_inr' => trim((string) ($record['deposit_amount_inr'] ?? '')),
            'interest_deposited_inr' => trim((string) ($record['interest_deposited_inr'] ?? '')),
            'balance_inr' => trim((string) ($record['balance_inr'] ?? '')),
        ];

        $isLegacyInterestRow =
            $entry['interest_deposited_inr'] === '' &&
            $entry['withdrawal_amount_inr'] === '' &&
            $entry['deposit_amount_inr'] !== '' &&
            stripos($entry['transaction_remarks'], 'interest') !== false;

        if ($isLegacyInterestRow) {
            $entry['interest_deposited_inr'] = $entry['deposit_amount_inr'];
            $entry['deposit_amount_inr'] = '';
        }

        $normalized[] = $entry;
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

    $accounts = sukanya_normalize_accounts(is_array($payload['accounts'] ?? null) ? $payload['accounts'] : []);
    $records = sukanya_normalize_records(is_array($payload['records'] ?? null) ? $payload['records'] : []);

    if (!sukanya_write_csv_rows($accountsFile, $accounts, ['label', 'value']) ||
        !sukanya_write_csv_rows($recordsFile, $records, ['s_no', 'value_date', 'transaction_date', 'cheque_number', 'transaction_remarks', 'withdrawal_amount_inr', 'deposit_amount_inr', 'interest_deposited_inr', 'balance_inr'])) {
        http_response_code(500);
        echo json_encode(['ok' => false, 'error' => 'Failed to write Sukanya CSV files.']);
        exit;
    }
}

$accountsRows = sukanya_read_csv_rows($accountsFile);
$recordsRows = sukanya_normalize_records(sukanya_read_csv_rows($recordsFile));

$sumDeposits = 0.0;
$sumInterest = 0.0;
$sumWithdrawals = 0.0;
$latestBalance = '';

foreach ($recordsRows as $record) {
    $sumDeposits += (float) str_replace(',', '', (string) ($record['deposit_amount_inr'] ?? '0'));
    $sumInterest += (float) str_replace(',', '', (string) ($record['interest_deposited_inr'] ?? '0'));
    $sumWithdrawals += (float) str_replace(',', '', (string) ($record['withdrawal_amount_inr'] ?? '0'));
    if (trim((string) ($record['balance_inr'] ?? '')) !== '') {
        $latestBalance = (string) $record['balance_inr'];
    }
}

echo json_encode([
    'ok' => true,
    'profile' => $allowedProfile,
    'accounts' => $accountsRows,
    'records' => $recordsRows,
    'total_deposit_inr' => number_format($sumDeposits, 0, '.', ''),
    'total_interest_inr' => number_format($sumInterest, 0, '.', ''),
    'total_withdrawal_inr' => number_format($sumWithdrawals, 0, '.', ''),
    'latest_balance_inr' => $latestBalance,
], JSON_UNESCAPED_SLASHES);
