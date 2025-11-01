<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

$modules = [
    ['key' => 'tyre_checklist', 'label' => 'Tyre Checklist'],
    ['key' => 'incab', 'label' => 'In-Cab'],
    ['key' => 'spot_audit', 'label' => 'Spot Audit'],
    ['key' => 'training', 'label' => 'Training'],
];

apiRespond(200, ['ok' => true, 'modules' => $modules]);
