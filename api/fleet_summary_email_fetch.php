<?php
declare(strict_types=1);
/**
 * Fleet summary email fetch — optimized for fast page load.
 * With ?token=xxx: email check / upload / UI dashboard.
 * Without token: browser gets HTML table; ?format=json gets JSON.
 */
$wantsJson = (isset($_GET['format']) && $_GET['format'] === 'json')
    || (strpos($_SERVER['HTTP_ACCEPT'] ?? '', 'application/json') !== false);

define('FLEET_SUMMARY_API_TOKEN', 'fsd_7c9f3c0e8a1b4e2f9d6c1a7b5e3d0c9a');
$token = (string) ($_GET['token'] ?? '');
$tokenValid = ($token !== '' && hash_equals(FLEET_SUMMARY_API_TOKEN, $token));

if (!$tokenValid) {
    if ($wantsJson) {
        $configPaths = [__DIR__ . '/../conf/config.php', __DIR__ . '/../../conf/config.php'];
        $conn = null;
        foreach ($configPaths as $path) {
            if (is_file($path)) { require_once $path; break; }
        }
        if (!isset($conn) || !($conn instanceof mysqli)) {
            http_response_code(500);
            echo json_encode(['ok' => false, 'error' => 'DB not available']);
            exit;
        }
        $result = $conn->query("SELECT * FROM fleet_summary_monthly ORDER BY 1 DESC LIMIT 24");
        $rows = [];
        if ($result) {
            while ($row = $result->fetch_assoc()) { $rows[] = $row; }
            $result->free();
        }
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['ok' => true, 'count' => count($rows), 'data' => $rows], JSON_UNESCAPED_UNICODE);
        exit;
    }
    header('Content-Type: text/html; charset=utf-8');
    ?>
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Fleet Summary</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet"></head><body class="p-3 bg-light">
<h1 class="mb-3">Fleet Summary</h1><div id="loading">Loading…</div><div id="error" class="alert alert-danger d-none"></div><div id="table-wrap" class="table-responsive"></div>
<script>
var w=document.getElementById('table-wrap'),l=document.getElementById('loading'),e=document.getElementById('error');
fetch(window.location.pathname+'?format=json').then(function(r){return r.json();}).then(function(res){
l.style.display='none';
if(!res.ok){e.textContent=res.error||'Failed';e.classList.remove('d-none');return;}
var d=res.data||[],keys=d[0]?Object.keys(d[0]):[];
if(d.length===0){w.innerHTML='<p class="text-muted">No records.</p>';return;}
var esc=function(s){var x=document.createElement('div');x.textContent=s;return x.innerHTML;};
var th=keys.map(function(k){return '<th>'+esc(k)+'</th>';}).join('');
var tr=d.map(function(r){return '<tr>'+keys.map(function(k){return '<td>'+esc(String(r[k]!=null?r[k]:''))+'</td>';}).join('')+'</tr>';}).join('');
w.innerHTML='<table class="table table-striped"><thead><tr>'+th+'</tr></thead><tbody>'+tr+'</tbody></table>';
}).catch(function(err){l.style.display='none';e.textContent='Load failed: '+err.message;e.classList.remove('d-none');});
</script></body></html>
<?php
    exit;
}

