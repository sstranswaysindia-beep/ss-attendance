<?php
/* =======================
   Trips Monitor (DriverDocs/trips.php)
   ======================= */

ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

if (session_status() === PHP_SESSION_NONE) session_start();
require __DIR__ . '/../includes/auth.php';
checkRole(['admin','supervisor']);

require_once __DIR__ . '/../../conf/config.php';
if (!isset($conn) || !($conn instanceof mysqli)) {
  die("Database connection (\$conn) not available");
}
$conn->set_charset('utf8mb4');

function h($s){ return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); }
function dmy($ymd){ return $ymd ? date('d-m-Y', strtotime($ymd)) : ''; }
function days_between($from, $to){
  $a = strtotime($from); $b = strtotime($to);
  if (!$a || !$b) return null;
  return (int)floor(($b - $a)/86400);
}

$ACTIVE_MENU = 'trips_monitor';

/* ---------- Date filters ---------- */
/* Defaults: current month */
$curY = (int)date('Y'); $curM = (int)date('n');
$selYear  = isset($_GET['year'])  && ctype_digit($_GET['year'])  ? (int)$_GET['year']  : $curY;
$selMonth = isset($_GET['month']) && ctype_digit($_GET['month']) ? (int)$_GET['month'] : $curM;

$monthStart = sprintf('%04d-%02d-01', $selYear, $selMonth);
$monthEnd   = date('Y-m-t', strtotime($monthStart)); // last day of selected month

/* Allow explicit from/to override (kept for backward compat) */
$from = isset($_GET['from']) && $_GET['from'] !== '' ? $_GET['from'] : $monthStart;
$to   = isset($_GET['to'])   && $_GET['to']   !== '' ? $_GET['to']   : $monthEnd;

/* ---------- Trips query (main table) ---------- */
$where  = [];
$params = [];
$types  = '';

$where[]  = "t.start_date BETWEEN ? AND ?";
$params[] = $from; $params[] = $to; $types .= 'ss';

$sql = "
  SELECT
    t.*,
    v.vehicle_no,
    p.plant_name,
    p.id AS plant_id,
    GROUP_CONCAT(DISTINCT d.name ORDER BY d.name SEPARATOR ', ') AS drivers,
    GROUP_CONCAT(DISTINCT c.customer_name SEPARATOR ', ') AS customers,
    h.name AS helper
  FROM trips t
  JOIN vehicles v ON v.id = t.vehicle_id
  JOIN plants p   ON p.id = v.plant_id
  LEFT JOIN trip_drivers td ON td.trip_id = t.id
  LEFT JOIN drivers d       ON d.id = td.driver_id
  LEFT JOIN trip_customers c ON c.trip_id = t.id
  LEFT JOIN trip_helper th ON th.trip_id = t.id
  LEFT JOIN drivers h      ON h.id = th.helper_id
  " . (count($where) ? (" WHERE " . implode(" AND ", $where)) : "") . "
  GROUP BY t.id
  ORDER BY t.start_date DESC, t.id DESC
";
$stmt = $conn->prepare($sql);
if ($types) $stmt->bind_param($types, ...$params);
$stmt->execute();
$rows = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
$stmt->close();

/* ---------- CSV Export ---------- */
if (isset($_GET['export']) && $_GET['export'] == '1') {
  header('Content-Type: text/csv; charset=utf-8');
  header('Content-Disposition: attachment; filename="trips_'.date('Ymd_His').'.csv"');
  $out = fopen('php://output', 'w');
  fputcsv($out, ['ID','Start Date','End Date','Plant','Vehicle','Drivers','Helper','Customers','Start KM','End KM','Run KM','Status','Note','GPS Lat','GPS Lng']);
  foreach ($rows as $r) {
    $run = ($r['end_km'] !== null && $r['end_km'] !== '') ? (int)$r['end_km'] - (int)$r['start_km'] : '';
    fputcsv($out, [
      $r['id'], $r['start_date'], $r['end_date'],
      $r['plant_name'], $r['vehicle_no'], $r['drivers'],
      ($r['helper'] ?? ''), $r['customers'],
      $r['start_km'], $r['end_km'], $run,
      $r['status'], $r['note'], $r['gps_lat'], $r['gps_lng']
    ]);
  }
  fclose($out); exit;
}

/* ---------- Plants list ---------- */
$plants = [];
$res = $conn->query("SELECT id, plant_name FROM plants ORDER BY plant_name ASC");
while ($res && $row = $res->fetch_assoc()) { $plants[(int)$row['id']] = $row['plant_name']; }

/* ---------- Activity analytics (MTD = selected month), per-plant ---------- */
/* Idle rule: no trip in last 15 days (global last-trip date) */
$idleThreshold = date('Y-m-d', strtotime('-15 days'));

