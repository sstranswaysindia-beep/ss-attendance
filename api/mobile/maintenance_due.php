<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/common.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    apiRespond(405, ['status' => 'error', 'error' => 'Method not allowed']);
}

$supervisorRaw = $_GET['supervisorUserId'] ?? $_GET['userId'] ?? '';
$plantFilterRaw = $_GET['plant_id'] ?? $_GET['plantId'] ?? null;

if (!is_numeric($supervisorRaw)) {
    apiRespond(400, ['status' => 'error', 'error' => 'Missing or invalid supervisorUserId']);
}

$supervisorUserId = (int) $supervisorRaw;
$plantFilter = null;
if ($plantFilterRaw !== null && $plantFilterRaw !== '') {
    if (is_numeric($plantFilterRaw)) {
        $plantFilter = (int) $plantFilterRaw;
    } else {
        apiRespond(400, ['status' => 'error', 'error' => 'Invalid plant_id filter']);
    }
}

$scope = strtolower(trim((string) ($_GET['scope'] ?? 'due')));
if (!in_array($scope, ['due', 'overdue', 'all'], true)) {
    $scope = 'due';
}

/* ---------- Helpers (copied from DriverDocs maintenance_due.php) ---------- */
function date_status(?string $nextDate): array {
    if (!$nextDate) return ['—', 'pill-muted', null];
    try {
        $today = new DateTime('today');
        $d     = new DateTime($nextDate);
        $diff  = (int)$today->diff($d)->format('%r%a');
    if ($diff < 0)   return ['Expired', 'pill-bad', $diff];
        if ($diff <= 30) return [$diff . 'd', 'pill-warn', $diff];
        return [$diff . 'd', 'pill-ok', $diff];
    } catch (Throwable $e) {
        return ['—', 'pill-muted', null];
    }
}

function km_status($currentKm, ?int $nextKm): array {
    if ($currentKm === null || $currentKm === '' || $nextKm === null) return ['—', 'pill-muted', null];
    $currentKm = (float)$currentKm;
    $remaining = (int)$nextKm - (int)$currentKm;
    if ($remaining <= 0) {
        $expiredBy = abs($remaining);
        $label = $expiredBy > 0 ? "Expired by {$expiredBy} km" : 'Expired';
        return [$label, 'pill-bad', $remaining];
    }
    if ($remaining <= 1000) return ['Due Soon', 'pill-warn', $remaining];
    return ['Not Due', 'pill-ok', $remaining];
}

function stricter_class(string $a, string $b): string {
    $rank = ['pill-bad' => 3, 'pill-warn' => 2, 'pill-ok' => 1, 'pill-muted' => 0];
    $ca = $rank[strtok($a, ' ')] ?? 0;
    $cb = $rank[strtok($b, ' ')] ?? 0;
    return ($ca >= $cb) ? $a : $b;
}

function severity_from_class(string $cls): string {
    $base = strtok($cls, ' ');
    if ($base === 'pill-bad')  return 'overdue';
    if ($base === 'pill-warn') return 'due_soon';
    if ($base === 'pill-ok')   return 'ok';
    return 'na';
}

function should_include_by_scope(string $severity, string $scope): bool {
    if ($scope === 'all') return true;
    if ($scope === 'overdue') return ($severity === 'overdue');
    return ($severity === 'overdue' || $severity === 'due_soon');
}

