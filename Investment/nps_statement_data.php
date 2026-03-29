<?php

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

$allowedProfile = 'neeraj';
$profile = strtolower(trim((string) ($_GET['profile'] ?? ($_POST['profile'] ?? 'neeraj'))));

if ($profile !== $allowedProfile) {
    http_response_code(403);
    echo json_encode(['ok' => false, 'error' => 'NPS statement is available only for the Neeraj profile.']);
    exit;
}

$uploadDir = __DIR__ . '/uploads/nps_statement/' . $allowedProfile;
if (!is_dir($uploadDir)) {
    mkdir($uploadDir, 0775, true);
}

function nps_statement_read_rows(string $filePath): array
{
    if (!is_file($filePath)) {
        return [];
    }

    $handle = fopen($filePath, 'rb');
    if ($handle === false) {
        return [];
    }

    $rows = [];
    while (($row = fgetcsv($handle, 0, ',', '"', '\\')) !== false) {
        $rows[] = array_map(
            static fn ($value) => trim((string) $value),
            $row
        );
    }

    fclose($handle);
    return $rows;
}

function nps_statement_first_cell(array $row): string
{
    return trim((string) ($row[0] ?? ''));
}

function nps_statement_has_values(array $row): bool
{
    foreach ($row as $cell) {
        if (trim((string) $cell) !== '') {
            return true;
        }
    }
    return false;
}

function nps_statement_find_row_index(array $rows, callable $matcher, int $start = 0): ?int
{
    $total = count($rows);
    for ($index = max(0, $start); $index < $total; $index++) {
        if ($matcher($rows[$index], $index)) {
            return $index;
        }
    }
    return null;
}

function nps_statement_clean_currency(string $value): string
{
    $text = trim($value);
    if ($text === '') {
        return '';
    }

    $negative = preg_match('/^\(.*\)$/', $text) === 1;
    $cleaned = preg_replace('/[^0-9.]/', '', $text) ?? '';
    if ($cleaned === '') {
        return '';
    }

    return $negative ? '-' . $cleaned : $cleaned;
}

function nps_statement_extract_percent(array $rows): string
{
    foreach ($rows as $row) {
        foreach ($row as $cell) {
            $value = trim((string) $cell);
            if (preg_match('/^\d+(?:\.\d+)?%$/', $value) === 1) {
                return $value;
            }
        }
    }
    return '';
}

function nps_statement_scheme_code(string $scheme): string
{
    if (preg_match('/SCHEME\s+([A-Z])\s+-/i', $scheme, $matches) === 1) {
        return strtoupper($matches[1]);
    }
    return '';
}

function nps_statement_get_latest_file(string $uploadDir): ?string
{
    $files = glob($uploadDir . '/*.csv') ?: [];
    if ($files === []) {
        return null;
    }

    usort(
        $files,
        static fn (string $left, string $right) => filemtime($right) <=> filemtime($left)
    );

    return $files[0] ?? null;
}

