<?php
$ROOT = '/Users/neerajsachan/SS Transways India'; // => public_html
$configs = [
    $ROOT . '/conf/config.php',
    $ROOT . '/../conf/config.php',
    $ROOT . '/DriverDocs/conf/config.php'
];
$DB_CONFIG = false;
foreach ($configs as $p) {
    if (file_exists($p)) {
        $DB_CONFIG = $p;
        break;
    }
}
if (!$DB_CONFIG) {
    echo "Config not found!\n";
    exit;
}
require_once $DB_CONFIG;
if (!$conn) {
    echo "No DB conn in: $DB_CONFIG\n";
    exit;
}
echo "Using config: $DB_CONFIG\n";
$res = $conn->query("SHOW CREATE TABLE fleet_summary_monthly");
if ($res) {
    print_r($res->fetch_assoc());
} else {
    echo "Table fleet_summary_monthly not found, error: " . $conn->error . "\n";
}
?>