<?php
/* =======================
   Attendance Dashboard (DriverDocs/attendance.php)
   ======================= */

ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

if (session_status() === PHP_SESSION_NONE) session_start();
require __DIR__ . '/../includes/auth.php';
checkRole(['admin', 'supervisor']);

require_once __DIR__ . '/../../conf/config.php';
if (!isset($conn) || !($conn instanceof mysqli)) {
  die('Database connection ($conn) not available');
}
$conn->set_charset('utf8mb4');

function h($value) {
  return htmlspecialchars((string)$value, ENT_QUOTES, 'UTF-8');
}

$ACTIVE_MENU = 'attendance_dashboard';

$today = date('Y-m-d');
$defaultFrom = date('Y-m-01');

$statusFilter = isset($_GET['status']) ? trim($_GET['status']) : 'Pending';
$fromDate = isset($_GET['from']) && $_GET['from'] !== '' ? $_GET['from'] : $defaultFrom;
$toDate = isset($_GET['to']) && $_GET['to'] !== '' ? $_GET['to'] : $today;
$plantFilter = isset($_GET['plant']) && ctype_digit($_GET['plant']) ? (int)$_GET['plant'] : null;

if (strtotime($fromDate) === false) {
  $fromDate = $defaultFrom;
}
if (strtotime($toDate) === false || $toDate < $fromDate) {
  $toDate = $today;
}

$conditions = ["COALESCE(d.role, 'driver') IN ('supervisor', 'driver')"];
$types = '';
$params = [];

$conditions[] = 'DATE(a.in_time) BETWEEN ? AND ?';
$types .= 'ss';
$params[] = $fromDate;
$params[] = $toDate;

if ($statusFilter !== '' && strcasecmp($statusFilter, 'All') !== 0) {
  $conditions[] = 'a.approval_status = ?';
  $types .= 's';
  $params[] = $statusFilter;
}

if ($plantFilter) {
  $conditions[] = 'a.plant_id = ?';
  $types .= 'i';
  $params[] = $plantFilter;
}

$sql = 'SELECT a.id,
               a.driver_id,
               d.name AS driver_name,
               COALESCE(d.role, "driver") AS driver_role,
               a.plant_id,
               p.plant_name,
               a.vehicle_id,
               v.vehicle_no,
               a.in_time,
               a.out_time,
               a.approval_status,
               a.source,
               a.notes
          FROM attendance a
     LEFT JOIN drivers d ON d.id = a.driver_id
     LEFT JOIN plants p  ON p.id = a.plant_id
     LEFT JOIN vehicles v ON v.id = a.vehicle_id
         WHERE ' . implode(' AND ', $conditions) . '
      ORDER BY a.in_time DESC
         LIMIT 300';

$stmt = $conn->prepare($sql);
if ($types !== '') {
  $stmt->bind_param($types, ...$params);
}
$stmt->execute();
$records = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
$stmt->close();

$groupMap = [];
$groupKeys = [];

foreach ($records as $record) {
  $driverId = isset($record['driver_id']) ? (int)$record['driver_id'] : 0;
  $inTimeRaw = $record['in_time'] ?? '';
  $outTimeRaw = $record['out_time'] ?? '';
  $dateKey = '';

  if ($inTimeRaw !== '') {
    $dateKey = substr($inTimeRaw, 0, 10);
  } elseif ($outTimeRaw !== '') {
    $dateKey = substr($outTimeRaw, 0, 10);
  }

  if ($dateKey === '') {
    continue;
  }

  $groupKey = $driverId . '|' . $dateKey;

  if (!isset($groupMap[$groupKey])) {
    $groupMap[$groupKey] = [
      'driverId' => $driverId,
      'driverName' => $record['driver_name'] ?? '',
      'driverRole' => $record['driver_role'] ?? 'driver',
      'date' => $dateKey,
      'entries' => [],
      'attendanceIds' => [],
      'plantIds' => [],
      'plantNames' => [],
      'vehicleNumbers' => [],
      'statuses' => [],
      'sources' => [],
      'notes' => [],
    ];
    $groupKeys[] = $groupKey;
  }

  $group = &$groupMap[$groupKey];
  $group['entries'][] = $record;

  if (!empty($record['id'])) {
    $group['attendanceIds'][] = (int)$record['id'];
  }

  if (!empty($record['plant_id'])) {
    $group['plantIds'][(int)$record['plant_id']] = (int)$record['plant_id'];
  }
  if (!empty($record['plant_name'])) {
    $group['plantNames'][$record['plant_name']] = $record['plant_name'];
  }

  if (!empty($record['vehicle_no'])) {
    $group['vehicleNumbers'][$record['vehicle_no']] = $record['vehicle_no'];
  }

  $statusValue = $record['approval_status'] ?? '';
  if ($statusValue === '') {
    $statusValue = 'Pending';
  }
  $group['statuses'][] = $statusValue;

  $sourceValue = $record['source'] ?? '';
  if ($sourceValue === '') {
    $sourceValue = 'mobile';
  }
  $group['sources'][$sourceValue] = $sourceValue;

  if (!empty($record['notes'])) {
    $group['notes'][] = $record['notes'];
  }
}

