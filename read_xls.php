<?php
require_once __DIR__ . '/../DriverDocs/vendor/autoload.php';

use PhpOffice\PhpSpreadsheet\IOFactory;

$file = __DIR__ . '/../DriverDocs/SS_TRANSWAYS_INDIA-FBD _ DRIVER JOURNEY SUMMARY WEEKLY REPORT_01-05-26 12_10_01.xls';

if (!file_exists($file)) {
    die("File not found");
}

try {
    $reader = IOFactory::createReaderForFile($file);
    $reader->setReadDataOnly(true);
    $spreadsheet = $reader->load($file);
    $sheet = $spreadsheet->getActiveSheet();
    $rows = $sheet->toArray();

    foreach (array_slice($rows, 0, 10) as $row) {
        echo implode(" | ", array_map(function ($c) {
            return json_encode($c); }, $row)) . "\n";
    }
} catch (\Throwable $e) {
    if (class_exists('\Shuchkin\SimpleXLS')) {
        $xls = \Shuchkin\SimpleXLS::parse($file);
        if ($xls) {
            foreach (array_slice($xls->rows(), 0, 10) as $row) {
                echo implode(" | ", array_map(function ($c) {
                    return json_encode($c); }, $row)) . "\n";
            }
        } else {
            echo "Error: " . \Shuchkin\SimpleXLS::parseError() . "\n";
        }
    } else {
        echo "Error: " . $e->getMessage() . "\n";
    }
}
