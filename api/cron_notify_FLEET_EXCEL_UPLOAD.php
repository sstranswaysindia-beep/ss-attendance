<?php
declare(strict_types=1);

/**
 * public_html/api/cron_notify_FLEET_EXCEL_UPLOAD.php
 * ------------------------------------------------------------
 * Calls fleet_summary_email_fetch.php via HTTP (same server) with corn_bypass=1
 * to check email (Hostinger IMAP) and process Excel attachments. Logs output.
 * Useful when hosting cron is unreliable; you can trigger from browser,
 * Google Apps Script, or any external scheduler.
 */

date_default_timezone_set('Asia/Kolkata');

/* ✅ IMPORTANT: no spaces in URL; use your token + corn_bypass=1 for email check */
$url = 'https://sstranswaysindia.com/api/fleet_summary_email_fetch.php?token=fsd_7c9f3c0e8a1b4e2f9d6c1a7b5e3d0c9a&corn_bypass=1';

/* Logs in: public_html/api/logs/ */
$logDir  = __DIR__ . '/logs';
$logFile = $logDir . '/fleet_excel_upload.log';

if (!is_dir($logDir)) {
  @mkdir($logDir, 0775, true);
}

/* best-effort block web access to logs */
$ht = $logDir . '/.htaccess';
if (!is_file($ht)) {
  @file_put_contents($ht, "Deny from all\n");
}

/* -------- HTTP call via cURL -------- */
$ch = curl_init($url);
curl_setopt_array($ch, [
  CURLOPT_RETURNTRANSFER => true,
  CURLOPT_TIMEOUT        => 120,
  CURLOPT_CONNECTTIMEOUT => 30,
  CURLOPT_SSL_VERIFYPEER => true,
  CURLOPT_SSL_VERIFYHOST => 2,
]);

$response = curl_exec($ch);
$error    = curl_error($ch);
$httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

/* -------- Log result -------- */
$ts = date('Y-m-d H:i:s');

if ($response === false) {
  $line = "[$ts] ERROR http={$httpCode} err={$error}\n";
} else {
  $short = mb_substr((string)$response, 0, 5000);
  $line  = "[$ts] OK http={$httpCode} resp={$short}\n";
}

@file_put_contents($logFile, $line, FILE_APPEND);

/* optional: show output if you open this file in browser */
header('Content-Type: text/plain; charset=utf-8');
echo $line;
