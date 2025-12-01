<?php
declare(strict_types=1);

if (session_status() === PHP_SESSION_NONE) session_start();

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
$log = ApiLogger::new('spot_audit_pdf');
$traceId = $log->id();

function spot_require(string $path, ApiLogger $logger, string $label): void
{
    if (!file_exists($path)) {
        $logger->log('ERROR', 'include:missing', ['label' => $label, 'path' => $path]);
        http_response_code(500);
        echo json_encode(['success' => false, 'message' => "Missing dependency: {$label}", 'trace_id' => $logger->id()]);
        exit;
    }
}

set_error_handler(function ($severity, $message, $file, $line) use ($log) {
    if (!(error_reporting() & $severity)) {
        return true;
    }
    $level = in_array($severity, [E_WARNING, E_USER_WARNING], true) ? 'WARN' : 'INFO';
    $log->log($level, 'php:error', compact('severity', 'message', 'file', 'line'));
    return true;
});
register_shutdown_function(function () use ($log, $traceId) {
    $e = error_get_last();
    if ($e && in_array($e['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR], true)) {
        $log->log('ERROR', 'php:fatal', $e);
        echo json_encode(['success' => false, 'message' => 'Fatal server error', 'trace_id' => $traceId]);
    }
});

$authPath    = __DIR__ . '/../../includes/auth.php';
$configPath  = __DIR__ . '/../../../conf/config.php';
$gdmPath     = __DIR__ . '/../classes/GoogleDriveManager.php';
$helpersPath = __DIR__ . '/api/safety/helpers.php';
spot_require($authPath, $log, 'includes/auth.php');
spot_require($configPath, $log, 'conf/config.php');
spot_require($gdmPath, $log, 'classes/GoogleDriveManager.php');
spot_require($helpersPath, $log, 'api/helpers.php');

require_once $authPath;
require_once $configPath;
require_once $gdmPath;
require_once $helpersPath;

if (isset($GLOBALS['conn']) && $GLOBALS['conn'] instanceof mysqli) {
    $GLOBALS['conn']->set_charset('utf8mb4');
}

$vendorCandidates = [
    __DIR__ . '/vendor/autoload.php',
    __DIR__ . '/../vendor/autoload.php',
    __DIR__ . '/../../vendor/autoload.php',
];
$autoloadHit = null;
foreach ($vendorCandidates as $candidate) {
    if (file_exists($candidate)) {
        require_once $candidate;
        $autoloadHit = $candidate;
        break;
    }
}
if (!$autoloadHit || !class_exists(\Google\Service\Drive::class) || !class_exists(\Google\Service\Docs::class)) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Google API client not installed. Run: composer require google/apiclient',
        'trace_id' => $traceId,
    ]);
    exit;
}

if (isset($_GET['selftest'])) {
    header('Content-Type: text/plain; charset=utf-8');
    echo "== Spot Audit PDF Self-Test ==\n\n";
    $svcPath = __DIR__ . '/../secure_store/google-service.json';
    echo "[1] Autoload: " . ($autoloadHit ? "OK ({$autoloadHit})\n" : "MISSING\n");
    echo "[2] Service JSON: " . (is_file($svcPath) ? "OK\n" : "MISSING\n");
    if (is_file($svcPath)) {
        $json = json_decode(file_get_contents($svcPath), true);
        echo "    client_email: " . ($json['client_email'] ?? 'N/A') . "\n";
    }
    $templateId = getSettingValue($GLOBALS['conn'], 'spot_audit_template_doc_id') ?: '';
    $templateId = trim((string)($_GET['template'] ?? $templateId));
    echo "[3] Template ID: " . ($templateId ?: 'NOT SET') . "\n";
    $auditId = filter_var($_GET['audit_id'] ?? $_GET['id'] ?? null, FILTER_VALIDATE_INT);
    echo "[4] Audit ID: " . ($auditId ?: 'MISSING (?audit_id=)') . "\n";
    if ($auditId) {
        try {
            $stmt = $GLOBALS['conn']->prepare('SELECT id FROM safety_spot_audits WHERE id = ?');
            $stmt->bind_param('i', $auditId);
            $stmt->execute();
            $found = (bool)$stmt->get_result()->fetch_assoc();
            $stmt->close();
            echo "    DB lookup: " . ($found ? "OK\n" : "NOT FOUND\n");
        } catch (Throwable $e) {
            echo "    DB error: " . $e->getMessage() . "\n";
        }
    }
    echo "\nShare the Google Doc template with the service account email above.\n";
    exit;
}