$groupedRecords = [];

foreach ($groupKeys as $groupKey) {
  $group = $groupMap[$groupKey];
  $entries = $group['entries'];

  usort($entries, static function (array $a, array $b): int {
    $aKey = $a['in_time'] ?? '';
    $bKey = $b['in_time'] ?? '';
    if ($aKey === '' && !empty($a['out_time'])) {
      $aKey = $a['out_time'];
    }
    if ($bKey === '' && !empty($b['out_time'])) {
      $bKey = $b['out_time'];
    }
    return strcmp($aKey, $bKey);
  });

  $firstIn = null;
  $lastOut = null;
  foreach ($entries as $entry) {
    $inTime = $entry['in_time'] ?? '';
    $outTime = $entry['out_time'] ?? '';

    if ($inTime !== '' && ($firstIn === null || $inTime < $firstIn)) {
      $firstIn = $inTime;
    }
    if ($outTime !== '' && ($lastOut === null || $outTime > $lastOut)) {
      $lastOut = $outTime;
    }
  }

  $statusPriority = ['pending' => 1, 'rejected' => 2, 'approved' => 3];
  $effectiveStatus = 'Pending';
  $bestScore = PHP_INT_MAX;
  foreach ($group['statuses'] as $status) {
    $normalized = strtolower($status);
    $score = $statusPriority[$normalized] ?? 4;
    if ($score < $bestScore) {
      $bestScore = $score;
      $effectiveStatus = $status;
    }
  }

  $groupedRecords[] = [
    'driverId' => $group['driverId'],
    'driverName' => $group['driverName'],
    'driverRole' => $group['driverRole'] ?? 'driver',
    'dateKey' => $group['date'],
    'dateLabel' => date('d M Y', strtotime($group['date'])),
    'attendanceIds' => array_values(array_unique($group['attendanceIds'])),
    'entries' => $entries,
    'plantLabel' => !empty($group['plantNames']) ? implode(', ', array_values($group['plantNames'])) : '—',
    'plantIds' => array_values($group['plantIds']),
    'vehicleLabel' => !empty($group['vehicleNumbers']) ? implode(', ', array_values($group['vehicleNumbers'])) : '-',
    'status' => $effectiveStatus,
    'sources' => implode(', ', array_values($group['sources'])),
    'notes' => !empty($group['notes']) ? implode(' • ', array_unique($group['notes'])) : '',
    'firstIn' => $firstIn,
    'lastOut' => $lastOut,
  ];
}

$supervisorGroups = [];
$driverGroups = [];
foreach ($groupedRecords as $group) {
  if (strcasecmp($group['driverRole'] ?? 'driver', 'supervisor') === 0) {
    $supervisorGroups[] = $group;
  } else {
    $driverGroups[] = $group;
  }
}

function sortAttendanceGroupsByRecent(array &$groups): void {
  usort($groups, static function (array $a, array $b): int {
    $aKey = $a['lastOut'] ?? $a['firstIn'] ?? ($a['dateKey'] . ' 00:00:00');
    $bKey = $b['lastOut'] ?? $b['firstIn'] ?? ($b['dateKey'] . ' 00:00:00');
    return strcmp($bKey, $aKey);
  });
}

sortAttendanceGroupsByRecent($supervisorGroups);
sortAttendanceGroupsByRecent($driverGroups);

$statusBuckets = [
  'Pending' => 0,
  'Approved' => 0,
  'Rejected' => 0,
  'Other' => 0,
];

foreach ($groupedRecords as $group) {
  $status = $group['status'] ?? '';
  $normalized = ucfirst(strtolower($status));
  if (isset($statusBuckets[$normalized])) {
    $statusBuckets[$normalized]++;
  } else {
    $statusBuckets['Other']++;
  }
}

