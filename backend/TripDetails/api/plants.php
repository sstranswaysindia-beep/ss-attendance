<?php
require __DIR__ . '/_auth_guard.php';
require __DIR__ . '/../../../conf/config.php';
require __DIR__ . '/bootstrap.php';

$plants = [];
$res = $conn->query("SELECT id, plant_name FROM plants ORDER BY plant_name");
while ($row = $res->fetch_assoc()) $plants[] = $row;

respond(['plants' => $plants]);