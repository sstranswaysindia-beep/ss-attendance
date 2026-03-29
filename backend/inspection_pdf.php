<?php
// public_html/DriverDocs/api/inspection_pdf.php
declare(strict_types=1);

if (session_status() === PHP_SESSION_NONE) session_start();

/* Long-running safety (same as bilty) */
ignore_user_abort(true);
set_time_limit(0);
ini_set('max_execution_time', '0');
ini_set('memory_limit', '512M');

ini_set('display_errors', 0);
ini_set('display_startup_errors', 0);
error_reporting(E_ALL);

header('Content-Type: application/json; charset=UTF-8');
if (ob_get_level()) { ob_clean(); }
header('X-Accel-Buffering: no');

require __DIR__ . '/_logger.php';
$log = ApiLogger::new('inspection_pdf');
$traceId = $log->id();

/* --- error guards --- */
set_error_handler(function($severity, $message, $file, $line) use ($log) {
  if (!(error_reporting() & $severity)) return true;
  $level = in_array($severity, [E_WARNING, E_USER_WARNING]) ? 'WARN' : 'INFO';
  $log->log($level, 'php:error', compact('severity','message','file','line'));
  return true;
});
register_shutdown_function(function() use ($log, $traceId) {
  $e = error_get_last();
  if ($e && in_array($e['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR])) {
    $log->log('ERROR', 'php:fatal', $e);
    echo json_encode(['success'=>false,'message'=>'Fatal server error','trace_id'=>$traceId]);
  }
});

/* --- require helpers like in bilty --- */
function must_have(string $path, ApiLogger $log, string $label) {
  if (!file_exists($path)) {
    $log->log('ERROR', 'include:missing', ['label'=>$label, 'path'=>$path]);
    http_response_code(500);
    echo json_encode(['success'=>false,'message'=>"Missing dependency: $label",'trace_id'=>$log->id()]);
    exit;
  }
}

$authPath     = __DIR__ . '/../../includes/auth.php';
$configPath   = __DIR__ . '/../../../conf/config.php';
$gdmPath      = __DIR__ . '/../classes/GoogleDriveManager.php';
$helpersPath  = __DIR__ . '/helpers.php';
must_have($authPath,   $log, 'includes/auth.php');
must_have($configPath, $log, 'conf/config.php');
must_have($gdmPath,    $log, 'classes/GoogleDriveManager.php');
must_have($helpersPath,$log, 'api/helpers.php');

require_once $authPath;
require_once $configPath;   // $conn
require_once $gdmPath;      // GoogleDriveManager
require_once $helpersPath;  // getSettingValue()

if (isset($GLOBALS['conn']) && $GLOBALS['conn'] instanceof mysqli) {
  $GLOBALS['conn']->set_charset('utf8mb4');
}

/* --- Composer autoload (Drive + Docs) --- */
$vendorCandidates = [
  __DIR__ . '/../vendor/autoload.php',
  __DIR__ . '/../../vendor/autoload.php',
];
$autoloadHit = null;
foreach ($vendorCandidates as $p) { if (file_exists($p)) { require_once $p; $autoloadHit = $p; break; } }
if (!$autoloadHit || !class_exists(\Google\Service\Drive::class) || !class_exists(\Google\Service\Docs::class)) {
  http_response_code(500);
  echo json_encode(['success'=>false,'message'=>'Google API client not installed. Run: composer require google/apiclient','trace_id'=>$traceId]);
  exit;
}

/* ============== Self-test (like you used) ============== */
if (isset($_GET['selftest'])) {
  header('Content-Type: text/plain; charset=utf-8');
  echo "== Tyre Inspection PDF Self-Test ==\n\n";
  $svcPath = __DIR__ . '/../../secure_store/google-service.json';
  echo "[1] Autoload: " . ($autoloadHit ? "OK ($autoloadHit)\n" : "MISSING\n");
  echo "[2] Service JSON: " . (is_file($svcPath) ? "OK\n" : "MISSING\n");
  if (is_file($svcPath)) {
    $j = json_decode(file_get_contents($svcPath), true);
    echo "    client_email: " . ($j['client_email'] ?? 'N/A') . "\n";
  }
  $templateId = getSettingValue($GLOBALS['conn'], 'tyre_template_doc_id') ?: '';
  $templateId = trim((string)($_GET['template'] ?? $templateId));
  echo "[3] Template ID: " . ($templateId ?: "NOT SET") . "\n";
  $id = filter_var($_GET['id'] ?? null, FILTER_VALIDATE_INT);
  echo "[4] Inspection ID: " . ($id ?: 'MISSING (?id=)') . "\n";
  if ($id) {
    try {
      $st = $GLOBALS['conn']->prepare("SELECT id FROM tyre_inspections WHERE id=?");
      $st->bind_param('i', $id); $st->execute();
      $ok = (bool)$st->get_result()->fetch_assoc(); $st->close();
      echo "    DB lookup: " . ($ok ? "OK\n" : "NOT FOUND\n");
    } catch (Throwable $e) { echo "    DB error: ".$e->getMessage()."\n"; }
  }
  echo "\nShare the Google Doc template with the service account email above.\n";
  exit;
}

/* --- auth --- */
try { checkRole(['admin','supervisor']); }
catch (Throwable $e) { http_response_code(403); echo json_encode(['success'=>false,'message'=>'Forbidden','trace_id'=>$traceId]); exit; }

/* --- method + CSRF --- */
try {
  if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    http_response_code(405);
    echo json_encode(['success'=>false,'message'=>'Method not allowed','trace_id'=>$traceId]); exit;
  }
  $posted = (string)($_POST['csrf_token'] ?? '');
  $stored = (string)($_SESSION['csrf_token'] ?? '');
  if ($posted === '' || $stored === '' || !hash_equals($stored, $posted)) {
    http_response_code(400);
    echo json_encode(['success'=>false,'message'=>'Invalid CSRF','trace_id'=>$traceId]); exit;
  }

  /* -------- inputs -------- */
  $inspectionId = filter_var($_POST['inspection_id'] ?? null, FILTER_VALIDATE_INT);
  if (!$inspectionId) { http_response_code(400); echo json_encode(['success'=>false,'message'=>'inspection_id required','trace_id'=>$traceId]); exit; }

  $overwrite       = isset($_POST['overwrite']) ? ((string)$_POST['overwrite'] === '1') : true;
  $enableSharing   = isset($_POST['share_public']) ? ((string)$_POST['share_public'] === '1') : false;
  $cleanupDoc      = !isset($_POST['cleanup_doc']) || ((string)$_POST['cleanup_doc'] === '1'); // default true

  // Settings (root + template), with sane defaults
  $DEFAULT_ROOT   = '1USJE6SZe1sqjSdqvWEqJEXnLIYzlVQzm'; // optional: replace or set in settings
  $DEFAULT_TPL_ID = '1llIiZx4sf-nNfedz2u0gVY-qWV8gdFFrJ6cH7iqBCfc';       // replace with your Doc ID or store in settings

  $rootFolder  = trim((string)($_POST['folder_override'] ?? '')) ?: (getSettingValue($GLOBALS['conn'],'tyre_root_folder_id') ?: $DEFAULT_ROOT);
  $templateId  = trim((string)($_POST['template_override'] ?? '')) ?: (getSettingValue($GLOBALS['conn'],'tyre_template_doc_id') ?: $DEFAULT_TPL_ID);

  if (!$templateId || $templateId === 'GOOGLE_DOC_TEMPLATE_ID_PLACEHOLDER') {
    http_response_code(500);
    echo json_encode(['success'=>false,'message'=>'Template ID not configured: set setting tyre_template_doc_id or pass template_override','trace_id'=>$traceId]); exit;
  }

  /* -------- fetch inspection + tyres + answers -------- */
  // header
  $sqlH = "
    SELECT ti.id, ti.started_at, ti.submitted_at, ti.updated_at,
           v.vehicle_no, v.tyre_count,
           d.name AS driver_name, d.empid AS driver_code,
           p.plant_name
      FROM tyre_inspections ti
      LEFT JOIN vehicles v ON v.id = ti.vehicle_id
      LEFT JOIN drivers  d ON d.id = ti.driver_id
      LEFT JOIN plants   p ON p.id = ti.plant_id
     WHERE ti.id = ?
     LIMIT 1";
  $stH = $GLOBALS['conn']->prepare($sqlH);
  $stH->bind_param('i', $inspectionId);
  $stH->execute(); $hdr = $stH->get_result()->fetch_assoc(); $stH->close();
  if (!$hdr) { http_response_code(404); echo json_encode(['success'=>false,'message'=>'Inspection not found','trace_id'=>$traceId]); exit; }

  // tyres + aggregate answers per tyre_row_id
  $sqlT = "
    SELECT
      t.id, t.position_code, t.psi,
      SUM(CASE WHEN a.result='acceptable'     THEN 1 ELSE 0 END) AS acc,
      SUM(CASE WHEN a.result='caution'        THEN 1 ELSE 0 END) AS cau,
      SUM(CASE WHEN a.result='non_acceptable' THEN 1 ELSE 0 END) AS nonacc
    FROM tyre_inspection_tyres t
    LEFT JOIN tyre_inspection_answers a ON a.tyre_row_id = t.id
    WHERE t.inspection_id = ?
    GROUP BY t.id, t.position_code, t.psi
  ";
  $stT = $GLOBALS['conn']->prepare($sqlT);
  $stT->bind_param('i', $inspectionId);
  $stT->execute(); $rsT = $stT->get_result();
  $tyres = [];
  while ($r = $rsT->fetch_assoc()) $tyres[] = $r;
  $stT->close();

  // Normalise date
  $dateStr = $hdr['updated_at'] ?: ($hdr['submitted_at'] ?: $hdr['started_at'] ?: date('Y-m-d'));
  $dateFmt = date('d-M-Y', strtotime($dateStr));

  /* -------- build placeholders --------
     Header placeholders:
       {{VEHICLE_NAME}}  {{DRIVER_NAME}}  {{SERVICE_LOCATION}}  {{DATE}}
     For each position code in:
       R1,R21,R22,R31,R32,R41,R42,R51,R52,L1,L21,L22,L31,L32,L41,L42,L51,L52,S1
     we provide:
       {{<CODE>_MARK}}  -> ✓ (acceptable), C (caution), X (non-acceptable or PSI out of range)
       {{<CODE>_PSI}}   -> numeric PSI or blank
  */
  $codes = ['R1','R21','R22','R31','R32','R41','R42','R51','R52','L1','L21','L22','L31','L32','L41','L42','L51','L52','S1'];
  $map   = array_fill_keys($codes, ['MARK'=>'','PSI'=>'']);

  // fill from DB rows
  foreach ($tyres as $t) {
    $code = strtoupper((string)$t['position_code']);
    if (!isset($map[$code])) continue;
    $psi  = is_null($t['psi']) ? '' : (string)$t['psi'];
    $acc  = (int)($t['acc'] ?? 0);
    $cau  = (int)($t['cau'] ?? 0);
    $non  = (int)($t['nonacc'] ?? 0);

    // PSI range check
    $psiOut = false;
    if ($psi !== '') {
      $p = (float)$psi;
      $psiOut = ($p < 120.0 || $p > 130.0);
    }

    // priority: non-acceptable or PSI out -> X; else caution -> C; else if any acceptable -> ✓
    $mark = '';
    if ($non > 0 || $psiOut)       $mark = 'X';
    elseif ($cau > 0)              $mark = 'C';
    elseif ($acc > 0)              $mark = '✓';
    else                           $mark = '';

    $map[$code] = ['MARK'=>$mark, 'PSI'=>$psi];
  }

  $driverLabel = trim(($hdr['driver_name'] ?? '') . (!empty($hdr['driver_code']) ? ' · '.$hdr['driver_code'] : ''));
  $vars = [
    'VEHICLE_NAME'    => (string)($hdr['vehicle_no'] ?? ''),
    'DRIVER_NAME'     => $driverLabel ?: '',
    'SERVICE_LOCATION'=> (string)($hdr['plant_name'] ?? ''),
    'DATE'            => $dateFmt,
  ];
  foreach ($codes as $c) {
    $vars[$c.'_MARK'] = $map[$c]['MARK'];
    $vars[$c.'_PSI']  = $map[$c]['PSI'];
  }

  /* -------- Google services + month folder like bilty -------- */
  $mgr   = new GoogleDriveManager($GLOBALS['conn']);
  $drive = $mgr->getService();
  $docs  = $mgr->getDocsService();

  // yyyy/mm folder under root
  $yStr = date('Y', strtotime($dateStr));
  $mStr = date('F', strtotime($dateStr));
  $yearFolder  = $mgr->getOrCreateSubFolder($yStr, $rootFolder);
  $monthFolder = $mgr->getOrCreateSubFolder($mStr, $yearFolder);
  if (!$yearFolder || !$monthFolder) throw new Exception('Failed to prepare target Drive folders');

  // ensure template accessible
  try { $drive->files->get($templateId, ['supportsAllDrives'=>true,'fields'=>'id']); }
  catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['success'=>false,'message'=>'Template not accessible to service user','trace_id'=>$traceId]); exit;
  }

  $safe = fn($s)=> trim(preg_replace('~\s+~',' ', preg_replace('~[^\w\s\-\.\(\)]~u','',$s ?? '')));
  $veh  = $safe($hdr['vehicle_no'] ?? 'VEHICLE');
  $fileBase = sprintf('TYRE_INSPECTION_%d_%s_%s', (int)$inspectionId, $veh, date('Ymd', strtotime($dateStr)));
  $pdfName  = $fileBase . '.pdf';

  // find existing pdf in month folder (optional overwrite)
  $findPdf = function(\Google\Service\Drive $drive, string $parentId, string $name) : ?string {
    $q = sprintf(
      "name = '%s' and '%s' in parents and mimeType='application/pdf' and trashed=false",
      str_replace("'", "\\'", $name),
      str_replace("'", "\\'", $parentId)
    );
    $resp = $drive->files->listFiles([
      'q'=>$q,'fields'=>'files(id,name)','supportsAllDrives'=>true,'includeItemsFromAllDrives'=>true,'pageSize'=>1
    ]);
    $files = $resp->getFiles();
    return $files && count($files) ? $files[0]->getId() : null;
  };
  $withRetry = function(callable $fn, string $step, int $max=6) use ($log, $mgr) {
    $attempt = 0; $base = 0.6; $cap = 8.0;
    $jitter = fn() => random_int(80, 350) / 1000;
    while (true) {
      try { return $fn(); }
      catch (\Google\Service\Exception $ge) {
        $code = (int)($ge->getCode() ?: 0);
        $msg  = $ge->getMessage() ?: '';
        if ($code === 401 && method_exists($mgr,'forceRefresh')) {
          $attempt++; $mgr->forceRefresh(); usleep(300000); continue;
        }
        $retryable = in_array($code,[403,429,500,502,503,504],true)
                  || stripos($msg,'Rate Limit')!==false || stripos($msg,'userRateLimitExceeded')!==false;
        $attempt++;
        if (!$retryable || $attempt >= $max) throw $ge;
        $sleep = min($cap, ($code===403||$code===429? 3.5 : $base) * pow(1.7, $attempt-1)) + $jitter();
        usleep((int)($sleep * 1e6));
      }
    }
  };

  if ($overwrite) {
    if ($old = $findPdf($drive, $monthFolder, $pdfName)) {
      $withRetry(function() use ($drive,$old){ $drive->files->delete($old, ['supportsAllDrives'=>true]); return true; }, 'delete_old');
    }
  } else {
    if ($old = $findPdf($drive, $monthFolder, $pdfName)) {
      echo json_encode([
        'success'=>true,'skipped'=>true,'message'=>'PDF already exists (overwrite=0)',
        'file_id'=>$old,
        'preview'=>"https://drive.google.com/file/d/{$old}/preview",
        'download'=>"https://drive.google.com/uc?id={$old}&export=download",
        'trace_id'=>$traceId
      ]); exit;
    }
  }

  // 1) Copy template
  $copyMeta = new \Google\Service\Drive\DriveFile(['name'=>$fileBase, 'parents'=>[$monthFolder]]);
  $docCopy = $withRetry(function() use ($drive,$templateId,$copyMeta){
    return $drive->files->copy($templateId, $copyMeta, ['supportsAllDrives'=>true,'fields'=>'id,name,webViewLink']);
  }, 'copy_template');
  $docId = $docCopy->getId();

  // 2) Replace {{...}} with values
  $requests = [];
  foreach ($vars as $k => $v) {
    $requests[] = new \Google\Service\Docs\Request([
      'replaceAllText' => [
        'containsText' => ['text' => '{{'.$k.'}}', 'matchCase' => true],
        'replaceText'  => (string)$v
      ]
    ]);
  }
  $withRetry(function() use ($docs,$docId,$requests){
    $docs->documents->batchUpdate($docId, new \Google\Service\Docs\BatchUpdateDocumentRequest(['requests'=>$requests]));
    return true;
  }, 'docs_replace');

  // 3) Export to PDF
  $pdfBin = $withRetry(function() use ($drive,$docId){
    return $drive->files->export($docId, 'application/pdf', ['alt'=>'media']);
  }, 'export_pdf');
  $pdfBytes = ($pdfBin instanceof \GuzzleHttp\Psr7\Response) ? (string)$pdfBin->getBody() : (string)$pdfBin;
  if ($pdfBytes === '') { throw new \RuntimeException('Empty PDF export'); }

  // 4) Upload PDF
  $createdPdf = $withRetry(function() use ($drive,$pdfBytes,$pdfName,$monthFolder){
    $meta = new \Google\Service\Drive\DriveFile(['name'=>$pdfName,'parents'=>[$monthFolder]]);
    return $drive->files->create($meta, [
      'data'=>$pdfBytes, 'mimeType'=>'application/pdf', 'uploadType'=>'multipart',
      'fields'=>'id,webViewLink,webContentLink','supportsAllDrives'=>true
    ]);
  }, 'create_pdf');

  // 5) Optional share
  if ($enableSharing) {
    try {
      $withRetry(function() use ($drive,$createdPdf){
        return $drive->permissions->create(
          $createdPdf->id,
          new \Google\Service\Drive\Permission(['type'=>'anyone','role'=>'reader','allowFileDiscovery'=>false]),
          ['supportsAllDrives'=>true]
        );
      }, 'share_pdf');
    } catch (Throwable $e) { /* non-fatal */ }
  }

  // 6) Cleanup Doc
  if ($cleanupDoc) {
    try { $withRetry(function() use ($drive,$docId){ $drive->files->delete($docId, ['supportsAllDrives'=>true]); return true; }, 'cleanup_doc'); }
    catch (Throwable $e) { /* ignore */ }
  }

  $fileId      = $createdPdf->id;
  $viewLink    = "https://drive.google.com/file/d/{$fileId}/preview";
  $contentLink = "https://drive.google.com/uc?id={$fileId}&export=download";

  echo json_encode([
    'success'=>true,
    'inspection_id'=>$inspectionId,
    'file_id'=>$fileId,
    'preview'=>$viewLink,
    'download'=>$contentLink,
    'trace_id'=>$traceId
  ]);
  exit;

} catch (Throwable $e) {
  http_response_code(500);
  echo json_encode(['success'=>false,'message'=>'Unable to generate document','trace_id'=>$traceId,'error'=>$e->getMessage()]);
  exit;
}