$sqlAgg = "
  WITH person_links AS (
    SELECT td.driver_id AS person_id, td.trip_id FROM trip_drivers td
    UNION ALL
    SELECT th.helper_id AS person_id, th.trip_id FROM trip_helper th
  ),
  person_trips_mtd_plant AS (
    SELECT pl.person_id,
           v.plant_id,
           p.plant_name,
           COUNT(DISTINCT t.id) AS trips_mtd,
           COALESCE(SUM(CASE WHEN t.status='ended' AND t.end_km IS NOT NULL
                             THEN (t.end_km - t.start_km) ELSE 0 END),0) AS km_mtd
    FROM person_links pl
    JOIN trips t ON t.id = pl.trip_id
    JOIN vehicles v ON v.id = t.vehicle_id
    JOIN plants p   ON p.id = v.plant_id
    WHERE t.start_date BETWEEN ? AND ?
    GROUP BY pl.person_id, v.plant_id, p.plant_name
  ),
  last_trip_any AS (
    SELECT person_id, last_trip_date, plant_id, plant_name FROM (
      SELECT pl.person_id,
             t.start_date AS last_trip_date,
             v.plant_id,
             p.plant_name,
             ROW_NUMBER() OVER (PARTITION BY pl.person_id ORDER BY t.start_date DESC) AS rn
      FROM person_links pl
      JOIN trips t ON t.id = pl.trip_id
      JOIN vehicles v ON v.id = t.vehicle_id
      JOIN plants p   ON p.id = v.plant_id
    ) z WHERE rn = 1
  )
  SELECT d.id AS person_id,
         d.name,
         COALESCE(d.role,'driver') AS role,
         m.plant_id,
         m.plant_name,
         COALESCE(m.trips_mtd,0) AS trips_mtd,
         COALESCE(m.km_mtd,0)    AS km_mtd,
         lt.last_trip_date,
         lt.plant_id AS last_trip_plant_id,
         lt.plant_name AS last_trip_plant_name
  FROM drivers d
  LEFT JOIN person_trips_mtd_plant m ON m.person_id = d.id
  LEFT JOIN last_trip_any lt         ON lt.person_id = d.id
  WHERE d.status='Active'
  ORDER BY d.name ASC, m.plant_name ASC
";
$stmt = $conn->prepare($sqlAgg);
$stmt->bind_param('ss', $monthStart, $monthEnd);
$stmt->execute();
$actRows = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
$stmt->close();

/* ---------- Build per-plant Working/Idle buckets ---------- */
$today = date('Y-m-d');
$perPlant = []; // [plant_id] => ['plant_name'=>..., 'working'=>[], 'idle'=>[]]
foreach ($plants as $pid=>$pname) {
  $perPlant[$pid] = ['plant_name'=>$pname, 'working'=>[], 'idle'=>[]];
}

/* To also list people whose last trip belongs to a plant, even if they have 0 MTD there */
$seenForPlant = []; // person_id=>set(plant_id)

foreach ($actRows as $r) {
  $pid = $r['plant_id'] ? (int)$r['plant_id'] : null;

  // If they have MTD stats for a plant, consider them for that plant
  if ($pid !== null && isset($perPlant[$pid])) {
    $last = $r['last_trip_date'] ?: null;
    $isIdle = (!$last || $last < $idleThreshold);
    $row = [
      'id' => (int)$r['person_id'],
      'name' => $r['name'],
      'role' => $r['role'],
      'trips_mtd' => (int)$r['trips_mtd'],
      'km_mtd' => (int)$r['km_mtd'],
      'last_trip_date' => $last,
    ];
    if ($isIdle) $perPlant[$pid]['idle'][] = $row; else $perPlant[$pid]['working'][] = $row;
    $seenForPlant[$r['person_id']][$pid] = true;
  }

  // Also push into the plant of their last trip (so idle shows up in that plant)
  if (!empty($r['last_trip_plant_id'])) {
    $lp = (int)$r['last_trip_plant_id'];
    if (isset($perPlant[$lp]) && empty($seenForPlant[$r['person_id']][$lp])) {
      $last = $r['last_trip_date'] ?: null;
      $isIdle = (!$last || $last < $idleThreshold);
      $row = [
        'id' => (int)$r['person_id'],
        'name' => $r['name'],
        'role' => $r['role'],
        'trips_mtd' => (int)($pid===$lp ? $r['trips_mtd'] : 0), // avoid double counting; if no MTD on this plant, show 0
        'km_mtd' => (int)($pid===$lp ? $r['km_mtd'] : 0),
        'last_trip_date' => $last,
      ];
      if ($isIdle) $perPlant[$lp]['idle'][] = $row; else $perPlant[$lp]['working'][] = $row;
      $seenForPlant[$r['person_id']][$lp] = true;
    }
  }
}

/* ---------- Global star performers (top by trips and km across all plants during selected month) ---------- */
/* ---------- Global star performers (top by trips and km across all plants during selected month) ---------- */
$globalAgg = []; // person_id => ['name','role','trips','km']
foreach ($actRows as $r) {
  if ($r['plant_id'] === null) continue;
  $pid = (int)$r['person_id'];
  if (!isset($globalAgg[$pid])) {
    $globalAgg[$pid] = ['name'=>$r['name'], 'role'=>$r['role'], 'trips'=>0, 'km'=>0];
  }
  $globalAgg[$pid]['trips'] += (int)$r['trips_mtd'];
  $globalAgg[$pid]['km']    += (int)$r['km_mtd'];
}

/* IMPORTANT: materialize to a variable before usort (needed since usort takes by reference) */
$globalAgg = array_values($globalAgg);

/* Top by TRIPS */
$globalTopTrips = $globalAgg; // copy
usort($globalTopTrips, function($a,$b){
  if ($a['trips'] !== $b['trips']) return $b['trips'] - $a['trips'];
  if ($a['km']    !== $b['km'])    return $b['km'] - $a['km'];
  return strcmp($a['name'], $b['name']);
});
$globalTopTrips = array_slice($globalTopTrips, 0, 3);