try {
    checkRole(['admin', 'supervisor']);
} catch (Throwable $e) {
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'Forbidden', 'trace_id' => $traceId]);
    exit;
}

try {
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
        http_response_code(405);
        echo json_encode(['success' => false, 'message' => 'Method not allowed', 'trace_id' => $traceId]);
        exit;
    }

    $posted = (string)($_POST['csrf_token'] ?? '');
    $stored = (string)($_SESSION['csrf_token'] ?? '');
    if ($posted === '' || $stored === '' || !hash_equals($stored, $posted)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'message' => 'Invalid CSRF', 'trace_id' => $traceId]);
        exit;
    }

    $auditId = filter_var($_POST['audit_id'] ?? $_POST['spot_audit_id'] ?? null, FILTER_VALIDATE_INT);
    if (!$auditId) {
        http_response_code(400);
        echo json_encode(['success' => false, 'message' => 'audit_id required', 'trace_id' => $traceId]);
        exit;
    }

    $overwrite     = isset($_POST['overwrite']) ? ((string)$_POST['overwrite'] === '1') : true;
    $enableSharing = isset($_POST['share_public']) ? ((string)$_POST['share_public'] === '1') : false;
    $cleanupDoc    = !isset($_POST['cleanup_doc']) || ((string)$_POST['cleanup_doc'] === '1');
    $scoreComment  = trim((string)($_POST['score_comment'] ?? ''));

    $DEFAULT_ROOT   = 'GOOGLE_DRIVE_ROOT_FOLDER_ID';
    $DEFAULT_TPL_ID = 'GOOGLE_DOC_TEMPLATE_ID_PLACEHOLDER';

    $rootFolder = trim((string)($_POST['folder_override'] ?? '')) ?: (getSettingValue($GLOBALS['conn'], 'spot_audit_root_folder_id') ?: $DEFAULT_ROOT);
    $templateId = trim((string)($_POST['template_override'] ?? '')) ?: (getSettingValue($GLOBALS['conn'], 'spot_audit_template_doc_id') ?: $DEFAULT_TPL_ID);

    if (!$templateId || $templateId === 'GOOGLE_DOC_TEMPLATE_ID_PLACEHOLDER') {
        http_response_code(500);
        echo json_encode(['success' => false, 'message' => 'Template ID not configured. Set setting spot_audit_template_doc_id or pass template_override', 'trace_id' => $traceId]);
        exit;
    }

    $sqlAudit = "
        SELECT
            a.*,
            p.plant_name,
            v.vehicle_no,
            v.id AS vehicle_master_id,
            d.name AS driver_name,
            d.empid AS driver_code,
            u.full_name AS created_by_name
        FROM safety_spot_audits a
        LEFT JOIN plants p ON p.id = a.plant_id
        LEFT JOIN vehicles v ON v.id = a.vehicle_id
        LEFT JOIN drivers d ON d.id = a.driver_id
        LEFT JOIN users u ON u.id = a.created_by
        WHERE a.id = ?
        LIMIT 1
    ";
    $stmtAudit = $GLOBALS['conn']->prepare($sqlAudit);
    $stmtAudit->bind_param('i', $auditId);
    $stmtAudit->execute();
    $audit = $stmtAudit->get_result()->fetch_assoc();
    $stmtAudit->close();
    if (!$audit) {
        http_response_code(404);
        echo json_encode(['success' => false, 'message' => 'Audit not found', 'trace_id' => $traceId]);
        exit;
    }

    $sectionStmt = $GLOBALS['conn']->prepare("
        SELECT section_key, section_label, average_score, comments
        FROM safety_spot_audit_sections
        WHERE audit_id = ?
        ORDER BY id ASC
    ");
    $sectionStmt->bind_param('i', $auditId);
    $sectionStmt->execute();
    $sectionRes = $sectionStmt->get_result();
    $sections = [];
    while ($row = $sectionRes->fetch_assoc()) {
        $key = $row['section_key'] ?: uniqid('section_', false);
        $sections[$key] = [
            'key' => $row['section_key'],
            'label' => $row['section_label'] ?: ($row['section_key'] ?: 'Section'),
            'score' => $row['average_score'],
            'comments' => $row['comments'] ?? '',
            'guide' => $sectionGuides[$row['section_key']] ?? '',
            'answers' => [],
        ];
    }
    $sectionStmt->close();

    $answerStmt = $GLOBALS['conn']->prepare("
        SELECT section_key, question_key, choice_value, numeric_score, extra_comment
        FROM safety_spot_audit_answers
        WHERE audit_id = ?
        ORDER BY id ASC
    ");
    $answerStmt->bind_param('i', $auditId);
    $answerStmt->execute();
    $answerRes = $answerStmt->get_result();
    while ($row = $answerRes->fetch_assoc()) {
        $key = $row['section_key'] ?: 'misc';
        if (!isset($sections[$key])) {
            $sections[$key] = [
                'key' => $row['section_key'],
                'label' => $row['section_key'] ?: 'Section',
                'score' => null,
                'comments' => '',
                'guide' => $sectionGuides[$row['section_key']] ?? '',
                'answers' => [],
            ];
        }
        $sections[$key]['answers'][] = $row;
    }
    $answerStmt->close();

    $assessmentDate = $audit['assessment_date'] ?: date('Y-m-d');
    $targetDate = $audit['target_date'] ?: '';
    $dateDisplay = $assessmentDate ? date('d-M-Y', strtotime($assessmentDate)) : '';
    $targetDisplay = $targetDate ? date('d-M-Y', strtotime($targetDate)) : '';

    $driverLabel = trim(($audit['driver_name'] ?? '') . (!empty($audit['driver_code']) ? ' · ' . $audit['driver_code'] : ''));
    $vehicleLabel = $audit['vehicle_number'] ?: ($audit['vehicle_no'] ?? '');

    $vars = [
        'AUDIT_ID' => (string)$audit['id'],
        'PLANT_ID' => (string)$audit['plant_id'],
        'PLANT_NAME' => (string)($audit['plant_name'] ?? ''),
        'VEHICLE_ID' => (string)$audit['vehicle_id'],
        'VEHICLE_NUMBER' => (string)$vehicleLabel,
        'DRIVER_ID' => (string)$audit['driver_id'],
        'DRIVER_NAME' => $driverLabel ?: '',
        'TRANSPORTER_NAME' => (string)($audit['transporter_name'] ?? 'SS Transways India'),
        'ASSESSMENT_DATE' => $dateDisplay,
        'TARGET_DATE' => $targetDisplay,
        'TOTAL_SCORE' => (string)($audit['total_score'] ?? ''),
        'TRUCK_CATEGORY' => (string)($audit['truck_category'] ?? ''),
        'LANGUAGE_CODE' => strtoupper((string)($audit['language_code'] ?? '')),
        'HIGHLIGHTS' => (string)($audit['highlights'] ?? ''),
        'ACTION_PLAN' => (string)($audit['action_plan'] ?? ''),
        'FINAL_ACTION' => (string)($audit['final_action'] ?? ''),
        'ASSESSED_BY' => (string)($audit['assessed_by'] ?? ''),
        'CREATED_BY' => (string)($audit['created_by_name'] ?? ''),
        'SCORE_COMMENT' => $scoreComment,
    ];

    $sectionLines = [];
    $scoreLines = [];
    $commentLines = [];
    foreach ($sections as $section) {
        $title = $section['label'] ?? ($section['key'] ?: 'Section');
        $line = "{$title}";
        if (isset($section['score']) && $section['score'] !== null) {
            $line .= " (Score: {$section['score']})";
        }
        $sectionLines[] = $line;
        if (!empty($section['guide'])) {
            $sectionLines[] = "Guide: {$section['guide']}";
        }
        if (!empty($section['comments'])) {
            $sectionLines[] = "Notes: {$section['comments']}";
        }
        foreach ($section['answers'] as $answer) {
            $qKey = $answer['question_key'] ?? '';
            $label = $questionLabels[$qKey] ?? $qKey;
            $ansLine = "- {$label}: {$answer['choice_value']}";
            if ($answer['numeric_score'] !== null) {
                $ansLine .= " (Score {$answer['numeric_score']})";
            }
            if (!empty($answer['extra_comment'])) {
                $ansLine .= " · {$answer['extra_comment']}";
            }
            $sectionLines[] = $ansLine;
        }
        $sectionLines[] = '';

        $safeKey = strtoupper(preg_replace('/[^A-Z0-9]+/', '_', (string)$section['key']));
        $vars["SECTION_{$safeKey}_TITLE"] = $title;
        $vars["SECTION_{$safeKey}_SCORE"] = (string)($section['score'] ?? '');
        $vars["SECTION_{$safeKey}_GUIDE"] = (string)($section['guide'] ?? '');
        $vars["SECTION_{$safeKey}_COMMENTS"] = (string)($section['comments'] ?? '');
        $answerSummary = [];
        foreach ($section['answers'] as $answer) {
            $qKey = $answer['question_key'] ?? '';
            $label = $questionLabels[$qKey] ?? $qKey;
            $summary = "{$label}: {$answer['choice_value']}";
            if ($answer['numeric_score'] !== null) {
                $summary .= " (Score {$answer['numeric_score']})";
            }
            if (!empty($answer['extra_comment'])) {
                $summary .= " · {$answer['extra_comment']}";
            }
            $answerSummary[] = $summary;
        }
        $vars["SECTION_{$safeKey}_ANSWERS"] = implode("\n", $answerSummary);

        if ($section['score'] !== null) {
            $scoreLines[] = "{$title}: {$section['score']}";
        }
        if (!empty($section['comments'])) {
            $commentLines[] = "{$title}: {$section['comments']}";
        }
    }

    $vars['SECTION_SUMMARY'] = trim(implode("\n", $sectionLines));
    $vars['CATEGORY_SCORES'] = implode("\n", $scoreLines);
    $vars['CATEGORY_COMMENTS'] = implode("\n", $commentLines);

    $mgr = new GoogleDriveManager($GLOBALS['conn']);
    $drive = $mgr->getService();
    $docs = $mgr->getDocsService();

    $dateForFolders = $assessmentDate ?: date('Y-m-d');
    $yearFolder = $mgr->getOrCreateSubFolder(date('Y', strtotime($dateForFolders)), $rootFolder);
    $monthFolder = $yearFolder ? $mgr->getOrCreateSubFolder(date('F', strtotime($dateForFolders)), $yearFolder) : null;
    if (!$yearFolder || !$monthFolder) {
        throw new RuntimeException('Failed to prepare Drive folders');
    }

    try {
        $drive->files->get($templateId, ['supportsAllDrives' => true, 'fields' => 'id']);
    } catch (Throwable $e) {
        http_response_code(500);
        echo json_encode(['success' => false, 'message' => 'Template not accessible to service account', 'trace_id' => $traceId]);
        exit;
    }

    $safeName = fn(string $value) => trim(preg_replace('~\s+~', ' ', preg_replace('~[^\w\s\-\.\(\)]~u', '', $value)));
    $vehicleSafe = $safeName($vehicleLabel ?: 'VEHICLE');
    $fileBase = sprintf('SPOT_AUDIT_%d_%s_%s', $auditId, $vehicleSafe, date('Ymd', strtotime($dateForFolders)));
    $pdfName = $fileBase . '.pdf';

    $findPdf = function (\Google\Service\Drive $drive, string $parentId, string $name) {
        $q = sprintf(
            "name = '%s' and '%s' in parents and mimeType='application/pdf' and trashed=false",
            str_replace("'", "\\'", $name),
            str_replace("'", "\\'", $parentId)
        );
        $resp = $drive->files->listFiles([
            'q' => $q,
            'fields' => 'files(id,name)',
            'supportsAllDrives' => true,
            'includeItemsFromAllDrives' => true,
            'pageSize' => 1,
        ]);
        $files = $resp->getFiles();
        return $files && count($files) ? $files[0]->getId() : null;
    };

    $withRetry = function (callable $fn, string $step, int $max = 6) use ($log, $mgr) {
        $attempt = 0;
        $base = 0.6;
        $cap = 8.0;
        $jitter = fn() => random_int(80, 350) / 1000;
        while (true) {
            try {
                return $fn();
            } catch (\Google\Service\Exception $ge) {
                $code = (int)($ge->getCode() ?: 0);
                $msg = $ge->getMessage() ?: '';
                if ($code === 401 && method_exists($mgr, 'forceRefresh')) {
                    $attempt++;
                    $mgr->forceRefresh();
                    usleep(300000);
                    continue;
                }
                $retryable = in_array($code, [403, 429, 500, 502, 503, 504], true)
                    || stripos($msg, 'Rate Limit') !== false
                    || stripos($msg, 'userRateLimitExceeded') !== false;
                $attempt++;
                if (!$retryable || $attempt >= $max) {
                    throw $ge;
                }
                $sleep = min($cap, ($code === 403 || $code === 429 ? 3.5 : $base) * pow(1.7, $attempt - 1)) + $jitter();
                usleep((int)($sleep * 1_000_000));
            }
        }
    };

    if ($overwrite) {
        if ($old = $findPdf($drive, $monthFolder, $pdfName)) {
            $withRetry(function () use ($drive, $old) {
                $drive->files->delete($old, ['supportsAllDrives' => true]);
                return true;
            }, 'delete_old');
        }
    } else {
        if ($old = $findPdf($drive, $monthFolder, $pdfName)) {
            echo json_encode([
                'success' => true,
                'skipped' => true,
                'message' => 'PDF already exists (overwrite=0)',
                'file_id' => $old,
                'preview' => "https://drive.google.com/file/d/{$old}/preview",
                'download' => "https://drive.google.com/uc?id={$old}&export=download",
                'trace_id' => $traceId,
            ]);
            exit;
        }
    }

    $copyMeta = new \Google\Service\Drive\DriveFile(['name' => $fileBase, 'parents' => [$monthFolder]]);
    $docCopy = $withRetry(function () use ($drive, $templateId, $copyMeta) {
        return $drive->files->copy($templateId, $copyMeta, ['supportsAllDrives' => true, 'fields' => 'id,name,webViewLink']);
    }, 'copy_template');
    $docId = $docCopy->getId();

    $requests = [];
    foreach ($vars as $key => $value) {
        $requests[] = new \Google\Service\Docs\Request([
            'replaceAllText' => [
                'containsText' => ['text' => '{{' . $key . '}}', 'matchCase' => true],
                'replaceText' => (string)$value,
            ],
        ]);
    }
    $withRetry(function () use ($docs, $docId, $requests) {
        $docs->documents->batchUpdate($docId, new \Google\Service\Docs\BatchUpdateDocumentRequest(['requests' => $requests]));
        return true;
    }, 'docs_replace');

    $pdfBin = $withRetry(function () use ($drive, $docId) {
        return $drive->files->export($docId, 'application/pdf', ['alt' => 'media']);
    }, 'export_pdf');
    $pdfBytes = ($pdfBin instanceof \GuzzleHttp\Psr7\Response) ? (string)$pdfBin->getBody() : (string)$pdfBin;
    if ($pdfBytes === '') {
        throw new RuntimeException('Empty PDF export');
    }

    $createdPdf = $withRetry(function () use ($drive, $pdfBytes, $pdfName, $monthFolder) {
        $meta = new \Google\Service\Drive\DriveFile(['name' => $pdfName, 'parents' => [$monthFolder]]);
        return $drive->files->create($meta, [
            'data' => $pdfBytes,
            'mimeType' => 'application/pdf',
            'uploadType' => 'multipart',
            'fields' => 'id,webViewLink,webContentLink',
            'supportsAllDrives' => true,
        ]);
    }, 'create_pdf');

    if ($enableSharing) {
        try {
            $withRetry(function () use ($drive, $createdPdf) {
                return $drive->permissions->create(
                    $createdPdf->id,
                    new \Google\Service\Drive\Permission(['type' => 'anyone', 'role' => 'reader', 'allowFileDiscovery' => false]),
                    ['supportsAllDrives' => true]
                );
            }, 'share_pdf');
        } catch (Throwable $e) {
            // ignore sharing errors
        }
    }

    if ($cleanupDoc) {
        try {
            $withRetry(function () use ($drive, $docId) {
                $drive->files->delete($docId, ['supportsAllDrives' => true]);
                return true;
            }, 'cleanup_doc');
        } catch (Throwable $e) {
            // ignore cleanup errors
        }
    }

    $fileId = $createdPdf->id;
    echo json_encode([
        'success' => true,
        'audit_id' => $auditId,
        'file_id' => $fileId,
        'preview' => "https://drive.google.com/file/d/{$fileId}/preview",
        'download' => "https://drive.google.com/uc?id={$fileId}&export=download",
        'trace_id' => $traceId,
    ]);
    exit;
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Unable to generate document',
        'trace_id' => $traceId,
        'error' => $e->getMessage(),
    ]);
    exit;
}