try {
    $roleStmt = $conn->prepare('SELECT role FROM users WHERE id = ? LIMIT 1');
    if (!$roleStmt) {
        throw new RuntimeException('Failed to prepare role lookup.');
    }
    $roleStmt->bind_param('i', $supervisorUserId);
    $roleStmt->execute();
    $roleRow = $roleStmt->get_result()->fetch_assoc();
    $roleStmt->close();
    if (!$roleRow) {
        apiRespond(404, ['status' => 'error', 'error' => 'User not found']);
    }
    $role = strtolower((string) ($roleRow['role'] ?? ''));

    $plantIds = [];
    if ($role === 'admin') {
        if ($plantFilter !== null) {
            $plantIds[$plantFilter] = true;
        }
    } else {
        if ($role !== 'supervisor') {
            apiRespond(403, ['status' => 'error', 'error' => 'Access denied']);
        }

        $directStmt = $conn->prepare('SELECT id FROM plants WHERE supervisor_user_id = ?');
        if ($directStmt) {
            $directStmt->bind_param('i', $supervisorUserId);
            $directStmt->execute();
            $directResult = $directStmt->get_result();
            while ($row = $directResult->fetch_assoc()) {
                $plantId = (int) $row['id'];
                $plantIds[$plantId] = true;
            }
            $directStmt->close();
        }

        $linkedStmt = $conn->prepare(
            'SELECT plant_id FROM supervisor_plants WHERE user_id = ?'
        );
        if ($linkedStmt) {
            $linkedStmt->bind_param('i', $supervisorUserId);
            $linkedStmt->execute();
            $linkedResult = $linkedStmt->get_result();
            while ($row = $linkedResult->fetch_assoc()) {
                $plantId = (int) $row['plant_id'];
                $plantIds[$plantId] = true;
            }
            $linkedStmt->close();
        }

        if (!empty($plantIds) && $plantFilter !== null) {
            if (!isset($plantIds[$plantFilter])) {
                apiRespond(403, ['status' => 'error', 'error' => 'You do not have access to this plant.']);
            }
            $plantIds = [$plantFilter => true];
        }
    }

    if (empty($plantIds) && $role !== 'admin') {
        apiRespond(200, [
            'status' => 'ok',
            'generated_at' => date('Y-m-d H:i:s'),
            'scope' => $scope,
            'plants' => [],
        ]);
    }

    $where = ["v.disable_flag = 'Y'"];
    $types = '';
    $args = [];

    if (!empty($plantIds)) {
        $placeholders = implode(',', array_fill(0, count($plantIds), '?'));
        $where[] = "v.plant_id IN ($placeholders)";
        $types .= str_repeat('i', count($plantIds));
        $args = array_values(array_map('intval', array_keys($plantIds)));
    }

    $sql = "
      SELECT
        p.id   AS plant_id,
        p.plant_name,
        p.location AS plant_location,
        v.id   AS vehicle_id,
        v.vehicle_no,
        vm.current_km,

        vm.next_oil_service_km,  vm.oil_next_date,
        vm.next_hub_greasing_km, vm.hub_next_date,
        vm.next_ra_oil_km,       vm.ra_next_date,
        vm.next_gear_oil_km,     vm.gear_next_date

      FROM vehicles v
      JOIN plants p ON p.id = v.plant_id
      LEFT JOIN vehicle_maintenance vm ON vm.vehicle_id = v.id
      WHERE " . implode(' AND ', $where) . "
      ORDER BY p.plant_name ASC, v.vehicle_no ASC
    ";

    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        throw new RuntimeException('Failed to prepare maintenance query.');
    }
    if ($types !== '') {
        $stmt->bind_param($types, ...$args);
    }
    $stmt->execute();
    $rs = $stmt->get_result();

    $plants = [];
    while ($r = $rs->fetch_assoc()) {
        $services = [
            [
                'key'     => 'oil',
                'title'   => 'Oil Service',
                'next_km' => $r['next_oil_service_km'] !== null ? (int)$r['next_oil_service_km'] : null,
                'next_dt' => $r['oil_next_date'] ?? null,
            ],
            [
                'key'     => 'hub',
                'title'   => 'Hub Greasing',
                'next_km' => $r['next_hub_greasing_km'] !== null ? (int)$r['next_hub_greasing_km'] : null,
                'next_dt' => $r['hub_next_date'] ?? null,
            ],
            [
                'key'     => 'ra',
                'title'   => 'R/A Oil',
                'next_km' => $r['next_ra_oil_km'] !== null ? (int)$r['next_ra_oil_km'] : null,
                'next_dt' => $r['ra_next_date'] ?? null,
            ],
            [
                'key'     => 'gear',
                'title'   => 'Gear Oil',
                'next_km' => $r['next_gear_oil_km'] !== null ? (int)$r['next_gear_oil_km'] : null,
                'next_dt' => $r['gear_next_date'] ?? null,
            ],
        ];

        $dueItems = [];
        $overallWorstRank = -1;
        $overallLabel = 'Not Due';
        $overallSeverity = 'ok';
        $rank = ['na'=>0,'ok'=>1,'due_soon'=>2,'overdue'=>3];

        foreach ($services as $s) {
            $km = km_status($r['current_km'], $s['next_km']);
            $dt = date_status($s['next_dt']);
            $worstClass = stricter_class($km[1], $dt[1]);
            $sev = severity_from_class($worstClass);

            if (should_include_by_scope($sev, $scope)) {
                $dueItems[] = [
                    'key'      => $s['key'],
                    'label'    => $s['title'],
                    'severity' => $sev,
                    'by_km' => [
                        'label'        => $km[0],
                        'remaining_km' => $km[2],
                        'next_km'      => $s['next_km'],
                    ],
                    'by_date' => [
                        'label'       => $dt[0],
                        'days'        => $dt[2],
                        'next_date'   => $s['next_dt'],
                    ],
                ];
            }

            if (($rank[$sev] ?? 0) > $overallWorstRank) {
                $overallWorstRank = $rank[$sev] ?? 0;
                $overallSeverity  = $sev;
                $overallLabel     = ($sev === 'overdue') ? 'Expired'
                                : (($sev === 'due_soon') ? 'Due Soon'
                                : (($sev === 'ok') ? 'Not Due' : '—'));
            }
        }

        if (($scope === 'due' || $scope === 'overdue') && count($dueItems) === 0) {
            continue;
        }

        $pid = (int)$r['plant_id'];
        if (!isset($plants[$pid])) {
            $plants[$pid] = [
                'plant_id'   => $pid,
                'plant_name' => $r['plant_name'],
                'location'   => $r['plant_location'],
                'vehicles'   => [],
            ];
        }

        $plants[$pid]['vehicles'][] = [
            'vehicle_id'  => (int)$r['vehicle_id'],
            'vehicle_no'  => $r['vehicle_no'],
            'current_km'  => ($r['current_km'] === null || $r['current_km'] === '') ? null : (float)$r['current_km'],
            'overall'     => ['label' => $overallLabel, 'severity' => $overallSeverity],
            'due_items'   => $dueItems,
        ];
    }

    $stmt->close();

    apiRespond(200, [
        'status' => 'ok',
        'generated_at' => date('Y-m-d H:i:s'),
        'scope' => $scope,
        'plants' => array_values($plants),
    ]);
} catch (Throwable $e) {
    apiRespond(500, ['status' => 'error', 'error' => 'Server error']);
}