/* Top by KM */
$globalTopKm = $globalAgg; // copy
usort($globalTopKm, function($a,$b){
  if ($a['km']    !== $b['km'])    return $b['km'] - $a['km'];
  if ($a['trips'] !== $b['trips']) return $b['trips'] - $a['trips'];
  return strcmp($a['name'], $b['name']);
});
$globalTopKm = array_slice($globalTopKm, 0, 3);
/* Helpers */
$monYearStr = date('M Y', strtotime($monthStart));
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Trips Monitor</title>

  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Josefin+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">

  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
  <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">
  <link href="assets/css/custom.css" rel="stylesheet">
  <link rel="icon" href="/images/logo_new.png" type="image/x-icon">

  <style>
    body { background:#f5f6f8; padding-top:56px; font-family: 'Josefin Sans', system-ui, -apple-system, Segoe UI, Roboto, sans-serif; }
    .page-gutter { padding: 10px 12px 0; }
    .main-like { background:#fff; min-height:calc(100vh - 56px); border-left:1px solid rgba(0,0,0,.06); padding-left:.75rem; padding-right:.75rem; }
    @media (min-width:768px){ .main-like { padding-left:1rem; padding-right:1rem; } }

    .shadow-soft { box-shadow:0 6px 20px rgba(0,0,0,.05); }
    .table-responsive { max-height:75vh; overflow:auto; }
    .filter-card { border-radius:14px; }

    .header-blue { background:#cfe2ff; border:1px solid #9ec5fe; }

    /* LIGHT GREEN header */
    .table thead.table-green th {
      background:#d4edda; color:#155724; position:sticky; top:0; z-index:1;
    }

    @keyframes flash { 0%{opacity:1} 50%{opacity:.35} 100%{opacity:1} }
    .badge-flash { animation:flash 1.2s ease-in-out infinite; filter:drop-shadow(0 0 6px rgba(255,193,7,.6)); }

    .sortable { cursor:pointer; user-select:none; }
    .sortable .carat { opacity:.5; font-size:.8em; margin-left:.25rem; }

    .addr { display:block; font-size:.8rem; color:#6c757d; max-width:280px; }
    .map-iframe { width:100%; height:60vh; border:0; }

    .dashboard-card { border-radius:14px; margin-top:1rem; }
    .idle-badge { animation: flash 1.4s ease-in-out infinite; }
    .table-fixed-head thead th { position: sticky; top: 0; background: #d4edda; z-index:1; }

    .star-badge { background: #fff3cd; color:#7a5d00; border:1px solid #ffe69c; }
    .subtle { color:#6c757d; font-weight:600; }
    .plant-chip { font-weight:700; }
  </style>
</head>
<body>
<?php include 'includes/navbar.php'; ?>

<div class="page-gutter">
  <div class="container-fluid">
    <div class="row gx-3">
      <?php include 'includes/sidebar.php'; ?>

      <main class="main-like main col-md-9 ms-sm-auto col-lg-10 px-2">

        <!-- Header bar: Filters + Export + Open TripDetails -->
        <div class="pt-2 pb-2 mb-3 border rounded header-blue">
          <div class="d-flex flex-wrap justify-content-between align-items-center gap-2 px-2">
            <div class="d-flex align-items-center gap-2">
              <i class="fa-solid fa-location-crosshairs"></i>
              <h1 class="h5 mb-0">Trips Monitor</h1>
              <span class="badge text-bg-light ms-2">Month: <?=h($monYearStr)?></span>
            </div>

            <form id="filterForm" class="d-flex flex-wrap align-items-end gap-2" method="get">
              <!-- Month / Year selectors -->
              <div class="input-group input-group-sm" style="width:auto">
                <span class="input-group-text">Month</span>
                <select name="month" id="selMonth" class="form-select">
                  <?php for($m=1;$m<=12;$m++): ?>
                    <option value="<?=$m?>" <?= $m===$selMonth?'selected':'' ?>><?= date('M', mktime(0,0,0,$m,1)) ?></option>
                  <?php endfor; ?>
                </select>
              </div>
              <div class="input-group input-group-sm" style="width:auto">
                <span class="input-group-text">Year</span>
                <select name="year" id="selYear" class="form-select">
                  <?php for($y=$curY-4;$y<=$curY+1;$y++): ?>
                    <option value="<?=$y?>" <?= $y===$selYear?'selected':'' ?>><?=$y?></option>
                  <?php endfor; ?>
                </select>
              </div>

              <!-- Optional explicit From/To override -->
              <div class="input-group input-group-sm" style="width:auto">
                <span class="input-group-text">From</span>
                <input type="date" name="from" id="fromDate" class="form-control" value="<?= h($from) ?>">
              </div>
              <div class="input-group input-group-sm" style="width:auto">
                <span class="input-group-text">To</span>
                <input type="date" name="to" id="toDate" class="form-control" value="<?= h($to) ?>">
              </div>

              <button type="submit" class="btn btn-sm btn-primary">
                <i class="fa-solid fa-magnifying-glass"></i>
              </button>

              <a class="btn btn-sm btn-outline-success"
                 href="?month=<?=$selMonth?>&year=<?=$selYear?>&from=<?=h($from)?>&to=<?=h($to)?>&export=1">
                <i class="fa-solid fa-file-csv"></i> Export CSV
              </a>

              <a class="btn btn-sm btn-warning text-dark"
                 href="https://sstranswaysindia.com/TripDetails/"
                 target="_blank" rel="noopener">
                <i class="fa-solid fa-up-right-from-square me-1"></i> Open TripDetails
              </a>
            </form>
          </div>

          <!-- NOTE: Per your request, the A–Z filter pills have been removed. -->
        </div>

        <!-- Quick search -->
        <div class="card shadow-sm filter-card mb-3">
          <div class="card-body">
            <div class="row g-2 align-items-center">
              <div class="col-12 col-md-6">
                <label class="form-label mb-1">Search (vehicle / plant / driver / customer)</label>
                <div class="input-group">
                  <span class="input-group-text"><i class="fa-solid fa-magnifying-glass"></i></span>
                  <input id="quickSearch" class="form-control" placeholder="Type to filter the table below…">
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Global Star Performers -->
        <div class="row g-3 mb-2">
          <div class="col-lg-6">
            <div class="card shadow-soft">
              <div class="card-body">
                <h4 class="h6 mb-3"><i class="fa-solid fa-star text-warning me-2"></i>Star Performers — Trips (<?=h($monYearStr)?>)</h4>
                <?php if (empty($globalTopTrips)): ?>
                  <div class="text-muted small">No data.</div>
                <?php else: ?>
                  <ol class="mb-0">
                    <?php foreach ($globalTopTrips as $i=>$g): ?>
                      <li class="mb-1">
                        <span class="badge star-badge me-2">#<?=($i+1)?></span>
                        <strong><?=h($g['name'])?></strong>
                        <span class="subtle ms-1">(<?=h(ucfirst($g['role']))?>)</span>
                        <span class="ms-2">Trips: <strong><?=number_format($g['trips'])?></strong></span>
                        <span class="ms-2">KM: <strong><?=number_format($g['km'])?></strong></span>
                      </li>
                    <?php endforeach; ?>
                  </ol>
                <?php endif; ?>
              </div>
            </div>
          </div>
          <div class="col-lg-6">
            <div class="card shadow-soft">
              <div class="card-body">
                <h4 class="h6 mb-3"><i class="fa-solid fa-trophy text-warning me-2"></i>Star Performers — KM (<?=h($monYearStr)?>)</h4>
                <?php if (empty($globalTopKm)): ?>
                  <div class="text-muted small">No data.</div>
                <?php else: ?>
                  <ol class="mb-0">
                    <?php foreach ($globalTopKm as $i=>$g): ?>
                      <li class="mb-1">
                        <span class="badge star-badge me-2">#<?=($i+1)?></span>
                        <strong><?=h($g['name'])?></strong>
                        <span class="subtle ms-1">(<?=h(ucfirst($g['role']))?>)</span>
                        <span class="ms-2">KM: <strong><?=number_format($g['km'])?></strong></span>
                        <span class="ms-2">Trips: <strong><?=number_format($g['trips'])?></strong></span>
                      </li>
                    <?php endforeach; ?>
                  </ol>
                <?php endif; ?>
              </div>
            </div>
          </div>
        </div>

        <!-- Trips table -->
        <div class="card shadow-soft">
          <div class="card-body">
            <div class="table-responsive">
              <table id="tripsTable" class="table table-sm table-bordered table-striped align-middle table-fixed-head">
                <thead class="table-green">
                  <tr>
                    <th class="sortable" data-key="id" data-type="num">ID <span class="carat">↕</span></th>
                    <th class="sortable" data-key="date" data-type="date">Date <span class="carat">↕</span></th>
                    <th class="sortable" data-key="plant" data-type="str">Plant <span class="carat">↕</span></th>
                    <th class="sortable" data-key="vehicle" data-type="str">Vehicle <span class="carat">↕</span></th>
                    <th class="sortable" data-key="drivers" data-type="str">Drivers <span class="carat">↕</span></th>
                    <th class="sortable" data-key="helper" data-type="str">Helper <span class="carat">↕</span></th>
                    <th class="sortable" data-key="customers" data-type="str">Customers <span class="carat">↕</span></th>
                    <th class="text-end sortable" data-key="startkm" data-type="num">Start KM <span class="carat">↕</span></th>
                    <th class="text-end sortable" data-key="endkm" data-type="num">End KM <span class="carat">↕</span></th>
                    <th class="text-end sortable" data-key="runkm" data-type="num">Run KM <span class="carat">↕</span></th>
                    <th class="sortable" data-key="status" data-type="str">Status <span class="carat">↕</span></th>
                    <th>Note</th>
                    <th>GPS</th>
                    <th class="text-end">Actions</th>
                  </tr>
                </thead>
                <tbody id="tbodyTrips">
                  <?php if (empty($rows)): ?>
                    <tr><td colspan="14" class="text-center text-muted">No trips found for selected dates.</td></tr>
                  <?php else: ?>
                    <?php foreach ($rows as $r): ?>
                      <?php
                        $run_km = ($r['end_km'] !== null && $r['end_km'] !== '') ? (int)$r['end_km'] - (int)$r['start_km'] : null;
                        $gps_ok = ($r['gps_lat'] !== null && $r['gps_lat'] !== '' && $r['gps_lng'] !== null && $r['gps_lng'] !== '');
                        $is_ongoing = ($r['status'] === 'ongoing');
                      ?>
                      <tr
                        data-id="<?= (int)$r['id'] ?>"
                        data-date="<?= h($r['start_date']) ?>"
                        data-plant="<?= h($r['plant_name']) ?>"
                        data-vehicle="<?= h($r['vehicle_no']) ?>"
                        data-drivers="<?= h($r['drivers'] ?: '-') ?>"
                        data-customers="<?= h($r['customers'] ?: '-') ?>"
                      >
                        <td><?= (int)$r['id'] ?></td>
                        <td style="white-space:nowrap">
                          <div><?= h(dmy($r['start_date'])) ?></div>
                          <?php if (!empty($r['end_date'])): ?>
                            <div class="text-muted small">End: <?= h(dmy($r['end_date'])) ?></div>
                          <?php endif; ?>
                        </td>
                        <td><?= h($r['plant_name']) ?></td>
                        <td><?= h($r['vehicle_no']) ?></td>
                        <td class="small"><?= h($r['drivers'] ?: '-') ?></td>
                        <td class="small"><?= h($r['helper'] ?? '-') ?></td>
                        <td class="small"><?= h($r['customers'] ?: '-') ?></td>
                        <td class="text-end"><?= h($r['start_km']) ?></td>
                        <td class="text-end"><?= $r['end_km'] !== null && $r['end_km'] !== '' ? h($r['end_km']) : '-' ?></td>
                        <td class="text-end"><?= $run_km !== null ? number_format($run_km) : '-' ?></td>
                        <td>
                          <?php if ($is_ongoing): ?>
                            <span class="badge bg-warning text-dark badge-flash">Ongoing</span>
                          <?php else: ?>
                            <span class="badge bg-success">Ended</span>
                          <?php endif; ?>
                        </td>
                        <td class="small"><?= nl2br(h($r['note'] ?? '')) ?></td>
                        <td class="small" style="white-space:nowrap">
                          <?php if ($gps_ok): ?>
                            <a href="#"
                               class="gps-link"
                               data-lat="<?= h($r['gps_lat']) ?>"
                               data-lng="<?= h($r['gps_lng']) ?>"
                               title="Preview on map">
                               <?= h($r['gps_lat']) ?>, <?= h($r['gps_lng']) ?>
                            </a>
                            <small class="addr" id="addr-<?= (int)$r['id'] ?>">Resolving address…</small>
                          <?php else: ?>
                            <span class="badge text-bg-secondary">Not available</span>
                          <?php endif; ?>
                        </td>
                        <td class="text-end" style="white-space:nowrap">
                          <?php if ($is_ongoing): ?>
                            <button
                              class="btn btn-sm btn-outline-success end-btn me-1"
                              data-id="<?= (int)$r['id'] ?>"
                              data-startkm="<?= (int)$r['start_km'] ?>">
                              End Trip
                            </button>
                          <?php endif; ?>
                          <button class="btn btn-sm btn-outline-danger del-btn" data-id="<?= (int)$r['id'] ?>">
                            Delete
                          </button>
                        </td>
                      </tr>
                    <?php endforeach; ?>
                  <?php endif; ?>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <!-- Plant-wise Working / Idle -->
        <?php foreach ($perPlant as $pid => $bucket): ?>
          <?php
            $wk = $bucket['working'];
            $id = $bucket['idle'];
            // Per-plant star performers (top 2 by trips, then km)
            $rank = $wk;
            usort($rank, function($a,$b){
              if ($a['trips_mtd'] !== $b['trips_mtd']) return $b['trips_mtd'] - $a['trips_mtd'];
              if ($a['km_mtd'] !== $b['km_mtd']) return $b['km_mtd'] - $a['km_mtd'];
              return strcmp($a['name'],$b['name']);
            });
            $plantTop = array_slice($rank, 0, 2);
          ?>
          <div class="row g-3 mt-3">
            <div class="col-12">
              <h3 class="h6 mb-2">
                <span class="badge text-bg-primary plant-chip me-2"><?=h($bucket['plant_name'])?></span>
                <span class="text-muted">Month: <?=h($monYearStr)?></span>
              </h3>
              <?php if (!empty($plantTop)): ?>
                <div class="small mb-2">
                  <?php foreach ($plantTop as $i=>$p): ?>
                    <span class="badge star-badge me-2">
                      <i class="fa-solid fa-star me-1"></i>
                      <?=h($p['name'])?> — Trips: <?=number_format($p['trips_mtd'])?>, KM: <?=number_format($p['km_mtd'])?>
                    </span>
                  <?php endforeach; ?>
                </div>
              <?php endif; ?>
            </div>

            <div class="col-lg-6">
              <div class="card shadow-soft dashboard-card">
                <div class="card-body">
                  <h4 class="h6 mb-3">
                    <i class="fa-solid fa-user-check me-2"></i>Working — <?=h($monYearStr)?>
                  </h4>
                  <div class="table-responsive">
                    <table class="table table-sm table-bordered align-middle table-fixed-head">
                      <thead class="table-green">
                        <tr>
                          <th style="min-width:220px;">Name</th>
                          <th>Role</th>
                          <th class="text-end">Trips (MTD)</th>
                          <th class="text-end">KM (MTD)</th>
                          <th>Last Trip</th>
                          <th class="text-end">Days Idle</th>
                        </tr>
                      </thead>
                      <tbody>
                        <?php if (empty($wk)): ?>
                          <tr><td colspan="6" class="text-center text-muted">No working drivers/helpers.</td></tr>
                        <?php else: ?>
                          <?php foreach ($wk as $row): ?>
                            <?php $daysIdle = $row['last_trip_date'] ? days_between($row['last_trip_date'], $today) : null; ?>
                            <tr>
                              <td>
                                <?php
                                  // star if in plantTop
                                  $isStar = false;
                                  foreach ($plantTop as $pt) { if ($pt['id'] === $row['id']) { $isStar = true; break; } }
                                ?>
                                <?php if ($isStar): ?><span class="badge star-badge me-2">Star</span><?php endif; ?>
                                <?=h($row['name'])?>
                              </td>
                              <td><?=h(ucfirst($row['role']))?></td>
                              <td class="text-end"><?=number_format((int)$row['trips_mtd'])?></td>
                              <td class="text-end"><?=number_format((int)$row['km_mtd'])?></td>
                              <td><?= $row['last_trip_date'] ? h(dmy($row['last_trip_date'])) : '<span class="text-muted">—</span>' ?></td>
                              <td class="text-end"><?= $daysIdle !== null ? number_format($daysIdle) : '—' ?></td>
                            </tr>
                          <?php endforeach; ?>
                        <?php endif; ?>
                      </tbody>
                    </table>
                  </div>
                  <div class="small text-muted">
                    Trips/KM counted when the person appears as Driver or Helper (KM only from ended trips).
                  </div>
                </div>
              </div>
            </div>

            <div class="col-lg-6">
              <div class="card shadow-soft dashboard-card">
                <div class="card-body">
                  <h4 class="h6 mb-3">
                    <i class="fa-solid fa-user-clock me-2"></i>Idle — no trip in last 15 days
                    <span class="badge text-bg-light ms-2"><?=h($monYearStr)?></span>
                  </h4>
                  <div class="table-responsive">
                    <table class="table table-sm table-bordered align-middle table-fixed-head">
                      <thead class="table-green">
                        <tr>
                          <th style="min-width:220px;">Name</th>
                          <th>Role</th>
                          <th class="text-end">Trips (MTD)</th>
                          <th class="text-end">KM (MTD)</th>
                          <th>Last Trip</th>
                          <th class="text-end">Days Idle</th>
                        </tr>
                      </thead>
                      <tbody>
                        <?php if (empty($id)): ?>
                          <tr><td colspan="6" class="text-center text-muted">No idle drivers/helpers 🎉</td></tr>
                        <?php else: ?>
                          <?php foreach ($id as $row): ?>
                            <?php $daysIdle = $row['last_trip_date'] ? days_between($row['last_trip_date'], $today) : days_between('1900-01-01', $today); ?>
                            <tr>
                              <td><span class="badge text-bg-danger idle-badge me-2">IDLE</span><?=h($row['name'])?></td>
                              <td><?=h(ucfirst($row['role']))?></td>
                              <td class="text-end"><?=number_format((int)$row['trips_mtd'])?></td>
                              <td class="text-end"><?=number_format((int)$row['km_mtd'])?></td>
                              <td><?= $row['last_trip_date'] ? h(dmy($row['last_trip_date'])) : '<span class="text-muted">—</span>' ?></td>
                              <td class="text-end"><?= number_format((int)$daysIdle) ?></td>
                            </tr>
                          <?php endforeach; ?>
                        <?php endif; ?>
                      </tbody>
                    </table>
                  </div>
                  <div class="small text-muted">
                    Idle cut-off date: <?=h(date('d M Y', strtotime($idleThreshold)))?>.
                  </div>
                </div>
              </div>
            </div>
          </div>
        <?php endforeach; ?>

      </main>
    </div>
  </div>
</div>

<!-- End Trip Modal -->
<div class="modal fade" id="endTripModal" tabindex="-1" aria-hidden="true">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title"><i class="fa-solid fa-flag-checkered me-2"></i>End Trip</h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <div class="modal-body">
        <input type="hidden" id="endTripId"/>
        <div class="row g-3">
          <div class="col-6">
            <label class="form-label">Trip End Date</label>
            <input id="endDate" type="date" class="form-control"/>
          </div>
          <div class="col-6">
            <label class="form-label">Trip End KM</label>
            <input id="endKm" type="number" class="form-control" min="0" inputmode="numeric"/>
          </div>
          <div class="col-12">
            <div class="form-text" id="computedRun"></div>
          </div>
        </div>
      </div>
      <div class="modal-footer">
        <button class="btn btn-outline-secondary" data-bs-dismiss="modal">Cancel</button>
        <button id="saveEndTrip" class="btn btn-success">Save</button>
      </div>
    </div>
  </div>
</div>

<!-- GPS Preview Modal -->
<div class="modal fade" id="gpsModal" tabindex="-1" aria-hidden="true">
  <div class="modal-dialog modal-lg modal-dialog-centered">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title"><i class="fa-solid fa-map-location-dot me-2"></i>GPS Preview</h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <div class="modal-body p-0">
        <iframe id="gpsMap" class="map-iframe" loading="lazy" referrerpolicy="no-referrer-when-downgrade"></iframe>
      </div>
      <div class="modal-footer">
        <a id="gpsOpenNew" href="#" target="_blank" class="btn btn-primary">
          <i class="fa-solid fa-up-right-from-square"></i> Open in Google Maps
        </a>
      </div>
    </div>
  </div>
</div>

<!-- Toasts -->
<div id="toastContainer" class="toast-container position-fixed top-0 start-50 translate-middle-x p-3" style="z-index:11000;"></div>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
<script>
  function showToast(message, variant='info', delay=3000){
    const id = 't' + Date.now();
    document.getElementById('toastContainer').insertAdjacentHTML('beforeend', `
      <div id="${id}" class="toast align-items-center text-bg-${variant} border-0 mb-2" role="status" aria-live="polite" aria-atomic="true">
        <div class="d-flex">
          <div class="toast-body fw-semibold">${message}</div>
          <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast" aria-label="Close"></button>
        </div>
      </div>
    `);
    const el = document.getElementById(id);
    const toast = new bootstrap.Toast(el, { delay });
    toast.show();
    el.addEventListener('hidden.bs.toast', ()=> el.remove());
  }

  /* ===== Month/Year -> auto-sync From/To ===== */
  (function syncMonthYearInit(){
    const selMonth = document.getElementById('selMonth');
    const selYear  = document.getElementById('selYear');
    const fromInp  = document.getElementById('fromDate');
    const toInp    = document.getElementById('toDate');
    function pad(n){ return String(n).padStart(2,'0'); }
    function sync(){
      const m = parseInt(selMonth.value || '1', 10);
      const y = parseInt(selYear.value  || new Date().getFullYear(), 10);
      const first = new Date(y, m-1, 1);
      const last  = new Date(y, m, 0);
      fromInp.value = `${first.getFullYear()}-${pad(first.getMonth()+1)}-${pad(1)}`;
      toInp.value   = `${last.getFullYear()}-${pad(last.getMonth()+1)}-${pad(last.getDate())}`;
    }
    selMonth?.addEventListener('change', sync);
    selYear?.addEventListener('change', sync);
  })();

  /* ========= End Trip ========= */
  let startKmForModal = 0;
  function openEndModal(tripId, startKm){
    document.getElementById('endTripId').value = tripId;
    document.getElementById('endDate').value = new Date().toISOString().split('T')[0];
    document.getElementById('endKm').value = '';
    document.getElementById('computedRun').textContent = `Start KM: ${startKm}`;
    startKmForModal = Number(startKm || 0);
    const modal = new bootstrap.Modal(document.getElementById('endTripModal'));
    modal.show();

    const endKmInp = document.getElementById('endKm');
    endKmInp.oninput = () => {
      const ek = Number(endKmInp.value || 0);
      const run = ek - startKmForModal;
      document.getElementById('computedRun').textContent = run >= 0
        ? `Start KM: ${startKmForModal} → End KM: ${ek} → Total: ${run} KM`
        : `End KM must be ≥ Start KM (${startKmForModal})`;
    };
  }

  // Save End Trip
  document.getElementById('saveEndTrip').addEventListener('click', async () => {
    const id       = Number(document.getElementById('endTripId').value || 0);
    const end_date = (document.getElementById('endDate').value || '').trim(); // yyyy-mm-dd
    const end_km   = Number(document.getElementById('endKm').value || 0);

    if (!id)           return showToast('Invalid trip id','danger');
    if (!end_date)     return showToast('Enter end date','warning');
    if (!end_km && end_km !== 0) return showToast('Enter end KM','warning');

    if (!isNaN(startKmForModal) && end_km < startKmForModal) {
      return showToast(`End KM (${end_km}) must be ≥ Start KM (${startKmForModal})`, 'danger', 5000);
    }

    const body = 'trip_id='   + encodeURIComponent(String(id)) +
                 '&end_date=' + encodeURIComponent(end_date)   +
                 '&end_km='   + encodeURIComponent(String(end_km));

    try {
      const res = await fetch('/TripDetails/api/trips_end.php?cb=' + Date.now(), {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Accept':'application/json' },
        body
      });

      const text = await res.text();
      let data = null; try { data = JSON.parse(text); } catch(_){}
      if (!data || !res.ok || data.ok !== true) {
        const msg = (data && (data.error || data.message)) || (text || '').slice(0,200) || `HTTP ${res.status}`;
        return showToast('Failed to end trip: ' + msg, 'danger', 6500);
      }

      // close modal
      bootstrap.Modal.getInstance(document.getElementById('endTripModal'))?.hide();

      // inline row update
      const tr = document.querySelector(`tr[data-id="${id}"]`);
      if (tr) {
        // End date
        const endDateFmt = end_date.split('-').reverse().join('-'); // d-m-Y
        const dateTd = tr.children[1];
        if (dateTd) {
          const small = dateTd.querySelector('.text-muted.small');
          if (small) small.textContent = 'End: ' + endDateFmt;
          else dateTd.insertAdjacentHTML('beforeend', `<div class="text-muted small">End: ${endDateFmt}</div>`);
        }

        // End KM + Run KM
        const startKm = Number((tr.children[7]?.textContent || '0').replace(/[^0-9]/g,''));
        const runKm = Math.max(0, end_km - (isNaN(startKm) ? 0 : startKm));
        if (tr.children[8]) tr.children[8].textContent = end_km.toLocaleString('en-IN');
        if (tr.children[9]) tr.children[9].textContent = runKm ? runKm.toLocaleString('en-IN') : '0';

        // Status
        const stTd = tr.children[10];
        if (stTd) stTd.innerHTML = '<span class="badge bg-success">Ended</span>';

        // remove end button
        tr.querySelector('.end-btn')?.remove();
      }

      showToast('Trip ended.','success');
    } catch (err) {
      showToast('Network/JS error while ending trip: ' + (err?.message || err), 'danger', 6500);
    }
  });

  /* ========= Delegated clicks: End, GPS, Delete ========= */
  document.addEventListener('click', (e)=>{
    const endBtn = e.target.closest('.end-btn');
    if (endBtn){ openEndModal(endBtn.dataset.id, endBtn.dataset.startkm); }

    const gpsA = e.target.closest('.gps-link');
    if (gpsA){
      e.preventDefault();
      const lat = gpsA.dataset.lat, lng = gpsA.dataset.lng;
      const q = encodeURIComponent(`${lat},${lng}`);
      const iframe = document.getElementById('gpsMap');
      iframe.src = `https://maps.google.com/maps?q=${q}&z=14&output=embed`;
      const openNew = document.getElementById('gpsOpenNew');
      openNew.href = `https://maps.google.com/?q=${q}`;
      const modal = new bootstrap.Modal(document.getElementById('gpsModal'));
      modal.show();
    }

    const delBtn = e.target.closest('.del-btn');
    if (delBtn){
      const id = Number(delBtn.dataset.id);
      if (!confirm('Delete this trip?')) return;
      fetch('/TripDetails/api/trips_delete.php', {
        method:'POST',
        credentials:'include',
        headers:{'Content-Type':'application/json','Accept':'application/json'},
        body: JSON.stringify({ trip_id:id })
      })
      .then(r=>r.text())
      .then(txt=>{
        let data=null; try{ data=JSON.parse(txt);}catch(_){}
        if(!data || !data.ok){ showToast((data && (data.error||data.message)) || (txt||'Delete failed'), 'danger'); return; }
        showToast('Trip deleted','success');
        document.querySelector(`tr[data-id="${id}"]`)?.remove();
      })
      .catch(()=> showToast('Network error while deleting','danger'));
    }
  });

  /* ========= Client search & sorting ========= */
  const quickSearch = document.getElementById('quickSearch');
  const table = document.getElementById('tripsTable');
  let sortState = {};

  function getCellVal(tr, key){
    switch(key){
      case 'id':      return Number(tr.children[0].textContent.trim() || '0');
      case 'date':    return tr.getAttribute('data-date') || '';
      case 'plant':   return (tr.getAttribute('data-plant')||'').toLowerCase();
      case 'vehicle': return (tr.getAttribute('data-vehicle')||'').toLowerCase();
      case 'drivers': return (tr.getAttribute('data-drivers')||'').toLowerCase();
      case 'helper':  return (tr.children[5].textContent||'').toLowerCase();
      case 'customers': return (tr.getAttribute('data-customers')||'').toLowerCase();
      case 'startkm': return Number(tr.children[7].textContent.replace(/,/g,'')||'0');
      case 'endkm':   return Number((tr.children[8].textContent||'').replace(/[^0-9]/g,'')||'0');
      case 'runkm':   return Number((tr.children[9].textContent||'').replace(/,/g,'')||'0');
      case 'status':  return (tr.children[10].textContent||'').toLowerCase();
      default:        return (tr.children[0].textContent||'').toLowerCase();
    }
  }

  table.querySelectorAll('th.sortable').forEach(th=>{
    th.addEventListener('click', ()=>{
      const key = th.dataset.key;
      const type = th.dataset.type || 'str';
      sortState[key] = (sortState[key] === 'asc') ? 'desc' : 'asc';

      const tbody = document.getElementById('tbodyTrips');
      const trs = Array.from(tbody.querySelectorAll('tr'));
      trs.sort((a,b)=>{
        const av = getCellVal(a,key);
        const bv = getCellVal(b,key);
        if (type === 'num'){
          return sortState[key] === 'asc' ? (av - bv) : (bv - av);
        } else if (type === 'date'){
          if (av === bv) return 0;
          return sortState[key] === 'asc' ? (av > bv ? 1 : -1) : (av > bv ? -1 : 1);
        } else {
          return sortState[key] === 'asc' ? av.localeCompare(bv) : bv.localeCompare(av);
        }
      });
      trs.forEach(tr=>tbody.appendChild(tr));
      table.querySelectorAll('.carat').forEach(c=>c.textContent='↕');
      th.querySelector('.carat').textContent = (sortState[key] === 'asc') ? '↑' : '↓';
    });
  });

  function runFilters(){
    const q = (quickSearch.value || '').trim().toLowerCase();
    document.querySelectorAll('#tbodyTrips tr').forEach(tr=>{
      const hay = [
        tr.dataset.vehicle || '',
        tr.dataset.plant || '',
        tr.dataset.drivers || '',
        tr.dataset.customers || ''
      ].join(' ').toLowerCase();
      tr.style.display = hay.includes(q) ? '' : 'none';
    });
  }
  quickSearch.addEventListener('input', runFilters);
  runFilters();

  /* ========= Reverse geocode (OSM Nominatim) ========= */
  const addrSpans = Array.from(document.querySelectorAll('.addr[id^="addr-"]'));
  const toFetch = addrSpans.map(sp=>{
    const tr = sp.closest('tr');
    return { el: sp, lat: tr.querySelector('.gps-link')?.dataset.lat, lng: tr.querySelector('.gps-link')?.dataset.lng };
  }).filter(x=>x.lat && x.lng);

  async function fetchAddr(item){
    const url = `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${encodeURIComponent(item.lat)}&lon=${encodeURIComponent(item.lng)}&zoom=14&addressdetails=1`;
    try{
      const res = await fetch(url, { headers:{ 'Accept':'application/json' }});
      if(!res.ok) throw new Error('HTTP '+res.status);
      const j = await res.json();
      item.el.textContent = j.display_name || 'Address not available';
    }catch(e){
      item.el.textContent = 'Address not available';
    }
  }
  (async ()=>{
    for (const it of toFetch){
      await fetchAddr(it);
      await new Promise(r=>setTimeout(r, 800));
    }
  })();
</script>
</body>
</html>