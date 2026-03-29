<?php

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

$allowedProfile = 'neeraj';
$profile = strtolower(trim((string) ($_GET['profile'] ?? ($_POST['profile'] ?? 'neeraj'))));

if ($profile !== $allowedProfile) {
    http_response_code(403);
    echo json_encode(['ok' => false, 'error' => 'Medical is available only for the Neeraj profile.']);
    exit;
}

$dataDir = __DIR__ . '/data';
$uploadDir = __DIR__ . '/uploads/medical/' . $allowedProfile;
$accountsFile = $dataDir . '/neeraj_medical_accounts.csv';
$beneficiariesFile = $dataDir . '/neeraj_medical_beneficiaries.csv';
$cancerGuardFile = $dataDir . '/neeraj_medical_cancer_guard.csv';

if (!is_dir($uploadDir)) {
    mkdir($uploadDir, 0775, true);
}

function medical_read_csv_rows(string $filePath): array
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

function medical_write_csv_rows(string $filePath, array $rows, array $header): bool
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

function medical_normalize_accounts(array $accounts): array
{
    $normalized = [];
    foreach ($accounts as $account) {
        $label = trim((string) ($account['label'] ?? ''));
        if ($label === '') {
            continue;
        }
        $normalized[] = [
            'group' => trim((string) ($account['group'] ?? '')),
            'label' => $label,
            'value' => trim((string) ($account['value'] ?? '')),
        ];
    }
    return $normalized;
}

function medical_normalize_beneficiaries(array $rows): array
{
    $normalized = [];
    foreach ($rows as $row) {
        $normalized[] = [
            's_no' => trim((string) ($row['s_no'] ?? '')),
            'beneficiary_name' => trim((string) ($row['beneficiary_name'] ?? '')),
            'member_id' => trim((string) ($row['member_id'] ?? '')),
            'date_of_birth' => trim((string) ($row['date_of_birth'] ?? '')),
            'relation' => trim((string) ($row['relation'] ?? '')),
            'effective_from' => trim((string) ($row['effective_from'] ?? '')),
        ];
    }
    return $normalized;
}

function medical_normalize_cancer_guard(array $rows): array
{
    $normalized = [];
    foreach ($rows as $row) {
        $normalized[] = [
            's_no' => trim((string) ($row['s_no'] ?? '')),
            'name' => trim((string) ($row['name'] ?? '')),
            'relationship' => trim((string) ($row['relationship'] ?? '')),
            'date_of_birth' => trim((string) ($row['date_of_birth'] ?? '')),
            'sum_insured' => trim((string) ($row['sum_insured'] ?? '')),
            'premium' => trim((string) ($row['premium'] ?? '')),
            'payment_status' => trim((string) ($row['payment_status'] ?? '')),
        ];
    }
    return $normalized;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && (string) ($_POST['action'] ?? '') === 'upload') {
    $field = trim((string) ($_POST['field'] ?? ''));
    if ($field !== 'ecard') {
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
    $filename = 'ecard_' . date('Ymd_His') . '_' . bin2hex(random_bytes(4)) . '.' . $safeExtension;
    $targetPath = $uploadDir . '/' . $filename;

    if (!move_uploaded_file((string) $file['tmp_name'], $targetPath)) {
        http_response_code(500);
        echo json_encode(['ok' => false, 'error' => 'Unable to store uploaded file.']);
        exit;
    }

    echo json_encode([
        'ok' => true,
        'profile' => $allowedProfile,
        'file_path' => 'uploads/medical/' . $allowedProfile . '/' . $filename,
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

    $accounts = medical_normalize_accounts(is_array($payload['accounts'] ?? null) ? $payload['accounts'] : []);
    $beneficiaries = medical_normalize_beneficiaries(is_array($payload['beneficiaries'] ?? null) ? $payload['beneficiaries'] : []);
    $cancerGuard = medical_normalize_cancer_guard(is_array($payload['cancer_guard'] ?? null) ? $payload['cancer_guard'] : []);

    if (
        !medical_write_csv_rows($accountsFile, $accounts, ['group', 'label', 'value']) ||
        !medical_write_csv_rows($beneficiariesFile, $beneficiaries, ['s_no', 'beneficiary_name', 'member_id', 'date_of_birth', 'relation', 'effective_from']) ||
        !medical_write_csv_rows($cancerGuardFile, $cancerGuard, ['s_no', 'name', 'relationship', 'date_of_birth', 'sum_insured', 'premium', 'payment_status'])
    ) {
        http_response_code(500);
        echo json_encode(['ok' => false, 'error' => 'Failed to write Medical CSV files.']);
        exit;
    }
}

echo json_encode([
    'ok' => true,
    'profile' => $allowedProfile,
    'accounts' => medical_read_csv_rows($accountsFile),
    'beneficiaries' => medical_normalize_beneficiaries(medical_read_csv_rows($beneficiariesFile)),
    'cancer_guard' => medical_normalize_cancer_guard(medical_read_csv_rows($cancerGuardFile)),
], JSON_UNESCAPED_SLASHES);
