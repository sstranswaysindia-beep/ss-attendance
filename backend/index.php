<?php
// index.php — Dashboard (Drivers, Vehicles, Maintenance, Approvals)

// Debug (remove in prod)
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

// Auth
if (session_status() === PHP_SESSION_NONE) session_start();
require __DIR__ . '/../includes/auth.php';
checkRole(['admin','supervisor']);

// DB
require __DIR__ . '/../../conf/config.php';
if (!isset($conn) || !($conn instanceof mysqli)) {
  die("Database connection (\$conn) not available");
}

/* ---- Sidebar active marker so includes/sidebar.php highlights Dashboard ---- */
$ACTIVE_MENU = 'dashboard';

/* ---------------- Settings ---------------- */
function get_int_setting(mysqli $conn, string $key, int $fallback): int {
  try {
    $stmt = $conn->prepare("SELECT setting_value FROM system_settings WHERE setting_key = ? LIMIT 1");
    $stmt->bind_param('s', $key);
    $stmt->execute();
    $val = $stmt->get_result()->fetch_column();
    $stmt->close();
    $n = (int)$val;
    return $n > 0 ? $n : $fallback;
  } catch (Throwable $e) {
    return $fallback;
  }
}
$WARNING_DAYS = get_int_setting($conn, 'warning_days', 30);
$KM_SOON      = get_int_setting($conn, 'maintenance_km_warn', 1000);

/* -------- Small helpers -------- */
function pct($num, $den) { return ($den > 0) ? round(($num / $den) * 100) : 0; }
function h($s) { return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); }

/* SVG donut ring */
function svg_donut($percent, $size = 96, $stroke = 10, $color = '#0d6efd') {
  $r = ($size - $stroke) / 2;
  $c = 2 * M_PI * $r;
  $dash = max(0, min($c, ($percent / 100) * $c));
  $bg = '#e9ecef';
  return '
  <svg width="'.$size.'" height="'.$size.'" viewBox="0 0 '.$size.' '.$size.'">
    <circle cx="'.($size/2).'" cy="'.($size/2).'" r="'.$r.'" fill="none" stroke="'.$bg.'" stroke-width="'.$stroke.'"/>
    <circle cx="'.($size/2).'" cy="'.($size/2).'" r="'.$r.'" fill="none"
            stroke="'.$color.'" stroke-width="'.$stroke.'"
            stroke-dasharray="'.$dash.' '.($c-$dash).'"
            stroke-linecap="round" transform="rotate(-90 '.($size/2).' '.($size/2).')"/>
    <text x="50%" y="50%" dominant-baseline="middle" text-anchor="middle"
          style="font:600 16px Josefin Sans, sans-serif; fill:#212529">'.$percent.'%</text>
  </svg>';
}
function driver_label($emp_id, $name) {
  $emp = trim((string)$emp_id);
  $nm  = trim((string)$name);
  return $emp !== '' ? ($emp . ' - ' . $nm) : $nm;
}

/* ---------------- Data: Drivers ---------------- */
$drv = [
  'total_subjects'=>0,'total_docs'=>0,'expiring'=>0,'expired'=>0,'recent_uploads'=>0,
  'recent_activity'=>[],'upcoming_expiries'=>[],'expired_list'=>[]
];

$drv['total_subjects'] = (int)($conn->query("SELECT COUNT(*) FROM drivers WHERE status='Active'")->fetch_column() ?? 0);
$drv['total_docs']     = (int)($conn->query("SELECT COUNT(*) FROM driver_documents WHERE is_active=1")->fetch_column() ?? 0);

/* counts */
$stmt = $conn->prepare("
  SELECT COUNT(*) FROM driver_documents
  WHERE is_active=1 AND expiry_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL ? DAY)
");
$stmt->bind_param('i', $WARNING_DAYS);
$stmt->execute(); $drv['expiring'] = (int)$stmt->get_result()->fetch_column(); $stmt->close();

$stmt = $conn->prepare("SELECT COUNT(*) FROM driver_documents WHERE is_active=1 AND expiry_date < CURDATE()");
$stmt->execute(); $drv['expired'] = (int)$stmt->get_result()->fetch_column(); $stmt->close();