$totalRecords = count($groupedRecords);

$plantList = [];
$plantResult = $conn->query('SELECT id, plant_name FROM plants ORDER BY plant_name ASC');
while ($plantResult && $row = $plantResult->fetch_assoc()) {
  $plantList[(int)$row['id']] = $row['plant_name'];
}

$missingSql = "SELECT d.id,
                      d.name,
                      COALESCE(d.role, 'driver') AS role,
                      d.plant_id,
                      p.plant_name
                 FROM drivers d
            LEFT JOIN plants p ON p.id = d.plant_id
                WHERE d.status = 'Active'
                  AND COALESCE(d.role, 'driver') IN ('supervisor', 'driver')";

$missingTypes = '';
$missingParams = [];

if ($plantFilter) {
  $missingSql .= ' AND d.plant_id = ?';
  $missingTypes .= 'i';
  $missingParams[] = $plantFilter;
}

$missingSql .= ' AND NOT EXISTS (
    SELECT 1 FROM attendance a
     WHERE a.driver_id = d.id
       AND DATE(a.in_time) BETWEEN ? AND ?';
$missingTypes .= 'ss';
$missingParams[] = $fromDate;
$missingParams[] = $toDate;

if ($plantFilter) {
  $missingSql .= ' AND a.plant_id = ?';
  $missingTypes .= 'i';
  $missingParams[] = $plantFilter;
}

$missingSql .= ' )
   ORDER BY p.plant_name ASC, d.name ASC';

$missingStmt = $conn->prepare($missingSql);
if ($missingTypes !== '') {
  $missingStmt->bind_param($missingTypes, ...$missingParams);
}
$missingStmt->execute();
$missingResult = $missingStmt->get_result();
$missingPeople = [];
while ($row = $missingResult->fetch_assoc()) {
  $missingPeople[] = [
    'id' => (int)$row['id'],
    'name' => $row['name'],
    'role' => $row['role'],
    'plantId' => $row['plant_id'] !== null ? (int)$row['plant_id'] : null,
    'plantName' => $row['plant_name'],
  ];
}
$missingStmt->close();

function renderGroupedAttendanceCard(array $groups, string $title, string $subtitle, string $emptyMessage): void {
  ?>
  <div class="card shadow-soft border-0 mb-3">
    <div class="card-body">
      <div class="d-flex justify-content-between align-items-center mb-3">
        <h2 class="h6 mb-0"><?= h($title) ?></h2>
        <span class="text-muted small"><?= h($subtitle) ?></span>
      </div>

      <div class="table-responsive">
        <table class="table table-sm table-striped align-middle">
          <thead class="table-light">
            <tr>
              <th>Date</th>
              <th>Person</th>
              <th>Attendance IDs</th>
              <th>Plant(s)</th>
              <th>Vehicle(s)</th>
              <th>Timeline</th>
              <th>Status</th>
              <th>Notes</th>
            </tr>
          </thead>
          <tbody>
            <?php if (empty($groups)): ?>
              <tr>
                <td colspan="8" class="text-center text-muted py-4"><?= h($emptyMessage) ?></td>
              </tr>
            <?php else: ?>
              <?php foreach ($groups as $group): ?>
                <tr>
                  <td>
                    <strong><?= h($group['dateLabel']) ?></strong><br>
                    <span class="text-muted small">Entries: <?= count($group['entries']) ?></span>
                  </td>
                  <td>
                    <strong><?= h($group['driverName'] ?: 'Unmapped') ?></strong><br>
                    <span class="text-muted small">ID: <?= h($group['driverId']) ?> • <?= h(ucfirst($group['driverRole'] ?? 'driver')) ?></span>
                  </td>
                  <td>
                    <?php if (!empty($group['attendanceIds'])): ?>
                      <?= h(implode(', ', $group['attendanceIds'])) ?>
                    <?php else: ?>
                      <span class="text-muted">—</span>
                    <?php endif; ?>
                  </td>
                  <td>
                    <?= h($group['plantLabel']) ?><br>
                    <?php if (!empty($group['plantIds'])): ?>
                      <span class="text-muted small">#<?= h(implode(', #', $group['plantIds'])) ?></span>
                    <?php endif; ?>
                  </td>
                  <td><?= h($group['vehicleLabel']) ?></td>
                  <td>
                    <ul class="list-unstyled mb-0 small">
                      <?php foreach ($group['entries'] as $entry): ?>
                        <?php
                          $inTime = $entry['in_time'] ?? '';
                          $outTime = $entry['out_time'] ?? '';
                          $inLabel = $inTime !== '' ? date('H:i', strtotime($inTime)) : '—';
                          $outLabel = $outTime !== '' ? date('H:i', strtotime($outTime)) : 'Open';
                          $entryStatus = $entry['approval_status'] ?? 'Pending';
                        ?>
                        <li>
                          <strong><?= h($inLabel) ?></strong> → <strong><?= h($outLabel) ?></strong>
                          <span class="text-muted">(<?= h($entryStatus) ?>)</span>
                          <?php if (!empty($entry['plant_name'])): ?>
                            <span class="text-muted">• <?= h($entry['plant_name']) ?></span>
                          <?php endif; ?>
                          <?php if (!empty($entry['vehicle_no'])): ?>
                            <span class="text-muted">[<?= h($entry['vehicle_no']) ?>]</span>
                          <?php endif; ?>
                        </li>
                      <?php endforeach; ?>
                    </ul>
                  </td>
                  <td>
                    <?php
                      $status = $group['status'] ?: 'Pending';
                      $badge = 'secondary';
                      if (strcasecmp($status, 'Pending') === 0) {
                        $badge = 'warning';
                      } elseif (strcasecmp($status, 'Approved') === 0) {
                        $badge = 'success';
                      } elseif (strcasecmp($status, 'Rejected') === 0) {
                        $badge = 'danger';
                      }
                    ?>
                    <span class="badge text-bg-<?= $badge ?> status-badge"><?= h($status) ?></span>
                    <div class="text-muted small mt-1"><?= h($group['sources']) ?></div>
                  </td>
                  <td class="notes">
                    <?php if ($group['notes'] !== ''): ?>
                      <span class="text-muted small"><?= nl2br(h($group['notes'])) ?></span>
                    <?php else: ?>
                      <span class="text-muted small">—</span>
                    <?php endif; ?>
                  </td>
                </tr>
              <?php endforeach; ?>
            <?php endif; ?>
          </tbody>
        </table>
      </div>
    </div>
  </div>
  <?php
}

