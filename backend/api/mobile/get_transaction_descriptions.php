<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require __DIR__ . '/common.php';

try {
    $createTableSql = "
        CREATE TABLE IF NOT EXISTS transaction_descriptions (
            id INT(11) NOT NULL AUTO_INCREMENT,
            label VARCHAR(100) NOT NULL UNIQUE,
            sort_order INT(11) NOT NULL DEFAULT 0,
            is_active TINYINT(1) NOT NULL DEFAULT 1,
            created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ";

    if (!$conn->query($createTableSql)) {
        throw new RuntimeException('Unable to ensure transaction_descriptions table exists.');
    }

    $defaultLabels = [
        'ADVANCE',
        'BODY FABRICATION',
        'CHARGES',
        'DA',
        'DEF',
        'DRIVETRACK',
        'EXTRA',
        'FASTAG',
        'FUEL',
        'HOME',
        'INCENTIVE',
        'MAINTENANCE',
        'MEDICAL',
        'MISCELLANEOUS',
        'OFFICE',
        'PAPER',
        'ROOM',
        'SAFETY',
        'SALARY',
        'TOLL',
        'TRAINING',
        'TRAVEL',
        'TYRE',
        'UNIFORM',
    ];

    $insertStmt = $conn->prepare(
        'INSERT IGNORE INTO transaction_descriptions (label, sort_order) VALUES (?, ?)'
    );

    foreach ($defaultLabels as $index => $label) {
        $labelText = trim($label);
        if ($labelText === '') {
            continue;
        }
        $insertStmt->bind_param('si', $labelText, $index);
        $insertStmt->execute();
    }
    $insertStmt->close();

    $result = $conn->query(
        'SELECT label FROM transaction_descriptions WHERE is_active = 1 ORDER BY sort_order ASC, label ASC'
    );

    $descriptions = [];
    if ($result) {
        while ($row = $result->fetch_assoc()) {
            $descriptions[] = $row['label'];
        }
        $result->free();
    }

    apiRespond(200, [
        'status' => 'ok',
        'descriptions' => $descriptions,
        'count' => count($descriptions),
    ]);
} catch (Throwable $error) {
    apiRespond(500, [
        'status' => 'error',
        'error' => $error->getMessage(),
    ]);
}