$stmt = $conn->prepare("
  SELECT COUNT(*) FROM driver_documents
  WHERE is_active=1 AND upload_date >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
");
$stmt->execute(); $drv['recent_uploads'] = (int)$stmt->get_result()->fetch_column(); $stmt->close();

/* lists */
$stmt = $conn->prepare("
  SELECT
    dd.upload_date AS when_at,
    dd.document_name AS doc_name,
    dd.document_type AS doc_type,
    d.name,
    d.empid AS emp_id
  FROM driver_documents dd
  JOIN drivers d ON d.id = dd.driver_id
  WHERE dd.is_active = 1
  ORDER BY dd.upload_date DESC
  LIMIT 10
");
$stmt->execute(); $drv['recent_activity'] = $stmt->get_result()->fetch_all(MYSQLI_ASSOC); $stmt->close();

$stmt = $conn->prepare("
  SELECT
    dd.expiry_date AS expiry_at,
    DATEDIFF(dd.expiry_date, CURDATE()) AS days_to_expiry,
    dd.document_name AS doc_name,
    dd.document_type AS doc_type,
    d.name,
    d.empid AS emp_id
  FROM driver_documents dd
  JOIN drivers d ON d.id = dd.driver_id
  WHERE dd.is_active=1
    AND dd.expiry_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL ? DAY)
  ORDER BY dd.expiry_date ASC
  LIMIT 12
");
$stmt->bind_param('i', $WARNING_DAYS);
$stmt->execute(); $drv['upcoming_expiries'] = $stmt->get_result()->fetch_all(MYSQLI_ASSOC); $stmt->close();

/* expired list */
$stmt = $conn->prepare("
  SELECT
    dd.expiry_date AS expired_at,
    dd.document_name AS doc_name,
    dd.document_type AS doc_type,
    d.name,
    d.empid AS emp_id
  FROM driver_documents dd
  JOIN drivers d ON d.id = dd.driver_id
  WHERE dd.is_active=1 AND dd.expiry_date < CURDATE()
  ORDER BY dd.expiry_date ASC
  LIMIT 20
");
$stmt->execute(); $drv['expired_list'] = $stmt->get_result()->fetch_all(MYSQLI_ASSOC); $stmt->close();

/* ---------------- Data: Vehicles ---------------- */
$veh = [
  'total_subjects'=>0,'total_docs'=>0,'expiring'=>0,'expired'=>0,'recent_uploads'=>0,
  'recent_activity'=>[],'upcoming_expiries'=>[],'expired_list'=>[]
];

$veh['total_subjects'] = (int)($conn->query("SELECT COUNT(*) FROM vehicles")->fetch_column() ?? 0);
$veh['total_docs']     = (int)($conn->query("SELECT COUNT(*) FROM vehicle_documents WHERE is_active=1")->fetch_column() ?? 0);

/* counts — exclude registration from expiry math */
$stmt = $conn->prepare("
  SELECT COUNT(*) FROM vehicle_documents
  WHERE is_active=1
    AND document_type <> 'registration'
    AND expiry_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL ? DAY)
");
$stmt->bind_param('i', $WARNING_DAYS);
$stmt->execute(); $veh['expiring'] = (int)$stmt->get_result()->fetch_column(); $stmt->close();

$stmt = $conn->prepare("
  SELECT COUNT(*) FROM vehicle_documents
  WHERE is_active=1
    AND document_type <> 'registration'
    AND expiry_date < CURDATE()
");
$stmt->execute(); $veh['expired'] = (int)$stmt->get_result()->fetch_column(); $stmt->close();

$stmt = $conn->prepare("
  SELECT COUNT(*) FROM vehicle_documents
  WHERE is_active=1 AND upload_date >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
");
$stmt->execute(); $veh['recent_uploads'] = (int)$stmt->get_result()->fetch_column(); $stmt->close();

/* lists — exclude registration from expiry lists */
$stmt = $conn->prepare("
  SELECT vd.expiry_date AS expiry_at, DATEDIFF(vd.expiry_date, CURDATE()) AS days_to_expiry,
         vd.document_name AS doc_name, vd.document_type AS doc_type, v.vehicle_no AS subject_label
  FROM vehicle_documents vd
  JOIN vehicles v ON v.id = vd.vehicle_id
  WHERE vd.is_active=1
    AND vd.document_type <> 'registration'
    AND vd.expiry_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL ? DAY)
  ORDER BY vd.expiry_date ASC
  LIMIT 12
");
$stmt->bind_param('i', $WARNING_DAYS);
$stmt->execute(); $veh['upcoming_expiries'] = $stmt->get_result()->fetch_all(MYSQLI_ASSOC); $stmt->close();

$stmt = $conn->prepare("
  SELECT vd.expiry_date AS expired_at,
         vd.document_name AS doc_name, vd.document_type AS doc_type, v.vehicle_no AS subject_label
  FROM vehicle_documents vd
  JOIN vehicles v ON v.id = vd.vehicle_id
  WHERE vd.is_active=1
    AND vd.document_type <> 'registration'
    AND vd.expiry_date < CURDATE()
  ORDER BY vd.expiry_date ASC
  LIMIT 20
");
$stmt->execute(); $veh['expired_list'] = $stmt->get_result()->fetch_all(MYSQLI_ASSOC); $stmt->close();

/* Percentages for donuts */
$drv_pct_expiring = pct($drv['expiring'], $drv['total_docs']);
$drv_pct_expired  = pct($drv['expired'],  max(1, $drv['total_docs']));
$veh_pct_expiring = pct($veh['expiring'], $veh['total_docs']);
$veh_pct_expired  = pct($veh['expired'],  max(1, $veh['total_docs']));

/* ---------------- Data: Maintenance ---------------- */
$mnt = [
  'total_vehicles'=>0,
  'due_soon'=>0,
  'overdue'=>0,
  'recent_updates'=>0,
  'recent_activity'=>[],
  'due_list'=>[],
  'overdue_list'=>[]
];

$mnt['total_vehicles'] = (int)($conn->query("SELECT COUNT(*) FROM vehicles")->fetch_column() ?? 0);

$baseSQL = "
  SELECT v.id AS vehicle_id, v.vehicle_no,
         'Oil Service' AS kind,
         vm.oil_next_date AS next_date,
         DATEDIFF(vm.oil_next_date, CURDATE()) AS days_to_next,
         vm.next_oil_service_km AS next_km,
         vm.current_km AS current_km,
         (vm.next_oil_service_km - vm.current_km) AS km_remaining
  FROM vehicles v
  JOIN vehicle_maintenance vm ON vm.vehicle_id = v.id
  UNION ALL
  SELECT v.id, v.vehicle_no,
         'Hub Greasing',
         vm.hub_next_date,
         DATEDIFF(vm.hub_next_date, CURDATE()),
         vm.next_hub_greasing_km,
         vm.current_km,
         (vm.next_hub_greasing_km - vm.current_km)
  FROM vehicles v
  JOIN vehicle_maintenance vm ON vm.vehicle_id = v.id
  UNION ALL
  SELECT v.id, v.vehicle_no,
         'RA Oil',
         vm.ra_next_date,
         DATEDIFF(vm.ra_next_date, CURDATE()),
         vm.next_ra_oil_km,
         vm.current_km,
         (vm.next_ra_oil_km - vm.current_km)
  FROM vehicles v
  JOIN vehicle_maintenance vm ON vm.vehicle_id = v.id
  UNION ALL
  SELECT v.id, v.vehicle_no,
         'Gear Box Oil',
         vm.gear_next_date,
         DATEDIFF(vm.gear_next_date, CURDATE()),
         vm.next_gear_oil_km,
         vm.current_km,
         (vm.next_gear_oil_km - vm.current_km)
  FROM vehicles v
  JOIN vehicle_maintenance vm ON vm.vehicle_id = v.id
";

/* Count due soon */
$stmt = $conn->prepare("
  SELECT COUNT(*) FROM (
    $baseSQL
  ) t
  WHERE
    (
      (t.next_date IS NOT NULL AND t.next_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL ? DAY))
      OR
      (t.next_km IS NOT NULL AND t.current_km IS NOT NULL AND (t.next_km - t.current_km) <= ?)
    )
");
$stmt->bind_param('ii', $WARNING_DAYS, $KM_SOON);
$stmt->execute(); $mnt['due_soon'] = (int)$stmt->get_result()->fetch_column(); $stmt->close();

/* Count overdue */
$stmt = $conn->prepare("
  SELECT COUNT(*) FROM (
    $baseSQL
  ) t
  WHERE
    (
      (t.next_date IS NOT NULL AND t.next_date < CURDATE())
      OR
      (t.next_km IS NOT NULL AND t.current_km IS NOT NULL AND (t.next_km - t.current_km) <= 0)
    )
");
$stmt->execute(); $mnt['overdue'] = (int)$stmt->get_result()->fetch_column(); $stmt->close();

/* Recent activity: vehicle_maintenance updated in last 7 days */
$stmt = $conn->prepare("
  SELECT v.vehicle_no AS subject_label, vm.updated_at AS when_at
  FROM vehicle_maintenance vm
  JOIN vehicles v ON v.id = vm.vehicle_id
  WHERE vm.updated_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
  ORDER BY vm.updated_at DESC
  LIMIT 10
");
$stmt->execute(); $mnt['recent_activity'] = $stmt->get_result()->fetch_all(MYSQLI_ASSOC); $stmt->close();

$stmt = $conn->prepare("
  SELECT COUNT(*) FROM vehicle_maintenance
  WHERE updated_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
");
$stmt->execute(); $mnt['recent_updates'] = (int)$stmt->get_result()->fetch_column(); $stmt->close();

/* Due soon list (limit 12) */
$stmt = $conn->prepare("
  SELECT * FROM (
    $baseSQL
  ) t
  WHERE
    (
      (t.next_date IS NOT NULL AND t.next_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL ? DAY))
      OR
      (t.next_km IS NOT NULL AND t.current_km IS NOT NULL AND (t.next_km - t.current_km) <= ?)
    )
  ORDER BY
    LEAST(
      IF(t.next_date IS NULL, 999999, DATEDIFF(t.next_date, CURDATE())),
      IF(t.next_km IS NULL OR t.current_km IS NULL, 999999, (t.next_km - t.current_km))
    ) ASC
  LIMIT 12
");
$stmt->bind_param('ii', $WARNING_DAYS, $KM_SOON);
$stmt->execute(); $mnt['due_list'] = $stmt->get_result()->fetch_all(MYSQLI_ASSOC); $stmt->close();

/* Overdue list (limit 20) */
$stmt = $conn->prepare("
  SELECT * FROM (
    $baseSQL
  ) t
  WHERE
    (
      (t.next_date IS NOT NULL AND t.next_date < CURDATE())
      OR
      (t.next_km IS NOT NULL AND t.current_km IS NOT NULL AND (t.next_km - t.current_km) <= 0)
    )
  ORDER BY
    GREATEST(
      IF(t.next_date IS NULL, -999999, -DATEDIFF(CURDATE(), t.next_date)),
      IF(t.next_km IS NULL OR t.current_km IS NULL, -999999, -(t.current_km - t.next_km))
    ) DESC
  LIMIT 20
");
$stmt->execute(); $mnt['overdue_list'] = $stmt->get_result()->fetch_all(MYSQLI_ASSOC); $stmt->close();

/* Percentages for donuts (Maintenance) */
$mnt_total_items = max(1, $mnt['total_vehicles'] * 4);
$mnt_pct_due     = pct($mnt['due_soon'],  $mnt_total_items);
$mnt_pct_overdue = pct($mnt['overdue'],   $mnt_total_items);
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Dashboard — Drivers, Vehicles, Maintenance, Approvals</title>

  <!-- Fonts / CSS -->
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Josefin+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">

  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
  <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">

  <!-- Your site styles (sidebar rules live here) -->
  <link href="assets/css/custom.css" rel="stylesheet">

  <link rel="icon" href="/images/logo_new.png" type="image/x-icon">

  <!-- Scoped layout fixes -->
  <style>
    body { background:#f5f6f8; padding-top:56px; font-family: 'Josefin Sans', sans-serif; }
    .page-gutter { padding: 10px 12px 0; }
    .container-fluid { padding-left:0; padding-right:0; }
    .row.gx-3 { --bs-gutter-x:1rem; }
    .main-like { background:#fff; min-height:calc(100vh - 56px); border-left:1px solid rgba(0,0,0,.06); }
    .main-like { padding-left:.75rem; padding-right:.75rem; }
    @media (min-width:768px){ .main-like { padding-left:1rem; padding-right:1rem; } }

    .card-gradient { background:linear-gradient(135deg,rgba(13,110,253,.08),rgba(13,110,253,.02)); border:1px solid rgba(13,110,253,.15); }
    .card-gradient-success{ background:linear-gradient(135deg,rgba(25,135,84,.1),rgba(25,135,84,.03)); border:1px solid rgba(25,135,84,.15); }
    .card-gradient-warning{ background:linear-gradient(135deg,rgba(255,193,7,.14),rgba(255,193,7,.04)); border:1px solid rgba(255,193,7,.25); }
    .card-gradient-danger{ background:linear-gradient(135deg,rgba(220,53,69,.14),rgba(220,53,69,.04)); border:1px solid rgba(220,53,69,.25); }
    .ring{ display:flex; align-items:center; gap:12px; }
    .kpi-title{ font-size:.8rem; text-transform:uppercase; letter-spacing:.04em; color:#6c757d; }
    .kpi-value{ font-weight:800; font-size:1.35rem; }
    .pill{ padding:.2rem .5rem; border-radius:999px; font-weight:600; font-size:.75rem; }
    .pill-primary{ background:#e7f0ff; color:#0d6efd; }
    .pill-info{ background:#e7fbff; color:#0aa2c0; }
    .pill-success{ background:#e7fff3; color:#198754; }
    .pill-warning{ background:#fff8e1; color:#b38100; }
    .pill-danger{ background:#ffe8ea; color:#c2273d; }
    .list-item-icon{ width:42px; height:42px; border-radius:50%; display:flex; align-items:center; justify-content:center; }
    .icon-driver{ background:#e7f0ff; color:#0d6efd; }
    .icon-vehicle{ background:#e7fbff; color:#0aa2c0; }
    .progress{ height:.5rem; background:#eef1f5; }
    .progress-bar.warn{ background:linear-gradient(90deg,#ffc107,#ff9800); }
    .progress-bar.danger{ background:linear-gradient(90deg,#dc3545,#ff1744); }

    .card-header { background:#fff; color:#212529; }
    .nav-tabs .nav-link { color:#0d6efd; background:transparent; }
    .nav-tabs .nav-link.active {
      color:#000 !important;
      background:#e9ecef;
      border-color:#dee2e6 #dee2e6 #fff;
      font-weight:700;
    }

    /* Status chips (normalized to lowercase keys) */
    .adv-status { padding:6px 12px; border-radius:999px; font-size:.7rem; font-weight:700; text-transform:uppercase; }
    .adv-status.pending   { background:#fff8e1; color:#b38100; }
    .adv-status.approved  { background:#e7fff3; color:#198754; }
    .adv-status.rejected  { background:#ffe8ea; color:#c2273d; }
    .adv-status.disbursed { background:#e7f0ff; color:#0d6efd; }

    .adv-amount { font-size:1.25rem; font-weight:800; color:#198754; }
    .adv-filter .btn { border-radius:999px; border:2px solid #dee2e6; color:#6c757d; }
    .adv-filter .btn.active, .adv-filter .btn:hover { border-color:#0d6efd; color:#0d6efd; background:#e7f0ff; }
    .adv-history { max-height:300px; overflow-y:auto; }
    .adv-history .item { background:#f8f9fa; border-radius:10px; padding:12px; margin-bottom:10px; border-left:4px solid #0d6efd; }
    .adv-card:hover{ transform: translateY(-2px); transition: transform .2s ease; }
    .adv-btn-approve{ background:linear-gradient(45deg,#198754,#20c997); color:#fff; border:none; }
    .adv-btn-reject{ background:linear-gradient(45deg,#dc3545,#e74c3c); color:#fff; border:none; }
  </style>
</head>
<body>
  <?php include 'includes/navbar.php'; ?>

  <div class="page-gutter">
    <div class="container-fluid">
      <div class="row gx-3">
        <?php include 'includes/sidebar.php'; ?>

        <main class="main-like main col-md-9 ms-sm-auto col-lg-10 px-2">

          <div class="d-flex justify-content-between align-items-center pt-2 pb-2 mb-3 border-bottom">
            <div class="d-flex align-items-center gap-2">
              <i class="fas fa-gauge-high"></i>
              <h1 class="h4 mb-0">Dashboard</h1>
            </div>
            <div class="btn-group">
              <a href="upload_document.php" class="btn btn-sm btn-success"><i class="fas fa-upload"></i> Upload Driver Doc</a>
              <a href="vehicle_docs_upload.php" class="btn btn-sm btn-info text-white"><i class="fas fa-file-upload"></i> Upload Vehicle Doc</a>
              <a href="send_advance_upload.php" class="btn btn-sm btn-primary"><i class="fas fa-paper-plane"></i> Send Advance</a>
            </div>
          </div>

          <!-- Tabs -->
          <ul class="nav nav-tabs" id="dvTabs" role="tablist">
            <li class="nav-item" role="presentation">
              <button class="nav-link active" id="drivers-tab" data-bs-toggle="tab" data-bs-target="#drivers"
                      type="button" role="tab" aria-controls="drivers" aria-selected="true">
                <i class="fas fa-id-card-clip me-1"></i> Drivers
              </button>
            </li>
            <li class="nav-item" role="presentation">
              <button class="nav-link" id="vehicles-tab" data-bs-toggle="tab" data-bs-target="#vehicles"
                      type="button" role="tab" aria-controls="vehicles" aria-selected="false">
                <i class="fas fa-truck me-1"></i> Vehicles
              </button>
            </li>
            <li class="nav-item" role="presentation">
              <button class="nav-link" id="maintenance-tab" data-bs-toggle="tab" data-bs-target="#maintenance"
                      type="button" role="tab" aria-controls="maintenance" aria-selected="false">
                <i class="fas fa-screwdriver-wrench me-1"></i> Maintenance
              </button>
            </li>
            <!-- Approvals tab with optional pending badge -->
            <li class="nav-item" role="presentation">
              <button class="nav-link" id="approval-tab" data-bs-toggle="tab" data-bs-target="#approval"
                      type="button" role="tab" aria-controls="approval" aria-selected="false">
                <i class="fas fa-money-bill-wave me-1"></i> Advance
                <span id="adv-tab-pending" class="badge bg-warning text-dark ms-2" style="display:none;"></span>
              </button>
            </li>
          </ul>

          <div class="tab-content" id="dvTabsContent">

            <!-- ==================== DRIVERS ==================== -->
            <div class="tab-pane fade show active" id="drivers" role="tabpanel" aria-labelledby="drivers-tab">
              <!-- KPI cards -->
              <div class="row g-3 mt-1">
                <div class="col-12 col-md-6 col-xl-3">
                  <div class="card card-gradient shadow-sm h-100">
                    <div class="card-body d-flex justify-content-between align-items-center">
                      <div>
                        <div class="kpi-title">Active Drivers</div>
                        <div class="kpi-value"><?= number_format($drv['total_subjects']) ?></div>
                        <span class="pill pill-primary"><i class="fas fa-user me-1"></i> People</span>
                      </div>
                      <div class="ring"><?= svg_donut(100, 96, 10, '#0d6efd') ?></div>
                    </div>
                  </div>
                </div>

                <div class="col-12 col-md-6 col-xl-3">
                  <div class="card card-gradient-success shadow-sm h-100">
                    <div class="card-body d-flex justify-content-between align-items-center">
                      <div>
                        <div class="kpi-title">Driver Documents</div>
                        <div class="kpi-value"><?= number_format($drv['total_docs']) ?></div>
                        <span class="pill pill-success"><i class="fas fa-folder-open me-1"></i> Files</span>
                      </div>
                      <div class="ring"><?= svg_donut(100, 96, 10, '#198754') ?></div>
                    </div>
                  </div>
                </div>

                <div class="col-12 col-md-6 col-xl-3">
                  <div class="card card-gradient-warning shadow-sm h-100">
                    <div class="card-body">
                      <div class="kpi-title mb-1">Expiring (≤ <?= (int)$WARNING_DAYS ?>d)</div>
                      <div class="d-flex align-items-center justify-content-between">
                        <div class="kpi-value"><?= number_format($drv['expiring']) ?></div>
                        <div class="ring"><?= svg_donut($drv_pct_expiring, 96, 10, '#ffc107') ?></div>
                      </div>
                      <div class="progress mt-2">
                        <div class="progress-bar warn" role="progressbar" style="width: <?= $drv_pct_expiring ?>%"></div>
                      </div>
                    </div>
                  </div>
                </div>

                <div class="col-12 col-md-6 col-xl-3">
                  <div class="card card-gradient-danger shadow-sm h-100">
                    <div class="card-body">
                      <div class="kpi-title mb-1">Expired</div>
                      <div class="d-flex align-items-center justify-content-between">
                        <div class="kpi-value"><?= number_format($drv['expired']) ?></div>
                        <div class="ring"><?= svg_donut($drv_pct_expired, 96, 10, '#dc3545') ?></div>
                      </div>
                      <div class="progress mt-2">
                        <div class="progress-bar danger" role="progressbar" style="width: <?= $drv_pct_expired ?>%"></div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <!-- Lists -->
              <div class="row g-3 mt-1">
                <!-- Recent Activity -->
                <div class="col-lg-4">
                  <div class="card shadow-sm h-100">
                    <div class="card-header">
                      <strong><i class="fas fa-clock me-1"></i> Recent Activity (Drivers)</strong>
                      <span class="float-end pill pill-primary"><i class="fas fa-upload me-1"></i> Last 10</span>
                    </div>
                    <div class="card-body">
                      <?php if (empty($drv['recent_activity'])): ?>
                        <p class="text-muted mb-0">No recent activity</p>
                      <?php else: foreach ($drv['recent_activity'] as $r): ?>
                        <div class="d-flex align-items-center mb-3">
                          <div class="list-item-icon icon-driver me-3"><i class="fas fa-user"></i></div>
                          <div>
                            <div class="small text-muted"><?= $r['when_at'] ? date('M j, Y g:i A', strtotime($r['when_at'])) : '' ?></div>
                            <div>
                              <strong><?= h(driver_label($r['emp_id'] ?? '', $r['name'] ?? '')) ?></strong> — <?= h($r['doc_name']) ?>
                              <span class="pill pill-primary"><?= h(ucfirst($r['doc_type'])) ?></span>
                            </div>
                          </div>
                        </div>
                      <?php endforeach; endif; ?>
                    </div>
                  </div>
                </div>

                <!-- Upcoming Expiries -->
                <div class="col-lg-4">
                  <div class="card shadow-sm h-100">
                    <div class="card-header">
                      <strong><i class="fas fa-calendar-day me-1"></i> Upcoming Expiries (Drivers)</strong>
                      <span class="float-end pill pill-warning"><i class="fas fa-hourglass-half me-1"></i> ≤ <?= (int)$WARNING_DAYS ?> days</span>
                    </div>
                    <div class="card-body">
                      <?php if (empty($drv['upcoming_expiries'])): ?>
                        <p class="text-muted mb-0">No upcoming expiries</p>
                      <?php else: foreach ($drv['upcoming_expiries'] as $e): ?>
                        <?php $urgent = ((int)$e['days_to_expiry'] <= 7); ?>
                        <div class="d-flex align-items-center mb-3">
                          <div class="list-item-icon <?= $urgent ? 'bg-danger text-white' : 'bg-warning text-dark' ?> me-3">
                            <i class="fas fa-exclamation-triangle"></i>
                          </div>
                          <div>
                            <div class="small text-muted">
                              Expires: <?= $e['expiry_at'] ? date('M j, Y', strtotime($e['expiry_at'])) : '' ?>
                              (<?= (int)$e['days_to_expiry'] ?> days)
                            </div>
                            <div>
                              <strong><?= h(driver_label($e['emp_id'] ?? '', $e['name'] ?? '')) ?></strong> — <?= h($e['doc_name']) ?>
                              <span class="pill <?= $urgent ? 'pill-danger' : 'pill-warning' ?>"><?= h(ucfirst($e['doc_type'])) ?></span>
                            </div>
                          </div>
                        </div>
                      <?php endforeach; endif; ?>
                    </div>
                  </div>
                </div>

                <!-- Expired -->
                <div class="col-lg-4">
                  <div class="card shadow-sm h-100">
                    <div class="card-header">
                      <strong><i class="fas fa-calendar-times me-1"></i> Expired Documents (Drivers)</strong>
                      <span class="float-end pill pill-danger"><i class="fas fa-ban me-1"></i> Showing 20</span>
                    </div>
                    <div class="card-body">
                      <?php if (empty($drv['expired_list'])): ?>
                        <p class="text-muted mb-0">No expired documents</p>
                      <?php else: foreach ($drv['expired_list'] as $x): ?>
                        <div class="d-flex align-items-center mb-3">
                          <div class="list-item-icon bg-danger text-white me-3">
                            <i class="fas fa-times-circle"></i>
                          </div>
                          <div>
                            <div class="small text-muted">
                              Expired: <?= $x['expired_at'] ? date('M j, Y', strtotime($x['expired_at'])) : '' ?>
                            </div>
                            <div>
                              <strong><?= h(driver_label($x['emp_id'] ?? '', $x['name'] ?? '')) ?></strong> — <?= h($x['doc_name']) ?>
                              <span class="pill pill-danger"><?= h(ucfirst($x['doc_type'])) ?></span>
                            </div>
                          </div>
                        </div>
                      <?php endforeach; endif; ?>
                    </div>
                  </div>
                </div>
              </div>
            </div><!-- /drivers tab -->

            <!-- ==================== VEHICLES ==================== -->
            <div class="tab-pane fade" id="vehicles" role="tabpanel" aria-labelledby="vehicles-tab">
              <!-- KPI cards -->
              <div class="row g-3 mt-1">
                <div class="col-12 col-md-6 col-xl-3">
                  <div class="card card-gradient shadow-sm h-100">
                    <div class="card-body d-flex justify-content-between align-items-center">
                      <div>
                        <div class="kpi-title">Vehicles</div>
                        <div class="kpi-value"><?= number_format($veh['total_subjects']) ?></div>
                        <span class="pill pill-info"><i class="fas fa-truck-moving me-1"></i> Fleet</span>
                      </div>
                      <div class="ring"><?= svg_donut(100, 96, 10, '#0aa2c0') ?></div>
                    </div>
                  </div>
                </div>

                <div class="col-12 col-md-6 col-xl-3">
                  <div class="card card-gradient-success shadow-sm h-100">
                    <div class="card-body d-flex justify-content-between align-items-center">
                      <div>
                        <div class="kpi-title">Vehicle Documents</div>
                        <div class="kpi-value"><?= number_format($veh['total_docs']) ?></div>
                        <span class="pill pill-success"><i class="fas fa-file-contract me-1"></i> Files</span>
                      </div>
                      <div class="ring"><?= svg_donut(100, 96, 10, '#198754') ?></div>
                    </div>
                  </div>
                </div>

                <div class="col-12 col-md-6 col-xl-3">
                  <div class="card card-gradient-warning shadow-sm h-100">
                    <div class="card-body">
                      <div class="kpi-title mb-1">Expiring (≤ <?= (int)$WARNING_DAYS ?>d)</div>
                      <div class="d-flex align-items-center justify-content-between">
                        <div class="kpi-value"><?= number_format($veh['expiring']) ?></div>
                        <div class="ring"><?= svg_donut($veh_pct_expiring, 96, 10, '#ffc107') ?></div>
                      </div>
                      <div class="progress mt-2">
                        <div class="progress-bar warn" role="progressbar" style="width: <?= $veh_pct_expiring ?>%"></div>
                      </div>
                    </div>
                  </div>
                </div>

                <div class="col-12 col-md-6 col-xl-3">
                  <div class="card card-gradient-danger shadow-sm h-100">
                    <div class="card-body">
                      <div class="kpi-title mb-1">Expired</div>
                      <div class="d-flex align-items-center justify-content-between">
                        <div class="kpi-value"><?= number_format($veh['expired']) ?></div>
                        <div class="ring"><?= svg_donut($veh_pct_expired, 96, 10, '#dc3545') ?></div>
                      </div>
                      <div class="progress mt-2">
                        <div class="progress-bar danger" role="progressbar" style="width: <?= $veh_pct_expired ?>%"></div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <!-- Lists -->
              <div class="row g-3 mt-1">
                <!-- Recent Activity -->
                <div class="col-lg-4">
                  <div class="card shadow-sm h-100">
                    <div class="card-header">
                      <strong><i class="fas fa-clock me-1"></i> Recent Activity (Vehicles)</strong>
                      <span class="float-end pill pill-info"><i class="fas fa-upload me-1"></i> Last 10</span>
                    </div>
                    <div class="card-body">
                      <?php if (empty($veh['recent_activity'])): ?>
                        <p class="text-muted mb-0">No recent activity</p>
                      <?php else: foreach ($veh['recent_activity'] as $r): ?>
                        <div class="d-flex align-items-center mb-3">
                          <div class="list-item-icon icon-vehicle me-3"><i class="fas fa-truck"></i></div>
                          <div>
                            <div class="small text-muted"><?= $r['when_at'] ? date('M j, Y g:i A', strtotime($r['when_at'])) : '' ?></div>
                            <div>
                              <strong><?= h($r['subject_label']) ?></strong> — <?= h($r['doc_name']) ?>
                              <span class="pill pill-info"><?= h(ucfirst($r['doc_type'])) ?></span>
                            </div>
                          </div>
                        </div>
                      <?php endforeach; endif; ?>
                    </div>
                  </div>
                </div>

                <!-- Upcoming Expiries (exclude registration) -->
                <div class="col-lg-4">
                  <div class="card shadow-sm h-100">
                    <div class="card-header">
                      <strong><i class="fas fa-calendar-day me-1"></i> Upcoming Expiries (Vehicles)</strong>
                      <span class="float-end pill pill-warning"><i class="fas fa-hourglass-half me-1"></i> ≤ <?= (int)$WARNING_DAYS ?> days</span>
                    </div>
                    <div class="card-body">
                      <?php if (empty($veh['upcoming_expiries'])): ?>
                        <p class="text-muted mb-0">No upcoming expiries</p>
                      <?php else: foreach ($veh['upcoming_expiries'] as $e): ?>
                        <?php $urgent = ((int)$e['days_to_expiry'] <= 7); ?>
                        <div class="d-flex align-items-center mb-3">
                          <div class="list-item-icon <?= $urgent ? 'bg-danger text-white' : 'bg-warning text-dark' ?> me-3">
                            <i class="fas fa-exclamation-triangle"></i>
                          </div>
                          <div>
                            <div class="small text-muted">
                              Expires: <?= $e['expiry_at'] ? date('M j, Y', strtotime($e['expiry_at'])) : '' ?>
                              (<?= (int)$e['days_to_expiry'] ?> days)
                            </div>
                            <div>
                              <strong><?= h($e['subject_label']) ?></strong> — <?= h($e['doc_name']) ?>
                              <span class="pill <?= $urgent ? 'pill-danger' : 'pill-warning' ?>"><?= h(ucfirst($e['doc_type'])) ?></span>
                            </div>
                          </div>
                        </div>
                      <?php endforeach; endif; ?>
                    </div>
                  </div>
                </div>

                <!-- Expired (exclude registration) -->
                <div class="col-lg-4">
                  <div class="card shadow-sm h-100">
                    <div class="card-header">
                      <strong><i class="fas fa-calendar-times me-1"></i> Expired Documents (Vehicles)</strong>
                      <span class="float-end pill pill-danger"><i class="fas fa-ban me-1"></i> Showing 20</span>
                    </div>
                    <div class="card-body">
                      <?php if (empty($veh['expired_list'])): ?>
                        <p class="text-muted mb-0">No expired documents</p>
                      <?php else: foreach ($veh['expired_list'] as $x): ?>
                        <div class="d-flex align-items-center mb-3">
                          <div class="list-item-icon bg-danger text-white me-3">
                            <i class="fas fa-times-circle"></i>
                          </div>
                          <div>
                            <div class="small text-muted">
                              Expired: <?= $x['expired_at'] ? date('M j, Y', strtotime($x['expired_at'])) : '' ?>
                            </div>
                            <div>
                              <strong><?= h($x['subject_label']) ?></strong> — <?= h($x['doc_name']) ?>
                              <span class="pill pill-danger"><?= h(ucfirst($x['doc_type'])) ?></span>
                            </div>
                          </div>
                        </div>
                      <?php endforeach; endif; ?>
                    </div>
                  </div>
                </div>
              </div>
            </div><!-- /vehicles tab -->

            <!-- ==================== MAINTENANCE ==================== -->
            <div class="tab-pane fade" id="maintenance" role="tabpanel" aria-labelledby="maintenance-tab">
              <!-- KPI cards -->
              <div class="row g-3 mt-1">
                <div class="col-12 col-md-6 col-xl-3">
                  <div class="card card-gradient shadow-sm h-100">
                    <div class="card-body d-flex justify-content-between align-items-center">
                      <div>
                        <div class="kpi-title">Vehicles Tracked</div>
                        <div class="kpi-value"><?= number_format($mnt['total_vehicles']) ?></div>
                        <span class="pill pill-info"><i class="fas fa-truck me-1"></i> Maintenance</span>
                      </div>
                      <div class="ring"><?= svg_donut(100, 96, 10, '#0aa2c0') ?></div>
                    </div>
                  </div>
                </div>

                <div class="col-12 col-md-6 col-xl-3">
                  <div class="card card-gradient-warning shadow-sm h-100">
                    <div class="card-body">
                      <div class="kpi-title mb-1">Due Soon (≤ <?= (int)$WARNING_DAYS ?>d or ≤ <?= (int)$KM_SOON ?>km)</div>
                      <div class="d-flex align-items-center justify-content-between">
                        <div class="kpi-value"><?= number_format($mnt['due_soon']) ?></div>
                        <div class="ring"><?= svg_donut($mnt_pct_due, 96, 10, '#ffc107') ?></div>
                      </div>
                      <div class="progress mt-2">
                        <div class="progress-bar warn" role="progressbar" style="width: <?= $mnt_pct_due ?>%"></div>
                      </div>
                    </div>
                  </div>
                </div>

                <div class="col-12 col-md-6 col-xl-3">
                  <div class="card card-gradient-danger shadow-sm h-100">
                    <div class="card-body">
                      <div class="kpi-title mb-1">Overdue</div>
                      <div class="d-flex align-items-center justify-content-between">
                        <div class="kpi-value"><?= number_format($mnt['overdue']) ?></div>
                        <div class="ring"><?= svg_donut($mnt_pct_overdue, 96, 10, '#dc3545') ?></div>
                      </div>
                      <div class="progress mt-2">
                        <div class="progress-bar danger" role="progressbar" style="width: <?= $mnt_pct_overdue ?>%"></div>
                      </div>
                    </div>
                  </div>
                </div>

                <div class="col-12 col-md-6 col-xl-3">
                  <div class="card card-gradient-success shadow-sm h-100">
                    <div class="card-body d-flex justify-content-between align-items-center">
                      <div>
                        <div class="kpi-title">Recent Updates (7d)</div>
                        <div class="kpi-value"><?= number_format($mnt['recent_updates']) ?></div>
                        <span class="pill pill-success"><i class="fas fa-wrench me-1"></i> Logs</span>
                      </div>
                      <div class="ring"><?= svg_donut(100, 96, 10, '#198754') ?></div>
                    </div>
                  </div>
                </div>
              </div>

              <!-- Lists -->
              <div class="row g-3 mt-1">
                <!-- Due Soon -->
                <div class="col-lg-4">
                  <div class="card shadow-sm h-100">
                    <div class="card-header">
                      <strong><i class="fas fa-hourglass-half me-1"></i> Due Soon (Maintenance)</strong>
                      <span class="float-end pill pill-warning">Date ≤ <?= (int)$WARNING_DAYS ?>d or Km ≤ <?= (int)$KM_SOON ?></span>
                    </div>
                    <div class="card-body">
                      <?php if (empty($mnt['due_list'])): ?>
                        <p class="text-muted mb-0">Nothing due soon</p>
                      <?php else: foreach ($mnt['due_list'] as $m): ?>
                        <?php
                          $days = isset($m['days_to_next']) ? (int)$m['days_to_next'] : null;
                          $kmrem = (isset($m['km_remaining']) && $m['km_remaining'] !== null) ? (int)$m['km_remaining'] : null;
                          $urgent = ($days !== null && $days <= 7) || ($kmrem !== null && $kmrem <= 200);
                        ?>
                        <div class="d-flex align-items-center mb-3">
                          <div class="list-item-icon <?= $urgent ? 'bg-danger text-white' : 'bg-warning text-dark' ?> me-3">
                            <i class="fas fa-screwdriver-wrench"></i>
                          </div>
                          <div>
                            <div><strong><?= h($m['vehicle_no']) ?></strong> — <?= h($m['kind']) ?></div>
                            <div class="small text-muted">
                              <?php if (!empty($m['next_date'])): ?>
                                Next Date: <?= date('M j, Y', strtotime($m['next_date'])) ?>
                                <?= ($days !== null) ? " (in " . (int)$days . "d)" : "" ?>
                                <?php if ($kmrem !== null) echo " • Km remaining: " . number_format($kmrem); ?>
                              <?php elseif ($kmrem !== null): ?>
                                Km remaining: <?= number_format($kmrem) ?>
                              <?php else: ?>
                                No schedule found
                              <?php endif; ?>
                            </div>
                          </div>
                        </div>
                      <?php endforeach; endif; ?>
                    </div>
                  </div>
                </div>

                <!-- Overdue -->
                <div class="col-lg-4">
                  <div class="card shadow-sm h-100">
                    <div class="card-header">
                      <strong><i class="fas fa-circle-exclamation me-1"></i> Overdue (Maintenance)</strong>
                      <span class="float-end pill pill-danger">Past date or exceeded km</span>
                    </div>
                    <div class="card-body">
                      <?php if (empty($mnt['overdue_list'])): ?>
                        <p class="text-muted mb-0">No overdue items</p>
                      <?php else: foreach ($mnt['overdue_list'] as $m): ?>
                        <?php
                          $days = isset($m['days_to_next']) ? (int)$m['days_to_next'] : null;
                          $kmrem = (isset($m['km_remaining']) && $m['km_remaining'] !== null) ? (int)$m['km_remaining'] : null;
                        ?>
                        <div class="d-flex align-items-center mb-3">
                          <div class="list-item-icon bg-danger text-white me-3">
                            <i class="fas fa-wrench"></i>
                          </div>
                          <div>
                            <div><strong><?= h($m['vehicle_no']) ?></strong> — <?= h($m['kind']) ?></div>
                            <div class="small text-muted">
                              <?php if (!empty($m['next_date']) && $days !== null && $days < 0): ?>
                                Due: <?= date('M j, Y', strtotime($m['next_date'])) ?> (<?= (int)abs($days) ?>d late)
                                <?php if ($kmrem !== null) echo " • Km over: " . number_format(max(0, -$kmrem)); ?>
                              <?php elseif ($kmrem !== null && $kmrem <= 0): ?>
                                Km over: <?= number_format(abs($kmrem)) ?>
                              <?php else: ?>
                                Overdue
                              <?php endif; ?>
                            </div>
                          </div>
                        </div>
                      <?php endforeach; endif; ?>
                    </div>
                  </div>
                </div>

                <!-- Recent Maintenance Updates -->
                <div class="col-lg-4">
                  <div class="card shadow-sm h-100">
                    <div class="card-header">
                      <strong><i class="fas fa-clock-rotate-left me-1"></i> Recent Maintenance Updates</strong>
                      <span class="float-end pill pill-success"><i class="fas fa-list-check me-1"></i> Last 10</span>
                    </div>
                    <div class="card-body">
                      <?php if (empty($mnt['recent_activity'])): ?>
                        <p class="text-muted mb-0">No recent updates</p>
                      <?php else: foreach ($mnt['recent_activity'] as $r): ?>
                        <div class="d-flex align-items-center mb-3">
                          <div class="list-item-icon bg-success text-white me-3"><i class="fas fa-screwdriver-wrench"></i></div>
                          <div>
                            <div class="small text-muted"><?= $r['when_at'] ? date('M j, Y g:i A', strtotime($r['when_at'])) : '' ?></div>
                            <div><strong><?= h($r['subject_label']) ?></strong> — Updated maintenance</div>
                          </div>
                        </div>
                      <?php endforeach; endif; ?>
                    </div>
                  </div>
                </div>
              </div>
            </div><!-- /maintenance tab -->

            <!-- ==================== APPROVALS (Advance Requests) ==================== -->
            <div class="tab-pane fade" id="approval" role="tabpanel" aria-labelledby="approval-tab">
              <!-- Header widgets -->
              <div class="row g-3 mt-1">
                <div class="col-12 col-md-6 col-xl-3">
                  <div class="card card-gradient shadow-sm h-100">
                    <div class="card-body d-flex justify-content-between align-items-center">
                      <div>
                        <div class="kpi-title">Total Requests</div>
                        <div class="kpi-value" id="adv-total">0</div>
                        <span class="pill pill-info"><i class="fas fa-money-bill-wave me-1"></i> Advances</span>
                      </div>
                      <div class="ring"><?= svg_donut(100, 96, 10, '#0aa2c0') ?></div>
                    </div>
                  </div>
                </div>
                <div class="col-12 col-md-6 col-xl-3">
                  <div class="card card-gradient-warning shadow-sm h-100">
                    <div class="card-body">
                      <div class="kpi-title mb-1">Pending</div>
                      <div class="d-flex align-items-center justify-content-between">
                        <div class="kpi-value" id="adv-pending">0</div>
                        <div class="ring"><?= svg_donut(100, 96, 10, '#ffc107') ?></div>
                      </div>
                    </div>
                  </div>
                </div>
                <div class="col-12 col-md-6 col-xl-3">
                  <div class="card card-gradient-success shadow-sm h-100">
                    <div class="card-body">
                      <div class="kpi-title mb-1">Approved</div>
                      <div class="d-flex align-items-center justify-content-between">
                        <div class="kpi-value" id="adv-approved">0</div>
                        <div class="ring"><?= svg_donut(100, 96, 10, '#198754') ?></div>
                      </div>
                    </div>
                  </div>
                </div>
                <div class="col-12 col-md-6 col-xl-3">
                  <div class="card card-gradient-danger shadow-sm h-100">
                    <div class="card-body">
                      <div class="kpi-title mb-1">Rejected</div>
                      <div class="d-flex align-items-center justify-content-between">
                        <div class="kpi-value" id="adv-rejected">0</div>
                        <div class="ring"><?= svg_donut(100, 96, 10, '#dc3545') ?></div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <!-- Filters -->
              <div class="card shadow-sm mt-2">
                <div class="card-body">
                  <div class="d-flex flex-wrap align-items-center justify-content-between">
                    <h6 class="mb-2 mb-md-0"><i class="fas fa-filter me-2"></i>Filter by Status</h6>
                    <div class="btn-group adv-filter" role="group" aria-label="Advance Filters">
                      <button type="button" class="btn btn-sm btn-light active" data-status="all">
                        All (<span id="adv-count-all">0</span>)
                      </button>
                      <button type="button" class="btn btn-sm btn-light" data-status="pending">
                        Pending (<span id="adv-count-pending">0</span>)
                      </button>
                      <button type="button" class="btn btn-sm btn-light" data-status="approved">
                        Approved (<span id="adv-count-approved">0</span>)
                      </button>
                      <button type="button" class="btn btn-sm btn-light" data-status="rejected">
                        Rejected (<span id="adv-count-rejected">0</span>)
                      </button>
                    </div>
                  </div>
                </div>
              </div>

              <!-- Loading -->
              <div class="text-center py-5" id="adv-loading" style="display:none;">
                <div class="spinner-border" role="status" aria-hidden="true"></div>
                <div class="mt-3 text-muted">Loading advance requests…</div>
              </div>

              <!-- Requests List -->
              <div id="adv-list" class="mt-2"></div>

              <!-- Pagination -->
              <nav aria-label="Advance pagination" class="mt-3" id="adv-pagination" style="display:none;">
                <ul class="pagination justify-content-center"></ul>
              </nav>
            </div><!-- /approval tab -->
          </div><!-- /.tab-content -->
        </main>
      </div>
    </div>
  </div><!-- /page-gutter -->

  <!-- Request Details Modal -->
  <div class="modal fade" id="adv-request-modal" tabindex="-1" aria-hidden="true">
    <div class="modal-dialog modal-lg">
      <div class="modal-content">
        <div class="modal-header">
          <h5 class="modal-title"><i class="fas fa-file-invoice-dollar me-2"></i>Advance Request Details</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
        </div>
        <div class="modal-body" id="adv-request-details">
          <!-- filled by JS -->
        </div>
        <div class="modal-footer" id="adv-modal-footer">
          <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
          <!-- approve/reject buttons inserted dynamically if pending -->
        </div>
      </div>
    </div>
  </div>

  <!-- Approval Modal -->
  <div class="modal fade" id="adv-approval-modal" tabindex="-1" aria-hidden="true">
    <div class="modal-dialog">
      <div class="modal-content">
        <div class="modal-header">
          <h5 class="modal-title"><i class="fas fa-check-circle me-2"></i><span id="adv-approval-title">Approve Request</span></h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
        </div>
        <div class="modal-body">
          <div class="mb-3">
            <label class="form-label">Comments (Optional)</label>
            <textarea class="form-control" id="adv-approval-comments" rows="3" placeholder="Enter any comments about this decision..."></textarea>
          </div>
          <div class="alert alert-info mb-0">
            <div><strong>Driver:</strong> <span id="adv-driver-name"></span></div>
            <div><strong>Amount:</strong> <span id="adv-request-amount"></span></div>
            <div><strong>Reason:</strong> <span id="adv-request-reason"></span></div>
          </div>
        </div>
        <div class="modal-footer">
          <button class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
          <button class="btn adv-btn-approve" id="adv-confirm-approve"><i class="fas fa-check me-1"></i>Approve</button>
          <button class="btn adv-btn-reject" id="adv-confirm-reject"><i class="fas fa-times me-1"></i>Reject</button>
        </div>
      </div>
    </div>
  </div>

  <!-- Disburse Modal -->
  <div class="modal fade" id="adv-disburse-modal" tabindex="-1" aria-hidden="true">
    <div class="modal-dialog">
      <div class="modal-content">
        <div class="modal-header">
          <h5 class="modal-title"><i class="fas fa-indian-rupee-sign me-2"></i>Mark Disbursed</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
        </div>
        <div class="modal-body">
          <div class="mb-3">
            <label class="form-label">Reference No. / UTR (optional)</label>
            <input type="text" class="form-control" id="adv-disb-ref" placeholder="e.g. UTR123..." />
          </div>
          <div class="mb-3">
            <label class="form-label">Paid On (optional)</label>
            <input type="date" class="form-control" id="adv-disb-date" />
          </div>
          <div class="mb-3">
            <label class="form-label">Comments (optional)</label>
            <textarea class="form-control" id="adv-disb-comments" rows="2" placeholder="Any note..."></textarea>
          </div>
          <div class="alert alert-info mb-0 small">
            This will set the request status to <strong>Disbursed</strong>.
          </div>
        </div>
        <div class="modal-footer">
          <button class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
          <button class="btn btn-success" id="adv-confirm-disburse"><i class="fas fa-check me-1"></i>Confirm Disbursed</button>
        </div>
      </div>
    </div>
  </div>

  <!-- JS -->
  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
  <script>
    // ---------- API helpers ----------
    const API_BASE = '/api/mobile/';
    const api = (path) => `${API_BASE}${path}`;

    async function fetchJSON(url, options = {}) {
      const res = await fetch(url, { credentials: 'include', ...options });
      const ct = (res.headers.get('content-type') || '').toLowerCase();

      let data = null;
      if (ct.includes('application/json')) {
        try { data = await res.json(); } catch (e) { /* fallthrough */ }
      }
      if (data) {
        if (!res.ok || data.ok === false) {
          const msg = (data.error || data.message) || `HTTP ${res.status}`;
          throw new Error(msg);
        }
        return data;
      }
      const text = await res.text();
      const preview = text.replace(/\s+/g, ' ').slice(0, 200);
      throw new Error(`Expected JSON but got ${ct || 'unknown'} — preview: ${preview}`);
    }

    // ===================== Approvals Module =====================
    class AdvanceApproval {
      constructor() {
        this.currentPage = 1;
        this.currentStatus = 'all';
        this.currentRequest = null;
        this.requestsPerPage = 20;
        this._bind();
      }

      _bind() {
        // Filter buttons
        document.querySelectorAll('.adv-filter .btn').forEach(btn => {
          btn.addEventListener('click', () => {
            document.querySelectorAll('.adv-filter .btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            this.currentStatus = btn.dataset.status;
            this.currentPage = 1;
            this.loadRequests();
          });
        });

        // Pagination
        const pager = document.getElementById('adv-pagination');
        if (pager) {
          pager.addEventListener('click', (e) => {
            const a = e.target.closest('a.page-link');
            if (!a) return;
            e.preventDefault();
            const page = parseInt(a.dataset.page, 10);
            if (!isNaN(page) && page > 0) {
              this.currentPage = page;
              this.loadRequests();
            }
          });
        }

        // Modal actions (approve / reject)
        document.getElementById('adv-confirm-approve')
          .addEventListener('click', () => this.processApproval('approve'));
        document.getElementById('adv-confirm-reject')
          .addEventListener('click', () => this.processApproval('reject'));

        // Disburse confirm
        const disbBtn = document.getElementById('adv-confirm-disburse');
        if (disbBtn) disbBtn.addEventListener('click', () => this.processDisburse());

        // Load when approvals tab is shown first time
        const approvalTabBtn = document.getElementById('approval-tab');
        if (approvalTabBtn) {
          approvalTabBtn.addEventListener('shown.bs.tab', () => {
            const list = document.getElementById('adv-list');
            if (!list.dataset.loaded) this.loadRequests();
          });

          // If page lands with Approvals already active, load immediately
          const act = approvalTabBtn.classList.contains('active')
            || document.querySelector('#approval.show.active');
          if (act) this.loadRequests();
        }
      }

      _statusKey(s) { return String(s || '').toLowerCase(); }
      _isPending(s) { return this._statusKey(s) === 'pending'; }

      async loadRequests() {
        this._loading(true);
        try {
          const url = api(
            `advance_requests_list.php?status=${encodeURIComponent(this.currentStatus)}&page=${this.currentPage}&limit=${this.requestsPerPage}`
          );
          const data = await fetchJSON(url);

          const requests   = (data?.data?.requests) || [];
          const counts     = (data?.data?.status_counts) || {};
          const pagination = (data?.data?.pagination) || {};

          this.renderList(requests);
          this.renderCounts(counts);
          this.renderPagination(pagination);

          document.getElementById('adv-list').dataset.loaded = '1';
        } catch (err) {
          this._toast('Error: ' + err.message, true);
          this.renderList([]);
          this.renderPagination({ total_pages: 1, current_page: 1 });
        } finally {
          this._loading(false);
        }
      }

      renderCounts(counts) {
        const total      = counts.total      ?? 0;
        const pending    = counts.pending    ?? 0;
        const approved   = counts.approved   ?? 0;
        const rejected   = counts.rejected   ?? 0;
        const disbursed  = counts.disbursed  ?? 0;

        // KPI cards
        document.getElementById('adv-total').textContent    = total;
        document.getElementById('adv-pending').textContent  = pending;
        document.getElementById('adv-approved').textContent = approved;
        document.getElementById('adv-rejected').textContent = rejected;

        // Filter counts
        const setText = (id, val) => { const el = document.getElementById(id); if (el) el.textContent = val; };
        setText('adv-count-all', total);
        setText('adv-count-pending', pending);
        setText('adv-count-approved', approved);
        setText('adv-count-rejected', rejected);
        setText('adv-count-disbursed', disbursed); // ok if not present

        // Tab badge
        const tabBadge = document.getElementById('adv-tab-pending');
        if (tabBadge) {
          tabBadge.textContent = pending;
          tabBadge.style.display = pending > 0 ? 'inline-block' : 'none';
        }
      }

      renderList(requests) {
        const wrap = document.getElementById('adv-list');
        if (!requests.length) {
          wrap.innerHTML = `
            <div class="card shadow-sm">
              <div class="card-body text-center py-5">
                <i class="fas fa-inbox fa-3x text-muted mb-3"></i>
                <h5>No advance requests found</h5>
                <p class="text-muted mb-0">There are no requests matching your current filter.</p>
              </div>
            </div>`;
          return;
        }

        wrap.innerHTML = requests.map(r => {
          const statusKey = this._statusKey(r.status);
          const isPending = statusKey === 'pending';
          const isApproved = statusKey === 'approved';

          return `
            <div class="card shadow-sm adv-card mb-2">
              <div class="card-body">
                <div class="row align-items-center">
                  <div class="col-md-8">
                    <div class="d-flex align-items-center mb-2">
                      <h6 class="mb-0 me-3">${this._h(r.driver_name)}</h6>
                      <span class="adv-status ${this._h(statusKey)}">${this._h(r.status_label)}</span>
                    </div>
                    <div class="row small text-muted">
                      <div class="col-sm-6">
                        <div><i class="fas fa-id-card me-1"></i>${this._h(r.employee_id || 'N/A')}</div>
                        <div><i class="fas fa-truck me-1"></i>${this._h(r.vehicle_number || 'N/A')}</div>
                        <div><i class="fas fa-building me-1"></i>${this._h(r.plant_name || 'N/A')}</div>
                      </div>
                      <div class="col-sm-6">
                        <div><i class="fas fa-calendar me-1"></i>${this._h(r.formatted_date)}</div>
                        <div><i class="fas fa-comment me-1"></i>${this._h(r.reason || 'No reason provided')}</div>
                      </div>
                    </div>
                  </div>
                  <div class="col-md-4 text-md-end mt-3 mt-md-0">
                    <div class="adv-amount mb-2">${this._h(r.formatted_amount)}</div>
                    <div class="btn-group">
                      <button class="btn btn-outline-primary btn-sm" data-id="${r.id}" data-action="view">
                        <i class="fas fa-eye"></i> View
                      </button>
                      ${isPending ? `
                        <button class="btn adv-btn-approve btn-sm" data-id="${r.id}" data-action="approve" title="Approve">
                          <i class="fas fa-check"></i>
                        </button>
                        <button class="btn adv-btn-reject btn-sm" data-id="${r.id}" data-action="reject" title="Reject">
                          <i class="fas fa-times"></i>
                        </button>`
                      : `
                        ${isApproved ? `
                          <button class="btn btn-success btn-sm" data-id="${r.id}" data-action="disburse" title="Mark Disbursed">
                            <i class="fas fa-indian-rupee-sign"></i>
                          </button>` : ``}
                        <small class="text-muted d-block ms-2">
                          ${r.approver_name ? `By: ${this._h(r.approver_name)}` : ''}<br>
                          ${this._h(r.formatted_approved_date || '')}
                        </small>
                      `}
                    </div>
                  </div>
                </div>
              </div>
            </div>
          `;
        }).join('');

        // Attach row button events
        wrap.querySelectorAll('button[data-action]').forEach(btn => {
          btn.addEventListener('click', () => {
            const id = parseInt(btn.dataset.id, 10);
            const action = btn.dataset.action;
            if (action === 'view') this.viewRequest(id);
            if (action === 'approve') this.showApprovalModal(id, 'approve');
            if (action === 'reject') this.showApprovalModal(id, 'reject');
            if (action === 'disburse') this.showDisburseModal(id);
          });
        });
      }

      renderPagination(p) {
        const nav = document.getElementById('adv-pagination');
        if (!nav) return;
        const ul = nav.querySelector('ul');

        const totalPages = p.total_pages || 1;
        const current    = p.current_page || 1;
        const hasPrev    = !!p.has_prev;
        const hasNext    = !!p.has_next;

        if (totalPages <= 1) {
          nav.style.display = 'none';
          ul.innerHTML = '';
          return;
        }
        nav.style.display = 'block';

        let html = '';
        html += hasPrev
          ? `<li class="page-item"><a class="page-link" href="#" data-page="${current-1}"><i class="fas fa-chevron-left"></i></a></li>`
          : `<li class="page-item disabled"><span class="page-link"><i class="fas fa-chevron-left"></i></span></li>`;

        for (let i = 1; i <= totalPages; i++) {
          html += `<li class="page-item ${i===current?'active':''}"><a class="page-link" href="#" data-page="${i}">${i}</a></li>`;
        }

        html += hasNext
          ? `<li class="page-item"><a class="page-link" href="#" data-page="${current+1}"><i class="fas fa-chevron-right"></i></a></li>`
          : `<li class="page-item disabled"><span class="page-link"><i class="fas fa-chevron-right"></i></span></li>`;

        ul.innerHTML = html;
      }

      async viewRequest(id) {
        try {
          const data = await fetchJSON(api(`advance_request_details.php?id=${id}`));
          const { request, driver, advance_history, advance_stats } = data.data;

          const details = document.getElementById('adv-request-details');
          details.innerHTML = `
            <div class="card card-gradient mb-2">
              <div class="card-body">
                <h6 class="mb-2"><i class="fas fa-user me-2"></i>${this._h(driver.name)}</h6>
                <div class="row small">
                  <div class="col-md-6">
                    <div><strong>Employee ID:</strong> ${this._h(driver.employee_id || 'N/A')}</div>
                    <div><strong>Phone:</strong> ${this._h(driver.phone || 'N/A')}</div>
                    <div><strong>Vehicle:</strong> ${this._h(driver.vehicle_number || 'N/A')}</div>
                  </div>
                  <div class="col-md-6">
                    <div><strong>Plant:</strong> ${this._h(driver.plant_name || 'N/A')}</div>
                    <div><strong>Joining Date:</strong> ${this._h(driver.formatted_joining_date || 'N/A')}</div>
                    <div><strong>Salary:</strong> ${this._h(driver.formatted_salary || 'N/A')}</div>
                  </div>
                </div>
              </div>
            </div>

            <div class="row g-2">
              <div class="col-md-8">
                <div class="card shadow-sm">
                  <div class="card-body">
                    <h6 class="mb-2"><i class="fas fa-file-invoice-dollar me-2"></i>Request</h6>
                    <div class="row">
                      <div class="col-sm-6">
                        <p class="mb-1"><strong>Amount:</strong> ${this._h(request.formatted_amount)}</p>
                        <p class="mb-1"><strong>Status:</strong> <span class="adv-status ${this._h(this._statusKey(request.status))}">${this._h(request.status_label)}</span></p>
                        <p class="mb-1"><strong>Date:</strong> ${this._h(request.formatted_date)}</p>
                      </div>
                      <div class="col-sm-6">
                        ${request.approved_at ? `
                          <p class="mb-1"><strong>Approved By:</strong> ${this._h(request.approver_name || 'N/A')}</p>
                          <p class="mb-1"><strong>Approved Date:</strong> ${this._h(request.formatted_approved_date)}</p>
                        ` : ''}
                      </div>
                    </div>
                    <p class="mb-1"><strong>Reason:</strong></p>
                    <div class="alert alert-light">${this._h(request.reason || 'No reason provided')}</div>
                    ${request.approval_comments ? `
                      <p class="mb-1"><strong>Approval Comments:</strong></p>
                      <div class="alert alert-info mb-0">${this._h(request.approval_comments)}</div>
                    ` : ''}
                  </div>
                </div>
              </div>
              <div class="col-md-4">
                <div class="card shadow-sm">
                  <div class="card-body">
                    <h6 class="mb-2"><i class="fas fa-chart-bar me-2"></i>Advance History</h6>
                    <div class="adv-history mb-2">
                      ${advance_history.length ? advance_history.map(h => `
                        <div class="item">
                          <div class="d-flex justify-content-between">
                            <span class="fw-bold">${this._h(h.formatted_amount)}</span>
                            <span class="adv-status ${this._h(this._statusKey(h.status))}">${this._h(h.status_label)}</span>
                          </div>
                          <div class="small text-muted">${this._h(h.formatted_date)}</div>
                          <div class="small mt-1">${this._h(h.reason || '')}</div>
                        </div>
                      `).join('') : '<p class="text-muted small mb-0">No previous advances</p>'}
                    </div>
                    <hr>
                    <div class="text-center">
                      <div class="small text-muted">Total Approved</div>
                      <div class="h5 text-success mb-0">${this._h(advance_stats.formatted_total_amount)}</div>
                      <div class="small text-muted">${this._h(advance_stats.total_requests)} requests</div>
                    </div>
                  </div>
                </div>
              </div>
            </div>`;

          const footer = document.getElementById('adv-modal-footer');
          if (this._isPending(request.status)) {
            footer.innerHTML = `
              <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
              <button type="button" class="btn adv-btn-approve" data-adv="${request.id}" id="adv-ft-approve"><i class="fas fa-check me-1"></i>Approve</button>
              <button type="button" class="btn adv-btn-reject" data-adv="${request.id}" id="adv-ft-reject"><i class="fas fa-times me-1"></i>Reject</button>`;
            footer.querySelector('#adv-ft-approve').addEventListener('click', () => this.showApprovalModal(request.id, 'approve'));
            footer.querySelector('#adv-ft-reject').addEventListener('click', () => this.showApprovalModal(request.id, 'reject'));
          } else {
            footer.innerHTML = `<button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>`;
          }

          new bootstrap.Modal(document.getElementById('adv-request-modal')).show();
        } catch (err) {
          this._toast('Error: ' + err.message, true);
        }
      }

      showApprovalModal(id, action) {
        this.currentRequest = { id, action };
        fetchJSON(api(`advance_request_details.php?id=${id}`))
          .then(data => {
            const { request, driver } = data.data;
            document.getElementById('adv-approval-title').textContent =
              action === 'approve' ? 'Approve Request' : 'Reject Request';
            document.getElementById('adv-driver-name').textContent = driver.name || 'N/A';
            document.getElementById('adv-request-amount').textContent = request.formatted_amount || '';
            document.getElementById('adv-request-reason').textContent = request.reason || 'No reason provided';
            document.getElementById('adv-confirm-approve').style.display = action === 'approve' ? 'inline-block' : 'none';
            document.getElementById('adv-confirm-reject').style.display = action === 'reject' ? 'inline-block' : 'none';
            new bootstrap.Modal(document.getElementById('adv-approval-modal')).show();
          })
          .catch(err => this._toast('Error: ' + err.message, true));
      }

      async processApproval(action) {
        if (!this.currentRequest) return;
        const comments = document.getElementById('adv-approval-comments').value;

        try {
          const data = await fetchJSON(api('advance_approval.php'), {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              request_id: this.currentRequest.id,
              action,
              comments
            })
          });

          this._toast(data.message || 'Updated');
          bootstrap.Modal.getInstance(document.getElementById('adv-approval-modal'))?.hide();
          bootstrap.Modal.getInstance(document.getElementById('adv-request-modal'))?.hide();
          document.getElementById('adv-approval-comments').value = '';
          this.currentRequest = null;
          this.loadRequests();
        } catch (err) {
          this._toast('Error: ' + err.message, true);
        }
      }

      showDisburseModal(id) {
        this.currentRequest = { id, action: 'disburse' };
        new bootstrap.Modal(document.getElementById('adv-disburse-modal')).show();
      }

      async processDisburse() {
        if (!this.currentRequest || this.currentRequest.action !== 'disburse') return;

        const ref   = document.getElementById('adv-disb-ref').value.trim();
        const paid  = document.getElementById('adv-disb-date').value;
        const notes = document.getElementById('adv-disb-comments').value.trim();

        try {
          const data = await fetchJSON(api('advance_disburse.php'), {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              request_id: this.currentRequest.id,
              reference: ref || null,
              paid_on: paid || null,
              comments: notes || null
            })
          });
          this._toast(data.message || 'Marked disbursed');
          bootstrap.Modal.getInstance(document.getElementById('adv-disburse-modal'))?.hide();
          document.getElementById('adv-disb-ref').value = '';
          document.getElementById('adv-disb-date').value = '';
          document.getElementById('adv-disb-comments').value = '';
          this.currentRequest = null;
          this.loadRequests();
        } catch (err) {
          this._toast('Error: ' + err.message, true);
        }
      }

      _loading(on) {
        document.getElementById('adv-loading').style.display = on ? 'block' : 'none';
      }
      _toast(message, isErr=false) {
        alert((isErr ? '❌ ' : '✅ ') + message);
      }
      _h(s) {
        if (s === null || s === undefined) return '';
        return String(s)
          .replace(/&/g,'&amp;')
          .replace(/</g,'&lt;')
          .replace(/>/g,'&gt;')
          .replace(/"/g,'&quot;')
          .replace(/'/g,'&#39;');
      }
    }

    // Initialize approvals module
    const advanceApproval = new AdvanceApproval();
  </script>
</body>
</html>