header('Content-Type: application/json');
    
    /* ---------------- Errors ---------------- */
    ini_set('display_errors', '1');
    ini_set('display_startup_errors', '1');
    error_reporting(E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED);
    mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
    
    set_error_handler(function ($severity, $message, $file, $line) {
      if (!(error_reporting() & $severity))
        return false;
    
      if (!headers_sent())
        http_response_code(500);
      echo json_encode(['ok' => false, 'type' => 'php_error', 'message' => $message, 'file' => $file, 'line' => $line]);
      exit;
    });
    set_exception_handler(function (Throwable $e) {
      http_response_code(500);
      echo json_encode(['ok' => false, 'type' => 'exception', 'message' => $e->getMessage(), 'where' => $e->getFile() . ':' . $e->getLine()]);
      exit;
    });
    
    /* ---------------- Config (token defined at top of file) ----------------
    */
    if (!defined('API_TOKEN')) {
        define('API_TOKEN', FLEET_SUMMARY_API_TOKEN);
    }
    
    /* ---------------- Paths ---------------- */
    $ROOT = dirname(__DIR__); // => public_html
    $LOG_DIR = __DIR__ . '/logs';
    $VENDOR_AUTOLOAD = false;
    $autoloads = [
      $ROOT . '/vendor/autoload.php',
      $ROOT . '/DriverDocs/vendor/autoload.php',
      __DIR__ . '/../vendor/autoload.php',
      __DIR__ . '/../../vendor/autoload.php'
    ];
    foreach ($autoloads as $p) {
      if (file_exists($p)) {
        $VENDOR_AUTOLOAD = $p;
        break;
      }
    }
    
    $DB_CONFIG = false;
    $configs = [
      $ROOT . '/conf/config.php',
      $ROOT . '/../conf/config.php',
      __DIR__ . '/../../conf/config.php',
      $ROOT . '/DriverDocs/conf/config.php'
    ];
    foreach ($configs as $p) {
      if (file_exists($p)) {
        $DB_CONFIG = $p;
        break;
      }
    }
    
    /* ---------------- Logger ---------------- */
    function log_debug(string $msg, array $ctx = []): void
    {
      $logDir = __DIR__ . '/logs';
      if (!is_dir($logDir)) {
        @mkdir($logDir, 0755, true);
      }
    
      $file = $logDir . '/fleet_summary_email_' . date('Y-m-d') . '.log';
      $line = '[' . date('Y-m-d H:i:s') . '] ' . $msg;
    
      if (!empty($ctx)) {
        $line .= ' | ' . json_encode($ctx, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
      }
      $line .= PHP_EOL;
    
      @file_put_contents($file, $line, FILE_APPEND);
    }
    
    /* ---------------- Auth ---------------- */
    $token = (string) ($_GET['token'] ?? '');
    if (!hash_equals(API_TOKEN, $token)) {
      log_debug('Unauthorized call', ['ip' => ($_SERVER['REMOTE_ADDR'] ?? ''), 'ua' => ($_SERVER['HTTP_USER_AGENT'] ?? '')]);
      http_response_code(401);
      echo json_encode(['ok' => false, 'message' => 'Unauthorized']);
      exit;
    }
    
    $isCron = true; // Always true because of the hash check above
    $isPost = ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_FILES['excel_file']));
    
    // Provide a standard response function for UI so we don't dump JSON on the user's screen
    // But as requested, append raw JSON block below the UI notification if we have a success message.
    function ui_render($token, $conn, $flashMessage = null, $flashType = 'success', $rawJsonData = null)
    {
      header('Content-Type: text/html; charset=utf-8');
      header('X-Frame-Options: SAMEORIGIN');

      // Handle file deletion from UI dashboard if requested
      if (isset($_GET['delete_sheet'])) {
        $delSheet = $_GET['delete_sheet'];
        $stmtDel = $conn->prepare("DELETE FROM fleet_summary_monthly WHERE sheet_name = ?");
        if ($stmtDel) {
          $stmtDel->bind_param('s', $delSheet);
          $stmtDel->execute();
          if ($stmtDel->affected_rows > 0) {
            $flashMessage = "Successfully deleted all records associated with file: " . htmlspecialchars($delSheet);
            $flashType = "success";
          } else {
            $flashMessage = "Could not find any records to delete for that file.";
            $flashType = "warning";
          }
        }
      }
    
      // Fetch recent uploads for UI table (optimized query performance bounding 60 days to prevent full-table grouping slowdowns)
      $recentUploads = [];
      $colCheck = $conn->query("SHOW COLUMNS FROM fleet_summary_monthly LIKE 'upload_source'");
      if ($colCheck && $colCheck->num_rows === 0) {
        $conn->query("ALTER TABLE fleet_summary_monthly ADD COLUMN upload_source VARCHAR(20) DEFAULT 'api' AFTER total_records");
      }
      $resHistory = $conn->query("
          SELECT sheet_name, email_subject, total_records, MAX(created_at) as latest_upload, COUNT(*) as rows_inserted,
                 COALESCE(MAX(upload_source), 'api') as upload_source
          FROM fleet_summary_monthly 
          WHERE created_at >= DATE_SUB(NOW(), INTERVAL 60 DAY)
          GROUP BY sheet_name, email_subject, total_records
          ORDER BY latest_upload DESC 
          LIMIT 20
      ");
      if ($resHistory) {
        while ($r = $resHistory->fetch_assoc()) {
          $recentUploads[] = $r;
        }
      }
      ?>
      <!DOCTYPE html>
      <html lang="en">
    
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Fleet Data Hub - SS Transways</title>
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link href="https://fonts.googleapis.com/css2?family=Josefin+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
        <!-- Bootstrap CSS -->
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
        <!-- Font Awesome -->
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
        <style>
          body {
            font-family: 'Josefin Sans', system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif;
            background: #f4f6fb;
            color: #333;
          }
    
          .app-header {
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: white;
            padding: 40px 0;
            margin-bottom: 40px;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
          }
    
          .upload-card {
            border: none;
            border-radius: 12px;
            box-shadow: 0 8px 30px rgba(0, 0, 0, 0.05);
            transition: transform 0.2s;
            background: #fff;
          }
    
          .upload-card:hover {
            transform: translateY(-2px);
          }
    
          .btn-primary {
            background-color: #198754;
            border-color: #198754;
            padding: 10px 20px;
            font-weight: 600;
            border-radius: 8px;
            box-shadow: 0 4px 10px rgba(25, 135, 84, 0.3);
          }
    
          .btn-primary:hover {
            background-color: #157347;
            border-color: #157347;
          }
    
          .table-custom {
            background: white;
            border-radius: 12px;
            overflow: hidden;
            box-shadow: 0 8px 30px rgba(0, 0, 0, 0.05);
          }
    
          .table-custom thead {
            background: #eef2f7;
            color: #444;
          }
    
          .table-custom th {
            font-weight: 600;
            text-transform: uppercase;
            font-size: 0.85rem;
            letter-spacing: 0.5px;
            border-bottom: 2px solid #dee2e6;
            padding: 12px 14px;
          }
    
          .table-custom td {
            vertical-align: middle;
            padding: 0;
          }
    
          .badge-custom {
            padding: 6px 10px;
            border-radius: 6px;
            font-weight: 500;
          }
    
          .btn-danger-light {
            background: #fee2e2;
            color: #ef4444;
            border: none;
            transition: all 0.2s;
          }
    
          .btn-danger-light:hover {
            background: #fecaca;
            color: #dc2626;
          }
          .table-layout-wide {
            width: 100%;
          }
          .table-layout-wide td, .table-layout-wide th {
            word-wrap: break-word;
          }
        </style>
      </head>
    
      <body>
    
        <?php
        $navbarPaths = [
          $_SERVER['DOCUMENT_ROOT'] . '/DriverDocs/includes/navbar.php',
          __DIR__ . '/../DriverDocs/includes/navbar.php',
          __DIR__ . '/../../DriverDocs/includes/navbar.php',
        ];
        $navbarIncluded = false;
        foreach ($navbarPaths as $p) {
          if (!empty($p) && is_file($p)) {
            include $p;
            $navbarIncluded = true;
            break;
          }
        }
        if (!$navbarIncluded): ?>
        <div class="app-header text-center">
          <div class="container">
            <h1 class="display-6 fw-bold"><i class="fa-solid fa-truck-fast me-2"></i> Fleet Journey Sync</h1>
            <p class="lead mb-0 opacity-75">Upload, manage, and monitor your monthly driver analytical data.</p>
          </div>
        </div>
        <?php endif; ?>
    
        <div class="container-fluid pb-5" style="width: 100%; padding: 2.5rem 2rem 0 2rem;">
          <?php if ($flashMessage): ?>
            <div class="alert alert-<?= htmlspecialchars($flashType) ?> alert-dismissible fade show shadow-sm mb-4 border-0"
              role="alert">
              <strong><i class="fa-solid <?= $flashType === 'success' ? 'fa-circle-check' : 'fa-triangle-exclamation' ?>"></i>
                Notification:</strong> <?= htmlspecialchars($flashMessage) ?>
              <?php if ($rawJsonData): ?>
                <div class="mt-3 bg-dark text-light p-3 rounded"
                  style="font-family: monospace; font-size: 0.85rem; overflow-wrap: break-word;">
                  <?= htmlspecialchars($rawJsonData) ?>
                </div>
              <?php endif; ?>
              <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
            </div>
          <?php endif; ?>
    
          <div class="row gx-4 justify-content-center">
            <!-- Upload Form -->
            <div class="col-12 mb-5">
              <div class="card upload-card h-100">
                <div class="card-body p-4 px-md-5">
                  <h5 class="card-title fw-bold text-dark mb-4"><i class="fa-solid fa-cloud-arrow-up text-primary me-2"></i>
                    Upload New Data</h5>
                  <form action="?token=<?= htmlspecialchars($token) ?>" method="POST" enctype="multipart/form-data" class="upload-form-single-row">
                    <div class="row align-items-end g-3">
                      <div class="col-md-8 col-lg-9">
                        <label class="form-label text-muted small fw-semibold text-uppercase">Choose file (.xls or .xlsx)</label>
                        <input type="file" name="excel_file" class="form-control form-control-lg" accept=".xls,.xlsx" required>
                      </div>
                      <div class="col-md-4 col-lg-3">
                        <button type="submit" class="btn btn-primary w-100"><i class="fa-solid fa-upload me-2"></i> Sync Database</button>
                      </div>
                    </div>
                  </form>
                </div>
              </div>
            </div>
    
            <!-- History Table -->
            <div class="col-12">
              <h5 class="fw-bold text-dark mb-3"><i class="fa-solid fa-clock-rotate-left text-primary me-2"></i> Synced Files
                History</h5>
              <div class="table-responsive table-custom">
                <table class="table mb-0 table-hover table-layout-wide">
                  <thead>
                    <tr>
                      <th class="text-center" style="min-width: 60px;">S.No</th>
                      <th style="min-width: 220px;">Filename</th>
                      <th style="min-width: 220px;">Subject</th>
                      <th style="min-width: 100px;">Source</th>
                      <th style="min-width: 140px;">Sync Date</th>
                      <th style="min-width: 100px;">Rows</th>
                      <th class="text-end" style="min-width: 90px;">Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    <?php if (empty($recentUploads)): ?>
                      <tr>
                        <td colspan="7" class="text-center text-muted py-4">No data has been synced yet. Upload your first Excel
                          file!</td>
                      </tr>
                    <?php else: ?>
                      <?php foreach ($recentUploads as $idx => $upl): 
                        $sno = $idx + 1;
                        $src = ($upl['upload_source'] ?? '') === 'manual' ? 'Manual' : 'API';
                      ?>
                        <tr>
                          <td class="text-muted text-center"><?= (int) $sno ?></td>
                          <td class="text-break" style="max-width: 320px;">
                            <span class="fw-semibold text-dark" title="<?= htmlspecialchars($upl['sheet_name']) ?>"><?= htmlspecialchars($upl['sheet_name']) ?></span>
                          </td>
                          <td class="text-break text-muted small" style="max-width: 320px;" title="<?= htmlspecialchars($upl['email_subject'] ?? '') ?>">
                            <?= htmlspecialchars($upl['email_subject'] ?? '—') ?>
                          </td>
                          <td><span class="badge <?= $src === 'Manual' ? 'bg-primary' : 'bg-secondary' ?> badge-custom"><?= htmlspecialchars($src) ?></span></td>
                          <td>
                            <span class="badge bg-light text-dark badge-custom border"><i class="fa-regular fa-calendar me-1"></i>
                              <?= date('d M Y, h:i A', strtotime($upl['latest_upload'])) ?>
                            </span>
                          </td>
                          <td>
                            <span class="badge bg-success badge-custom bg-opacity-10 text-success"><i
                                class="fa-solid fa-database"></i>
                              <?= (int) $upl['rows_inserted'] ?>
                            </span>
                            <?php if (!empty($upl['total_records'])): ?>
                              <div class="small text-muted mt-1">(Out of
                                <?= (int) $upl['total_records'] ?>)
                              </div>
                            <?php endif; ?>
                          </td>
                          <td class="text-end">
                            <a href="?token=<?= htmlspecialchars($token) ?>&delete_sheet=<?= urlencode($upl['sheet_name']) ?>"
                              class="btn btn-sm btn-danger-light"
                              onclick="return confirm('Are you sure you want to completely erase ALL records that came from this spreadsheet? This cannot be undone.')">
                              <i class="fa-solid fa-trash-can"></i> Delete
                            </a>
                          </td>
                        </tr>
                      <?php endforeach; ?>
                    <?php endif; ?>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
    
        <!-- Bootstrap JS Bundle -->
        <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
      </body>
    
      </html>
      <?php
      exit;
    }
    
    /* ---------------- UI Frontend Toggle ---------------- */
    // The UI is now handled by the ui_render function, which will be called after DB connection
    // or directly if ?ui is present.
    
    /* ---------------- Dependencies ---------------- */
    if (!$VENDOR_AUTOLOAD || !file_exists($VENDOR_AUTOLOAD)) {
      log_debug('Vendor autoload missing', ['path' => $VENDOR_AUTOLOAD]);
      throw new RuntimeException('Vendor autoload not found.');
    }
    require_once $VENDOR_AUTOLOAD;
    
    if (!function_exists('imap_open')) {
      log_debug('IMAP extension missing');
      throw new RuntimeException('PHP IMAP extension is not enabled (imap_open missing).');
    }
    
    use PhpOffice\PhpSpreadsheet\IOFactory;
    use PhpOffice\PhpSpreadsheet\Shared\Date as ExcelDate;
    
    /* ---------------- DB Config Settings Validated ---------------- */
    if (!$DB_CONFIG || !file_exists($DB_CONFIG)) {
      log_debug('DB config missing', ['path' => $DB_CONFIG]);
      throw new RuntimeException('DB config not found.');
    }
    
    /* ---------------- IMAP Settings ----------------
       Put these in env OR hardcode here (env recommended)
    */
    $IMAP_USER = getenv('HOSTINGER_EMAIL_USER') ?: 'dhirendrasingh@sstranswaysindia.com';
    $IMAP_PASS = getenv('HOSTINGER_EMAIL_PASS') ?: 'Comp1exity@1234';
    $IMAP_HOST = getenv('HOSTINGER_IMAP_HOST') ?: 'imap.hostinger.com';
    $IMAP_PORT = getenv('HOSTINGER_IMAP_PORT') ?: '993';
    $MAILBOX = '{' . $IMAP_HOST . ':' . $IMAP_PORT . '/imap/ssl}INBOX';
    
    if ($IMAP_USER === '' || $IMAP_PASS === '') {
      log_debug('Missing env vars HOSTINGER_EMAIL_USER/HOSTINGER_EMAIL_PASS');
      throw new RuntimeException('Missing env HOSTINGER_EMAIL_USER / HOSTINGER_EMAIL_PASS');
    }
    
    /* ---------------- Subject Match ---------------- */
    $SUBJECT_PREFIX = 'DRIVER JOURNEY SUMMARY MONTHLY REPORT';
    
    function normalizeSubject(string $s): string
    {
      $s = trim(preg_replace('/\s+/', ' ', $s));
      $s = preg_replace('/\s+as\s+on\s+.*$/i', '', $s);
      return trim((string) $s);
    }
    
    function decodePartBody($imap, int $msgNo, string $partNo, int $encoding): string
    {
      $data = imap_fetchbody($imap, $msgNo, $partNo);
      switch ($encoding) {
        case 3:
          return base64_decode($data) ?: '';
        case 4:
          return quoted_printable_decode($data);
        default:
          return $data;
      }
    }
    
    function getAttachments($imap, int $msgNo): array
    {
      $structure = imap_fetchstructure($imap, $msgNo);
      $out = [];
    
      $walk = function ($struct, string $prefix) use (&$walk, $imap, $msgNo, &$out) {
        if (empty($struct->parts) || !is_array($struct->parts))
          return;
    
        foreach ($struct->parts as $i => $part) {
          $partNo = ($prefix === '') ? (string) ($i + 1) : ($prefix . '.' . ($i + 1));
          $filename = '';
    
          if (!empty($part->dparameters)) {
            foreach ($part->dparameters as $p) {
              if (strtolower((string) ($p->attribute ?? '')) === 'filename') {
                $filename = (string) ($p->value ?? '');
              }
            }
          }
          if ($filename === '' && !empty($part->parameters)) {
            foreach ($part->parameters as $p) {
              if (strtolower((string) ($p->attribute ?? '')) === 'name') {
                $filename = (string) ($p->value ?? '');
              }
            }
          }
    
          if ($filename !== '') {
            $out[] = [
              'partNo' => $partNo,
              'filename' => $filename,
              'encoding' => (int) ($part->encoding ?? 0),
            ];
          }
    
          if (!empty($part->parts) && is_array($part->parts)) {
            $walk($part, $partNo);
          }
        }
      };
    
      $walk($structure, '');
      return $out;
    }
    
    function parseExcelDate($v): ?string
    {
      if ($v === null || $v === '')
        return null;
    
      if (is_numeric($v)) {
        try {
          $dt = ExcelDate::excelToDateTimeObject((float) $v);
          return $dt->format('Y-m-d H:i:s');
        } catch (Throwable $e) {
        }
      }
    
      $s = trim((string) $v);
      if ($s === '')
        return null;
    
      $fmts = [
        'd-m-Y H:i:s',
        'd/m/Y H:i:s',
        'd-m-Y H:i',
        'd/m/Y H:i',
        'Y-m-d H:i:s',
        'Y-m-d H:i',
        'd-m-Y',
        'd/m/Y',
        'Y-m-d'
      ];
      foreach ($fmts as $f) {
        $dt = DateTime::createFromFormat($f, $s);
        if ($dt instanceof DateTime)
          return $dt->format('Y-m-d H:i:s');
      }
      $ts = strtotime($s);
      if ($ts !== false)
        return date('Y-m-d H:i:s', $ts);
    
      return null;
    }
    
    function headerKey(string $s): string
    {
      $s = strtolower(trim($s));
      $s = preg_replace('/\s+/', ' ', $s);
      $s = preg_replace('/[^a-z0-9 ]+/', '', $s);
      return trim($s);
    }
    
    function findHeaderRowAndMap(array $rows, string $sheetName = ''): array
    {
      $aliases = [
        'entity_name' => ['entity name', 'entity', 'company'],
        'vehicle_no' => ['vehicle no', 'vehicle', 'asset id', 'truck no'],
        'driver_id_excel' => ['driver id', 'drv id'],
        'driver_name' => ['driver name', 'driver', 'drivers'],
        'card_id' => ['card id', 'card'],
        'dt_start' => ['dt start', 'start time', 'report at'],
        'dt_end' => ['dt end', 'end time'],
        'duration' => ['duration', 'total duration'],
        'moving_min' => ['moving min', 'moving duration', 'moving time'],
        'stop_min' => ['stop min', 'halt', 'halt duration'],
        'distance' => ['distance', 'distance km', 'km'],
        'acceleration' => ['acceleration', 'accel', 'accel cnt'],
        'deceleration' => ['deceleration', 'daccel', 'daccel cnt', 'decel'],
        'night_drive' => ['night drive', 'night drv', 'night'],
        'over_speed' => ['over speed', 'overspeed'],
      ];
    
      $maxScan = min(60, count($rows));
      for ($r = 0; $r < $maxScan; $r++) {
        $norm = array_map(fn($x) => headerKey((string) $x), (array) $rows[$r]);
    
        $hasVehicle = false;
        $hasStart = false;
        foreach ($norm as $cell) {
          if (strpos($cell, 'asset') !== false || strpos($cell, 'vehicle') !== false)
            $hasVehicle = true;
          if (strpos($cell, 'start') !== false || strpos($cell, 'report') !== false)
            $hasStart = true;
        }
        if (!$hasVehicle || !$hasStart)
          continue;
    
        $map = [];
        foreach ($norm as $cIdx => $cell) {
          foreach ($aliases as $key => $list) {
            foreach ($list as $alias) {
              if ($cell === headerKey($alias)) {
                $map[$key] = $cIdx;
                break;
              }
            }
          }
        }
    
        if (isset($map['vehicle_no']) && isset($map['dt_start']))
          return [$r, $map];
      }
    
      throw new RuntimeException("Could not detect header row/columns in Excel file: {$sheetName}");
    }
    
    function toIntOrNull($v): ?int
    {
      if ($v === null || $v === '')
        return null;
      if (is_numeric($v))
        return (int) round((float) $v);
      $s = preg_replace('/[^0-9\-]/', '', (string) $v);
      if ($s === '' || $s === '-')
        return null;
      return (int) $s;
    }
    function toDecOrNull($v): ?string
    {
      if ($v === null || $v === '')
        return null;
      if (is_numeric($v))
        return number_format((float) $v, 2, '.', '');
      $s = str_replace([',', ' '], '', (string) $v);
      $s = preg_replace('/[^0-9\.\-]/', '', $s);
      if ($s === '' || $s === '-' || $s === '.')
        return null;
      return number_format((float) $s, 2, '.', '');
    }
    
    /* ---------------- Prevent IMAP logic on GET UI Loads ---------------- */
    if (hash_equals(FLEET_SUMMARY_API_TOKEN, $token) && $_SERVER['REQUEST_METHOD'] === 'GET' && !isset($_GET['corn_bypass']) && empty($_GET['test_imap'])) {
      require_once $DB_CONFIG;
      if (!isset($conn) || !$conn instanceof mysqli) {
        throw new RuntimeException('Database connection ($conn) not available');
      }
      $conn->set_charset('utf8mb4');
      // Render UI and Stop Parsing!
      ui_render($token, $conn);
      exit;
    }
    
    /* ---------------- Optional: Test IMAP connection only (for debugging on Hostinger) ---------------- */
    if (!empty($_GET['test_imap'])) {
      header('Content-Type: application/json; charset=utf-8');
      $mailbox1 = '{' . $IMAP_HOST . ':' . $IMAP_PORT . '/imap/ssl}INBOX';
      $imap = @imap_open($mailbox1, $IMAP_USER, $IMAP_PASS);
      if ($imap) {
        imap_close($imap);
        echo json_encode(['ok' => true, 'message' => 'IMAP connection successful']);
        exit;
      }
      $mailbox2 = '{' . $IMAP_HOST . ':' . $IMAP_PORT . '/imap/ssl/novalidate-cert}INBOX';
      $imap2 = @imap_open($mailbox2, $IMAP_USER, $IMAP_PASS);
      if ($imap2) {
        imap_close($imap2);
        echo json_encode(['ok' => true, 'message' => 'IMAP connection OK (using novalidate-cert)']);
        exit;
      }
      $lastErr = imap_last_error();
      log_debug('IMAP test failed', ['err' => $lastErr]);
      echo json_encode(['ok' => false, 'message' => 'IMAP connection failed. Enable PHP IMAP extension on Hostinger; check email/password.', 'debug' => $lastErr ?: 'No error string']);
      exit;
    }
    
    /* ---------------- Database Connection execution DEFERRED past slow layer ---------------- */
    
    /* ---------------- Run IMAP Checks for Cron (use ?token=xxx&corn_bypass=1) ---------------- */
    try {
    log_debug('Start fetch', ['imap_host' => $IMAP_HOST, 'user' => $IMAP_USER]);
    
    $MAILBOX_BASE = '{' . $IMAP_HOST . ':' . $IMAP_PORT . '/imap/ssl}';
    $imap = @imap_open($MAILBOX_BASE, $IMAP_USER, $IMAP_PASS);
    if (!$imap) {
      $MAILBOX_BASE = '{' . $IMAP_HOST . ':' . $IMAP_PORT . '/imap/ssl/novalidate-cert}';
      $imap = @imap_open($MAILBOX_BASE, $IMAP_USER, $IMAP_PASS);
    }
    if (!$imap) {
      $errors = imap_errors();
      $lastErr = imap_last_error();
      log_debug('IMAP open failed', ['err' => $lastErr, 'errors' => $errors]);
      throw new RuntimeException('IMAP login failed: ' . ($lastErr ?: 'Unknown error. Enable PHP IMAP extension on Hostinger and check email/password.'));
    }
    
    $boxes = @imap_getmailboxes($imap, $MAILBOX_BASE, '*');
    imap_close($imap);
    
    $allEmails = [];
    if ($boxes) {
      foreach ($boxes as $box) {
        if (stripos($box->name, 'Trash') !== false || stripos($box->name, 'Spam') !== false || stripos($box->name, 'Bin') !== false) {
          continue;
        }
    
        $imapBox = @imap_open($box->name, $IMAP_USER, $IMAP_PASS);
        if (!$imapBox)
          continue;
    
        $search = 'SUBJECT "' . addslashes($SUBJECT_PREFIX) . '"';
        $emails = imap_search($imapBox, $search);
    
        if ($emails && is_array($emails)) {
          foreach ($emails as $msgNo) {
            $overview = imap_fetch_overview($imapBox, (string) $msgNo, 0);
            if (!empty($overview[0])) {
              $allEmails[] = [
                'mailbox' => $box->name,
                'msgNo' => $msgNo,
                'udate' => $overview[0]->udate ?? 0,
                'subject' => $overview[0]->subject ?? ''
              ];
            }
          }
        }
        imap_close($imapBox);
      }
    }
    
    if (count($allEmails) === 0) {
      log_debug('No matching emails found');
      echo json_encode(['ok' => true, 'message' => 'No matching emails found']);
      exit;
    }
    
    usort($allEmails, function ($a, $b) {
      return $b['udate'] <=> $a['udate'];
    });
    /* ---------------- Establish late DB Connection ---------------- */
    require_once $DB_CONFIG; // provides $conn
    
    if (!isset($conn) || !$conn instanceof mysqli) {
      log_debug('DB connection not available');
      throw new RuntimeException('Database connection ($conn) not available');
    }
    if (!$conn->ping()) {
      require $DB_CONFIG; // Re-attempt connection fallback just in case
    }
    $conn->set_charset('utf8mb4');
    
    $createTableSql = "
    CREATE TABLE IF NOT EXISTS `fleet_summary_monthly` (
      `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
      `entity_name` varchar(255) DEFAULT NULL,
      `vehicle_id` bigint(20) unsigned NOT NULL,
      `driver_id` bigint(20) unsigned DEFAULT NULL,
      `driver_id_excel` varchar(50) DEFAULT NULL,
      `driver_name` varchar(255) DEFAULT NULL,
      `card_id` varchar(50) DEFAULT NULL,
      `dt_start` datetime DEFAULT NULL,
      `dt_end` datetime DEFAULT NULL,
      `duration` varchar(50) DEFAULT NULL,
      `moving_min` int(11) DEFAULT NULL,
      `stop_min` int(11) DEFAULT NULL,
      `distance` decimal(10,2) DEFAULT NULL,
      `acceleration` int(11) DEFAULT NULL,
      `deceleration` int(11) DEFAULT NULL,
      `night_drive` int(11) DEFAULT NULL,
      `over_speed` int(11) DEFAULT NULL,
      `sheet_name` varchar(255) NOT NULL,
      `email_subject` varchar(500) DEFAULT NULL,
      `total_records` int(11) DEFAULT NULL,
      `upload_source` varchar(20) DEFAULT 'api',
      `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
      PRIMARY KEY (`id`),
      UNIQUE KEY `idx_fleet_month_sheet_veh_dt` (`sheet_name`,`vehicle_id`,`dt_start`),
      KEY `idx_fleet_month_veh` (`vehicle_id`),
      KEY `idx_fleet_month_dt` (`dt_start`),
      KEY `idx_fleet_month_drv` (`driver_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ";
    $conn->query($createTableSql);
    $colCheck = $conn->query("SHOW COLUMNS FROM fleet_summary_monthly LIKE 'upload_source'");
    if ($colCheck && $colCheck->num_rows === 0) {
      $conn->query("ALTER TABLE fleet_summary_monthly ADD COLUMN upload_source VARCHAR(20) DEFAULT 'api' AFTER total_records");
    }
    
    $stmtCheckFile = $conn->prepare("SELECT 1 FROM fleet_summary_monthly WHERE sheet_name = ? LIMIT 1");
    
    function findDriverIdFuzzy($conn, $searchName)
    {
      static $dmap = null;
      if ($dmap === null) {
        $dmap = [];
        $r = $conn->query("SELECT id, name FROM drivers");
        if ($r) {
          while ($row = $r->fetch_assoc()) {
            $dmap[(int) $row['id']] = strtolower(trim($row['name']));
          }
        }
      }
    
      $s = strtolower(trim($searchName));
      if ($s === '')
        return null;
    
      // Exact match
      foreach ($dmap as $id => $n) {
        if ($n === $s)
          return $id;
      }
    
      // Common aliases requested
      $aliases = [
        'indra bahadur' => 'indra bahadur yadav',
        'manos goud' => 'manoj gaur',
        'budhadhosh gautam' => 'buddhghosh gautam'
      ];
      if (isset($aliases[$s])) {
        $s = $aliases[$s];
        foreach ($dmap as $id => $n) {
          if ($n === $s)
            return $id;
        }
      }
    
      // Substring Match (e.g. "INDRA BAHADUR" is found in "Indra Bahadur yadav")
      foreach ($dmap as $id => $n) {
        if ($n !== '' && (strpos($n, $s) !== false || strpos($s, $n) !== false)) {
          return $id;
        }
      }
    
      return null;
    }
    
    $vehMap = [];
    $resVeh = $conn->query("SELECT id, vehicle_no FROM vehicles");
    if ($resVeh) {
      while ($r = $resVeh->fetch_assoc()) {
        $vClean = strtoupper(preg_replace('/\s+/', '', $r['vehicle_no']));
        $vehMap[$vClean] = (int) $r['id'];
      }
    }
    
    $sql = "
    INSERT INTO fleet_summary_monthly
    (entity_name, vehicle_id, driver_id, driver_id_excel, driver_name, card_id, 
     dt_start, dt_end, duration, moving_min, stop_min, 
     distance, acceleration, deceleration, night_drive, over_speed, sheet_name, email_subject, total_records, upload_source)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ";
    /* NOTE: We removed IGNORE because we'll try to insert, and maybe we should add IGNORE if desired */
    $sql = str_replace("INSERT ", "INSERT IGNORE ", $sql);
    $stmtIns = $conn->prepare($sql);
    
    function processExcelFile($tmpPath, $sheetName, $subjectDecoded, $subjectNorm, $uploadSource = 'api')
    {
      global $stmtCheckFile, $stmtIns, $vehMap, $conn;
    
      $stmtCheckFile->bind_param('s', $sheetName);
      $stmtCheckFile->execute();
      if ($stmtCheckFile->get_result()->fetch_assoc()) {
        log_debug('Duplicate file skipped', ['filename' => $sheetName, 'subject' => $subjectDecoded]);
        return ['ok' => true, 'message' => 'Duplicate file skipped (already processed)', 'sheet' => $sheetName];
      }
    
      $spreadsheet = IOFactory::load($tmpPath);
      $sheet = $spreadsheet->getSheet(0);
      $rows = $sheet->toArray(null, true, true, false);
    
      try {
        [$headerRowIdx, $col] = findHeaderRowAndMap($rows, $sheetName);
        log_debug('Header detected', ['headerRowIdx' => $headerRowIdx, 'colMap' => $col, 'sheet' => $sheetName]);
      } catch (Throwable $e) {
        log_debug('Error parsing file headers', ['sheet' => $sheetName, 'subject' => $subjectDecoded, 'error' => $e->getMessage()]);
        return [
          'ok' => false,
          'type' => 'exception',
          'message' => $e->getMessage(),
          'filename' => $sheetName,
          'email_subject' => $subjectDecoded
        ];
      }
    
      $inserted = 0;
      $skipped = 0;
      $skippedReasons = [];
    
      $totalRecords = count($rows) - $headerRowIdx - 1;
      if ($totalRecords < 0) {
        $totalRecords = 0;
      }
    
      for ($i = $headerRowIdx + 1; $i < count($rows); $i++) {
        $row = (array) $rows[$i];
    
        $vehicleNo = trim((string) ($row[$col['vehicle_no']] ?? ''));
        if ($vehicleNo === '') {
          $skipped++;
          $skippedReasons['empty_vehicle'] = ($skippedReasons['empty_vehicle'] ?? 0) + 1;
          continue;
        }
    
        $vClean = strtoupper(preg_replace('/\s+/', '', $vehicleNo));
        if (!isset($vehMap[$vClean])) {
          $skipped++;
          $skippedReasons['unknown_vehicle_' . $vehicleNo] = ($skippedReasons['unknown_vehicle_' . $vehicleNo] ?? 0) + 1;
          continue;
        }
        $vehicleId = $vehMap[$vClean];
    
        $entityName = isset($col['entity_name']) ? trim((string) ($row[$col['entity_name']] ?? '')) : null;
        $driverIdEx = isset($col['driver_id_excel']) ? trim((string) ($row[$col['driver_id_excel']] ?? '')) : null;
        $driverName = isset($col['driver_name']) ? trim((string) ($row[$col['driver_name']] ?? '')) : null;
        $cardId = isset($col['card_id']) ? trim((string) ($row[$col['card_id']] ?? '')) : null;
    
        $dtStartCol = $col['dt_start'] ?? null;
        $dtStartRaw = $dtStartCol !== null ? ($row[$dtStartCol] ?? 'null') : 'missing_col';
        $dtStart = $dtStartCol !== null ? parseExcelDate($row[$dtStartCol] ?? null) : null;
    
        if (!$dtStart) {
          $skipped++;
          $skippedReasons['invalid_date_start_' . $dtStartRaw] = ($skippedReasons['invalid_date_start_' . $dtStartRaw] ?? 0) + 1;
          continue;
        }
    
        $dtEndCol = $col['dt_end'] ?? null;
        $dtEnd = $dtEndCol !== null ? parseExcelDate($row[$dtEndCol] ?? null) : null;
    
        $duration = isset($col['duration']) ? trim((string) ($row[$col['duration']] ?? '')) : null;
    
        $driverId = null;
        if ($driverName !== '' && $driverName !== null) {
          $driverId = findDriverIdFuzzy($conn, $driverName);
        }
    
        $movingMin = isset($col['moving_min']) ? toIntOrNull($row[$col['moving_min']] ?? null) : null;
        $stopMin = isset($col['stop_min']) ? toIntOrNull($row[$col['stop_min']] ?? null) : null;
        $distance = isset($col['distance']) ? toDecOrNull($row[$col['distance']] ?? null) : null;
    
        $accel = isset($col['acceleration']) ? toIntOrNull($row[$col['acceleration']] ?? null) : null;
        $decel = isset($col['deceleration']) ? toIntOrNull($row[$col['deceleration']] ?? null) : null;
        $nightDr = isset($col['night_drive']) ? toIntOrNull($row[$col['night_drive']] ?? null) : null;
        $overSpd = isset($col['over_speed']) ? toIntOrNull($row[$col['over_speed']] ?? null) : null;
    
        $stmtIns->bind_param(
          'siissssssiidiiiissis',
          $entityName,
          $vehicleId,
          $driverId,
          $driverIdEx,
          $driverName,
          $cardId,
          $dtStart,
          $dtEnd,
          $duration,
          $movingMin,
          $stopMin,
          $distance,
          $accel,
          $decel,
          $nightDr,
          $overSpd,
          $sheetName,
          $subjectDecoded,
          $totalRecords,
          $uploadSource
        );
    
        $stmtIns->execute();
        if ($stmtIns->affected_rows > 0) {
          $inserted++;
        } else {
          $skipped++;
          $skippedReasons['duplicate_key_db'] = ($skippedReasons['duplicate_key_db'] ?? 0) + 1;
        }
      }
    
      log_debug('Import done', [
        'sheet' => $sheetName,
        'subject' => $subjectDecoded,
        'inserted' => $inserted,
        'skipped' => $skipped,
        'skipped_reasons' => $skippedReasons
      ]);
    
      return [
        'ok' => true,
        'message' => 'Processed Excel Data',
        'email_subject' => $subjectDecoded,
        'normalized_subject' => $subjectNorm,
        'sheet' => $sheetName,
        'inserted_or_updated_rows' => $inserted,
        'skipped_rows' => $skipped,
        'skipped_reasons' => $skippedReasons
      ];
    }
    
    
    /* ---------------- API Direct Post File Upload ---------------- */
    if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_FILES['excel_file'])) {
      if (!isset($_FILES['excel_file']) || $_FILES['excel_file']['error'] !== UPLOAD_ERR_OK) {
        if (hash_equals(FLEET_SUMMARY_API_TOKEN, $token)) {
          ui_render($token, $conn, 'Missing or invalid excel_file payload details.', 'danger');
        } else {
          http_response_code(400);
          echo json_encode(['ok' => false, 'message' => 'Missing or invalid excel_file in POST payload']);
          exit;
        }
      }
    
      $tmpPath = $_FILES['excel_file']['tmp_name'];
      $sheetName = $_FILES['excel_file']['name'];
    
      $ext = strtolower(pathinfo($sheetName, PATHINFO_EXTENSION));
      if (!in_array($ext, ['xls', 'xlsx'])) {
        if ($isCron) {
          ui_render($token, $conn, 'Invalid file extension. Please upload strictly .xls or .xlsx formats ONLY.', 'danger');
        } else {
          http_response_code(400);
          echo json_encode(['ok' => false, 'message' => 'Invalid file extension. Please upload .xls or .xlsx']);
          exit;
        }
      }
    
      $subjectDecoded = 'API File Upload: ' . $sheetName;
      $subjectNorm = normalizeSubject($subjectDecoded);
    
      $response = processExcelFile($tmpPath, $sheetName, $subjectDecoded, $subjectNorm, 'manual');
    
      // Distinguish visual fallback for humans via form uploads
      if (hash_equals(FLEET_SUMMARY_API_TOKEN, $token)) {
        if ($response['ok']) {
          $msg = "Excel has been successfully uploaded! Inserted {$response['inserted_or_updated_rows']} rows. Skipped: {$response['skipped_rows']}";
          ui_render($token, $conn, $msg, 'success', json_encode($response));
        } else {
          ui_render($token, $conn, "Upload failed system check -> " . ($response['message'] ?? 'Unknown Error'), 'danger');
        }
      } else {
        echo json_encode($response);
        exit;
      }
    }
    
    /* ---------------- Email IMAP Fetching Logic ---------------- */
    $processedAny = false;
    
    foreach ($allEmails as $emailMeta) {
      $msgNo = (int) $emailMeta['msgNo'];
      $subjectDecoded = imap_utf8((string) $emailMeta['subject']);
      $subjectNorm = normalizeSubject($subjectDecoded);
    
      if (stripos($subjectNorm, $SUBJECT_PREFIX) === false) {
        continue;
      }
    
      $imap = @imap_open($emailMeta['mailbox'], $IMAP_USER, $IMAP_PASS);
      if (!$imap)
        continue;
    
      $attachments = getAttachments($imap, $msgNo);
      $excelAtt = null;
      foreach ($attachments as $att) {
        $fn = strtolower((string) $att['filename']);
        if (preg_match('/\.(xls|xlsx)$/i', $fn)) {
          $excelAtt = $att;
          break;
        }
      }
    
      if (!$excelAtt)
        continue;
    
      $sheetName = (string) $excelAtt['filename'];
    
      $stmtCheckFile->bind_param('s', $sheetName);
      $stmtCheckFile->execute();
      if ($stmtCheckFile->get_result()->fetch_assoc()) {
        log_debug('Duplicate file skipped', ['filename' => $sheetName, 'subject' => $subjectDecoded]);
        // Optionally mark seen even if skipped, or leave it. We leave it as is.
        continue;
      }
    
      // Found an unprocessed attachment, download body
      $bytes = decodePartBody($imap, $msgNo, $excelAtt['partNo'], $excelAtt['encoding']);
    
      $tmpDir = sys_get_temp_dir();
      $safeName = preg_replace('/[^a-zA-Z0-9\.\-_]+/', '_', $sheetName);
      $tmpPath = $tmpDir . '/fleet_summary_' . time() . '_' . $safeName;
    
      if (file_put_contents($tmpPath, $bytes) === false) {
        log_debug('Failed to write temp attachment', ['tmpPath' => $tmpPath]);
        continue;
      }
    
      $response = processExcelFile($tmpPath, $sheetName, $subjectDecoded, $subjectNorm, 'api');

      if ($response['ok']) {
        imap_setflag_full($imap, (string) $msgNo, "\\Seen");
      } else {
        // we still mark seen to avoid endless retrying of the same erroneous email
        imap_setflag_full($imap, (string) $msgNo, "\\Seen");
      }
    
      @unlink($tmpPath);
      echo json_encode($response);
    
      imap_close($imap);
      $processedAny = true;
      break; // Remove this to loop through ALL unprocessed, keep for one-at-a-time (cron friendly)
    }
    
    if (!$processedAny) {
      echo json_encode([
        'ok' => true,
        'message' => 'All matching emails are already processed.'
      ]);
    }
    } catch (Throwable $e) {
      log_debug('Email check failed', ['message' => $e->getMessage(), 'file' => $e->getFile(), 'line' => $e->getLine()]);
      if (!headers_sent()) {
        header('Content-Type: application/json; charset=utf-8');
        http_response_code(500);
      }
      echo json_encode([
        'ok' => false,
        'message' => $e->getMessage(),
        'hint' => 'Use ?token=YOUR_TOKEN&corn_bypass=1 to run email check. On Hostinger enable PHP IMAP extension and set HOSTINGER_EMAIL_USER / HOSTINGER_EMAIL_PASS if needed.'
      ]);
    }
    exit;

// ——— JSON response below ———
header('Content-Type: application/json; charset=utf-8');

// Prefer one config path; add more if your deployment differs
$configPaths = [
    __DIR__ . '/../conf/config.php',
    __DIR__ . '/../../conf/config.php',
];
$conn = null;
foreach ($configPaths as $path) {
    if (is_file($path)) {
        require_once $path;
        break;
    }
}

if (!isset($conn) || !($conn instanceof mysqli)) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'DB not available']);
    exit;
}

mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

// Optional: require API key (set to true to enforce X-API-Key header)
$requireAuth = false;
if ($requireAuth && function_exists('getSettingValue')) {
    $sharedKey = getSettingValue($conn, 'api.shared_key');
    $incoming  = $_SERVER['HTTP_X_API_KEY'] ?? '';
    if (!$sharedKey || !hash_equals(trim((string)$sharedKey), trim($incoming))) {
        http_response_code(401);
        echo json_encode(['ok' => false, 'error' => 'Unauthorized']);
        exit;
    }
}

// Cache for 5 minutes to avoid heavy DB load on every page hit
$cacheMinutes = 5;
$cacheDir = ($_SERVER['DOCUMENT_ROOT'] ?? __DIR__) . '/DriverDocs/cache';
$cacheFile = $cacheDir . '/fleet_summary_email_fetch.json';
$useCache = ($cacheMinutes > 0 && $cacheDir !== '');

if ($useCache && is_dir($cacheDir) && is_file($cacheFile)) {
    $age = time() - filemtime($cacheFile);
    if ($age < $cacheMinutes * 60) {
        header('Cache-Control: public, max-age=' . max(0, ($cacheMinutes * 60) - $age));
        readfile($cacheFile);
        exit;
    }
}

// Single bounded query — LIMIT keeps response fast; ORDER BY 1 uses first column (e.g. month)
$maxMonths = 24;
$sql = "SELECT * FROM fleet_summary_monthly ORDER BY 1 DESC LIMIT " . (int) $maxMonths;
$result = $conn->query($sql);

$rows = [];
if ($result) {
    while ($row = $result->fetch_assoc()) {
        $rows[] = $row;
    }
    $result->free();
}

$payload = [
    'ok'    => true,
    'count' => count($rows),
    'data'  => $rows,
];

$json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

if ($useCache && $json !== false) {
    if (!is_dir($cacheDir)) {
        @mkdir($cacheDir, 0775, true);
    }
    if (is_dir($cacheDir)) {
        @file_put_contents($cacheFile, $json);
    }
}

header('Cache-Control: private, max-age=' . ($cacheMinutes * 60));
echo $json;
