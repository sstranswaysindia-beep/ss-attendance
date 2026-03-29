<?php
require_once __DIR__ . '/../conf/config.php';
$res = $conn->query("DESCRIBE safety_training_progress");
while ($r = $res->fetch_assoc()) {
    echo $r['Field'] . " - " . $r['Type'] . "\n";
}
