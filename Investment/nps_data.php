<?php

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

$allowedProfiles = ['ankita', 'akanksha', 'neeraj', 'vikas', 'mom'];
$profile = strtolower(trim((string) ($_GET['profile'] ?? '')));

if ($profile === '' || !in_array($profile, $allowedProfiles, true)) {
    http_response_code(403);
    echo json_encode(['ok' => false, 'error' => 'NPS is not available for this profile.']);
    exit;
}

$dataDir = __DIR__ . '/data';
$recordsFile = $dataDir . '/' . $profile . '_nps_records.csv';

function nps_read_csv_rows(string $filePath): array
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

function nps_write_csv_rows(string $filePath, array $rows, array $header): bool
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

function nps_normalize_records(array $records): array
{
    $normalized = [];
    foreach ($records as $record) {
        $name = trim((string) ($record['name'] ?? ''));
        $amount = trim((string) ($record['amount'] ?? ''));
        $note = trim((string) ($record['note'] ?? ''));

        if ($name === '' && $amount === '' && $note === '') {
            continue;
        }

        $normalized[] = [
            'name' => $name,
            'amount' => $amount,
            'note' => $note,
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

    $records = nps_normalize_records(is_array($payload['records'] ?? null) ? $payload['records'] : []);

    if (!nps_write_csv_rows($recordsFile, $records, ['name', 'amount', 'note'])) {
        http_response_code(500);
        echo json_encode(['ok' => false, 'error' => 'Failed to write NPS CSV file.']);
        exit;
    }
}

$recordsRows = nps_normalize_records(nps_read_csv_rows($recordsFile));

echo json_encode([
    'ok' => true,
    'profile' => $profile,
    'records' => $recordsRows,
], JSON_UNESCAPED_SLASHES);