function nps_statement_build_payload(string $filePath, string $profile): array
{
    $rows = nps_statement_read_rows($filePath);
    $subscriber = [
        'pran' => '',
        'subscriber_name' => '',
    ];
    $statement = [
        'generation_date' => '',
        'scheme_choice' => '',
    ];
    $investmentSummary = [
        'as_on' => '',
        'holdings' => '',
        'contributions_count' => '',
        'total_contribution' => '',
        'total_withdrawal' => '',
        'notional_gain_loss' => '',
        'intermediary_charges' => '',
        'xirr' => '',
    ];
    $schemeSummary = [];
    $contributionDetails = [];
    $transactionGroups = [];

    foreach ($rows as $row) {
        $firstCell = nps_statement_first_cell($row);
        if ($firstCell === 'PRAN') {
            $subscriber['pran'] = ltrim(trim((string) ($row[1] ?? '')), "'");
        } elseif ($firstCell === 'Subscriber Name') {
            $subscriber['subscriber_name'] = trim((string) ($row[1] ?? ''));
        } elseif (stripos($firstCell, 'Statement Generation Date') === 0) {
            $statement['generation_date'] = trim((string) preg_replace('/^Statement Generation Date\s*:/i', '', $firstCell));
        } elseif (stripos($firstCell, 'Scheme Choice -') === 0) {
            $statement['scheme_choice'] = trim((string) preg_replace('/^Scheme Choice\s*-\s*/i', '', $firstCell));
        }
    }

    $investmentSummaryIndex = nps_statement_find_row_index(
        $rows,
        static fn (array $row): bool => nps_statement_first_cell($row) === 'Investment Summary'
    );

    if ($investmentSummaryIndex !== null) {
        $headingIndex = nps_statement_find_row_index(
            $rows,
            static fn (array $row): bool => stripos(nps_statement_first_cell($row), 'Value of your Holdings') !== false,
            $investmentSummaryIndex + 1
        );

        if ($headingIndex !== null) {
            $headingRow = $rows[$headingIndex];
            $formulaRow = $rows[$headingIndex + 1] ?? [];
            $valuesRow = $rows[$headingIndex + 2] ?? [];
            if (preg_match('/as on\s+(.+?)\s+\(in Rs\)/i', (string) ($headingRow[0] ?? ''), $matches) === 1) {
                $investmentSummary['as_on'] = trim($matches[1]);
            }

            $investmentSummary['holdings'] = nps_statement_clean_currency((string) ($valuesRow[0] ?? ''));
            $investmentSummary['contributions_count'] = trim((string) ($valuesRow[1] ?? ''));
            $investmentSummary['total_contribution'] = nps_statement_clean_currency((string) ($valuesRow[2] ?? ''));
            $investmentSummary['total_withdrawal'] = nps_statement_clean_currency((string) ($valuesRow[3] ?? ''));
            $investmentSummary['notional_gain_loss'] = nps_statement_clean_currency((string) ($valuesRow[4] ?? ''));
            $investmentSummary['intermediary_charges'] = nps_statement_clean_currency((string) ($valuesRow[5] ?? ''));
            $investmentSummary['xirr'] = nps_statement_extract_percent([$headingRow, $formulaRow, $valuesRow]);
        }
    }

    $schemeSummaryIndex = nps_statement_find_row_index(
        $rows,
        static fn (array $row): bool => nps_statement_first_cell($row) === 'Investment Details - Scheme Wise Summary'
    );

    if ($schemeSummaryIndex !== null) {
        for ($index = $schemeSummaryIndex + 2, $total = count($rows); $index < $total; $index++) {
            $row = $rows[$index];
            $firstCell = nps_statement_first_cell($row);
            if ($firstCell === '' || stripos($firstCell, 'Contribution/Redemption Details') !== false) {
                break;
            }

            $schemeSummary[] = [
                'scheme' => $firstCell,
                'scheme_code' => nps_statement_scheme_code($firstCell),
                'value_holdings' => nps_statement_clean_currency((string) ($row[1] ?? '')),
                'total_units' => trim((string) ($row[2] ?? '')),
                'nav' => trim((string) ($row[3] ?? '')),
            ];
        }
    }

    $contributionIndex = nps_statement_find_row_index(
        $rows,
        static fn (array $row): bool => stripos(nps_statement_first_cell($row), 'Contribution/Redemption Details during the selected period') !== false
    );

    if ($contributionIndex !== null) {
        $headerIndex = nps_statement_find_row_index(
            $rows,
            static fn (array $row): bool => nps_statement_first_cell($row) === 'Date',
            $contributionIndex + 1
        );

        if ($headerIndex !== null) {
            for ($index = $headerIndex + 1, $total = count($rows); $index < $total; $index++) {
                $row = $rows[$index];
                $firstCell = nps_statement_first_cell($row);
                if ($firstCell === '') {
                    continue;
                }
                if ($firstCell === 'Transaction Details') {
                    break;
                }

                $contributionDetails[] = [
                    'date' => $firstCell,
                    'particulars' => trim((string) ($row[1] ?? '')),
                    'uploaded_by' => trim((string) ($row[2] ?? '')),
                    'employee_contribution' => nps_statement_clean_currency((string) ($row[3] ?? '')),
                    'employer_contribution' => nps_statement_clean_currency((string) ($row[4] ?? '')),
                    'total' => nps_statement_clean_currency((string) ($row[5] ?? '')),
                ];
            }
        }
    }

    $transactionIndex = nps_statement_find_row_index(
        $rows,
        static fn (array $row): bool => nps_statement_first_cell($row) === 'Transaction Details'
    );

    if ($transactionIndex !== null) {
        $index = $transactionIndex + 1;
        $total = count($rows);
        while ($index < $total) {
            $row = $rows[$index];
            $firstCell = nps_statement_first_cell($row);
            if ($firstCell === '') {
                $index++;
                continue;
            }

            if (stripos($firstCell, 'NPS TRUST-') === 0) {
                $schemeName = $firstCell;
                $schemeCode = nps_statement_scheme_code($schemeName);
                $headerRowIndex = nps_statement_find_row_index(
                    $rows,
                    static fn (array $candidate): bool => nps_statement_first_cell($candidate) === 'Date',
                    $index + 1
                );
                if ($headerRowIndex === null) {
                    break;
                }

                $groupRows = [];
                $scan = $headerRowIndex + 1;
                while ($scan < $total) {
                    $scanRow = $rows[$scan];
                    $scanFirstCell = nps_statement_first_cell($scanRow);
                    if ($scanFirstCell === '') {
                        $scan++;
                        continue;
                    }
                    if (stripos($scanFirstCell, 'NPS TRUST-') === 0) {
                        break;
                    }

                    $groupRows[] = [
                        'date' => $scanFirstCell,
                        'description' => trim((string) ($scanRow[1] ?? '')),
                        'amount' => trim((string) ($scanRow[2] ?? '')),
                        'nav' => trim((string) ($scanRow[3] ?? '')),
                        'units' => trim((string) ($scanRow[4] ?? '')),
                    ];
                    $scan++;
                }

                $transactionGroups[] = [
                    'scheme' => $schemeName,
                    'scheme_code' => $schemeCode,
                    'rows' => $groupRows,
                ];
                $index = $scan;
                continue;
            }

            $index++;
        }
    }

    return [
        'ok' => true,
        'profile' => $profile,
        'has_statement' => true,
        'source_file' => 'uploads/nps_statement/' . $profile . '/' . basename($filePath),
        'source_name' => basename($filePath),
        'uploaded_at' => date('Y-m-d H:i:s', (int) filemtime($filePath)),
        'subscriber' => $subscriber,
        'statement' => $statement,
        'investment_summary' => $investmentSummary,
        'scheme_summary' => $schemeSummary,
        'contribution_details' => $contributionDetails,
        'transaction_groups' => $transactionGroups,
    ];
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && (string) ($_POST['action'] ?? '') === 'upload') {
    if (!isset($_FILES['file']) || !is_array($_FILES['file'])) {
        http_response_code(400);
        echo json_encode(['ok' => false, 'error' => 'No NPS statement file uploaded.']);
        exit;
    }

    $file = $_FILES['file'];
    if (($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
        http_response_code(400);
        echo json_encode(['ok' => false, 'error' => 'NPS statement upload failed.']);
        exit;
    }

    $originalName = (string) ($file['name'] ?? 'nps_statement.csv');
    $extension = strtolower(pathinfo($originalName, PATHINFO_EXTENSION));
    if ($extension !== 'csv') {
        http_response_code(400);
        echo json_encode(['ok' => false, 'error' => 'Please upload a CSV statement file.']);
        exit;
    }

    $baseName = pathinfo($originalName, PATHINFO_FILENAME);
    $safeBaseName = preg_replace('/[^a-zA-Z0-9_-]+/', '_', $baseName) ?: 'nps_statement';
    $filename = $safeBaseName . '_' . date('Ymd_His') . '.csv';
    $targetPath = $uploadDir . '/' . $filename;

    if (!move_uploaded_file((string) $file['tmp_name'], $targetPath)) {
        http_response_code(500);
        echo json_encode(['ok' => false, 'error' => 'Unable to store the NPS statement file.']);
        exit;
    }

    echo json_encode(nps_statement_build_payload($targetPath, $allowedProfile), JSON_UNESCAPED_SLASHES);
    exit;
}

$currentFile = nps_statement_get_latest_file($uploadDir);
if ($currentFile === null) {
    echo json_encode([
        'ok' => true,
        'profile' => $allowedProfile,
        'has_statement' => false,
        'source_file' => '',
        'source_name' => '',
        'uploaded_at' => '',
        'subscriber' => ['pran' => '', 'subscriber_name' => ''],
        'statement' => ['generation_date' => '', 'scheme_choice' => ''],
        'investment_summary' => [
            'as_on' => '',
            'holdings' => '',
            'contributions_count' => '',
            'total_contribution' => '',
            'total_withdrawal' => '',
            'notional_gain_loss' => '',
            'intermediary_charges' => '',
            'xirr' => '',
        ],
        'scheme_summary' => [],
        'contribution_details' => [],
        'transaction_groups' => [],
    ], JSON_UNESCAPED_SLASHES);
    exit;
}

echo json_encode(nps_statement_build_payload($currentFile, $allowedProfile), JSON_UNESCAPED_SLASHES);