?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Attendance Dashboard</title>

  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Josefin+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">

  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
  <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">
  <link href="assets/css/custom.css" rel="stylesheet">
  <link rel="icon" href="/images/logo_new.png" type="image/x-icon">

  <style>
    body { background:#f5f6f8; padding-top:56px; font-family:'Josefin Sans', system-ui, sans-serif; }
    .page-gutter { padding: 10px 12px 0; }
    .main-like { background:#fff; min-height:calc(100vh - 56px); border-left:1px solid rgba(0,0,0,.06); padding:0 1rem 2rem; }
    .shadow-soft { box-shadow:0 6px 18px rgba(0,0,0,.05); }
    .header-bar { background:#ffe8cc; border:1px solid #ffbf70; }
    .status-badge { font-size:.85rem; }
    .table-responsive { max-height:70vh; }
    .notes { max-width:260px; }
  </style>
</head>
<body>
<?php include 'includes/navbar.php'; ?>

<div class="page-gutter">
  <div class="container-fluid">
    <div class="row gx-3">
      <?php include 'includes/sidebar.php'; ?>

      <main class="main-like col-md-9 ms-sm-auto col-lg-10">
        <div class="pt-3 pb-2 mb-3 header-bar rounded">
          <div class="d-flex flex-wrap justify-content-between align-items-center gap-2 px-2">
            <div class="d-flex align-items-center gap-2">
              <i class="fa-solid fa-user-check"></i>
              <h1 class="h5 mb-0">Attendance Overview</h1>
              <span class="badge text-bg-light">Showing <?= h(date('d M Y', strtotime($fromDate))) ?> → <?= h(date('d M Y', strtotime($toDate))) ?></span>
            </div>

            <form class="d-flex flex-wrap align-items-end gap-2" method="get">
              <div class="input-group input-group-sm" style="width:auto">
                <span class="input-group-text">Status</span>
                <select name="status" class="form-select">
                  <?php foreach (['All','Pending','Approved','Rejected'] as $option): ?>
                    <option value="<?= h($option) ?>" <?= strcasecmp($statusFilter, $option) === 0 ? 'selected' : '' ?>><?= h($option) ?></option>
                  <?php endforeach; ?>
                </select>
              </div>
              <div class="input-group input-group-sm" style="width:auto">
                <span class="input-group-text">Plant</span>
                <select name="plant" class="form-select">
                  <option value="">All Plants</option>
                  <?php foreach ($plantList as $id => $name): ?>
                    <option value="<?= $id ?>" <?= $plantFilter === $id ? 'selected' : '' ?>><?= h($name) ?></option>
                  <?php endforeach; ?>
                </select>
              </div>
              <div class="input-group input-group-sm" style="width:auto">
                <span class="input-group-text">From</span>
                <input type="date" name="from" class="form-control" value="<?= h($fromDate) ?>">
              </div>
              <div class="input-group input-group-sm" style="width:auto">
                <span class="input-group-text">To</span>
                <input type="date" name="to" class="form-control" value="<?= h($toDate) ?>">
              </div>
              <button type="submit" class="btn btn-sm btn-primary"><i class="fa-solid fa-magnifying-glass"></i></button>
            </form>
          </div>
        </div>

        <div class="row g-3 mb-3">
          <div class="col-sm-3">
            <div class="card shadow-soft border-0">
              <div class="card-body">
                <p class="text-muted text-uppercase fw-semibold mb-1">Total Records</p>
                <h3 class="mb-0"><?= number_format($totalRecords) ?></h3>
              </div>
            </div>
          </div>
          <div class="col-sm-3">
            <div class="card shadow-soft border-0">
              <div class="card-body">
                <p class="text-muted text-uppercase fw-semibold mb-1">Pending</p>
                <h3 class="mb-0 text-warning"><?= number_format($statusBuckets['Pending']) ?></h3>
              </div>
            </div>
          </div>
          <div class="col-sm-3">
            <div class="card shadow-soft border-0">
              <div class="card-body">
                <p class="text-muted text-uppercase fw-semibold mb-1">Approved</p>
                <h3 class="mb-0 text-success"><?= number_format($statusBuckets['Approved']) ?></h3>
              </div>
            </div>
          </div>
          <div class="col-sm-3">
            <div class="card shadow-soft border-0">
              <div class="card-body">
                <p class="text-muted text-uppercase fw-semibold mb-1">Rejected / Other</p>
                <h3 class="mb-0 text-danger"><?= number_format($statusBuckets['Rejected'] + $statusBuckets['Other']) ?></h3>
              </div>
            </div>
          </div>
        </div>

        <?php
          renderGroupedAttendanceCard(
            $supervisorGroups,
            'Supervisor Attendance (grouped by person/day)',
            number_format(count($supervisorGroups)) . ' record(s) • latest 300 raw entries',
            'No supervisor attendance matches the current filters.'
          );
          renderGroupedAttendanceCard(
            $driverGroups,
            'Driver Attendance (grouped by person/day)',
            number_format(count($driverGroups)) . ' record(s) • latest 300 raw entries',
            'No driver attendance matches the current filters.'
          );
        ?>

        <div class="card shadow-soft border-0 mt-3">
          <div class="card-body">
            <div class="d-flex justify-content-between align-items-center mb-3">
              <h2 class="h6 mb-0">People Without Attendance (<?= h(date('d M Y', strtotime($fromDate))) ?> → <?= h(date('d M Y', strtotime($toDate))) ?>)</h2>
              <span class="text-muted small"><?= number_format(count($missingPeople)) ?> record(s)</span>
            </div>

            <?php if (empty($missingPeople)): ?>
              <div class="text-muted small">Everyone has an attendance entry for the selected range.</div>
            <?php else: ?>
              <div class="table-responsive">
                <table class="table table-sm table-hover align-middle">
                  <thead class="table-light">
                    <tr>
                      <th>Name</th>
                      <th>Role</th>
                      <th>Plant</th>
                    </tr>
                  </thead>
                  <tbody>
                    <?php foreach ($missingPeople as $person): ?>
                      <tr>
                        <td><strong><?= h($person['name']) ?></strong><span class="text-muted small ms-2">#<?= h($person['id']) ?></span></td>
                        <td><?= h(ucfirst($person['role'] ?? 'driver')) ?></td>
                        <td><?= h($person['plantName'] ?? 'Not mapped') ?></td>
                      </tr>
                    <?php endforeach; ?>
                  </tbody>
                </table>
              </div>
            <?php endif; ?>
          </div>
        </div>

      </main>
    </div>
  </div>
</div>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
