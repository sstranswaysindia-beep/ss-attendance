<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require __DIR__ . '/common.php';

date_default_timezone_set('Asia/Kolkata');

// ── Action dispatcher ───────────────────────────────────────────────────────
$action = strtolower(trim((string) ($_GET['action'] ?? $_POST['action'] ?? '')));

if ($action === 'form_data') {
    handleFormData($conn);
} elseif ($action === 'upload_documents') {
    handleUploadDocuments($conn);
} elseif ($action === 'save' || $_SERVER['REQUEST_METHOD'] === 'POST') {
    handleSave($conn);
} else {
    apiRespond(400, ['status' => 'error', 'error' => 'Unknown action. Use ?action=form_data or POST ?action=save']);
}

// ── GET: form_data ──────────────────────────────────────────────────────────
function handleFormData(mysqli $conn): void
{
    $plants = [];
    $res = $conn->query("SELECT id, plant_name, location, category FROM plants ORDER BY plant_name ASC");
    if ($res) {
        while ($row = $res->fetch_assoc()) {
            $plants[] = [
                'id'       => (int) $row['id'],
                'name'     => $row['plant_name'],
                'location' => $row['location'] ?? '',
                'category' => $row['category'] ?? '',
            ];
        }
    }

    $addresses = [];
    $res = $conn->query("
        SELECT
            oa.id,
            oa.plant_id,
            oa.address_local,
            oa.state,
            oa.pincode,
            p.plant_name
        FROM office_address oa
        LEFT JOIN plants p ON p.id = oa.plant_id
        ORDER BY COALESCE(p.plant_name, ''), oa.address_local ASC
    ");
    if ($res) {
        while ($row = $res->fetch_assoc()) {
            $plantName = trim((string) ($row['plant_name'] ?? ''));
            $addresses[] = [
                'id'      => (int) $row['id'],
                'plant_id'=> (int) ($row['plant_id'] ?? 0),
                'plant_name' => $plantName,
                'address' => $row['address_local'],
                'state'   => $row['state'] ?? '',
                'pincode' => $row['pincode'] ?? '',
                'label'   => trim(($row['address_local'] ?? '') . ($plantName !== '' ? ' (' . $plantName . ')' : ''))
                    . ' | ' . ($row['state'] ?? '') . ' - ' . ($row['pincode'] ?? ''),
            ];
        }
    }

    // Next EmpID preview (not locked; actual one is generated at save time)
    $nextEmpId = nextEmpIdPreview($conn);

    $banks = [
        'Bank Of Baroda', 'Bank Of Maharashtra', 'Maharashtra Bank', 'Bank Of India',
        'State Bank Of India', 'Kotak Mahindra Bank', 'Federal Bank', 'Canara Bank',
        'FINO BANK', 'Union Bank', 'Punjab National Bank', 'UCO Bank',
        'AU Small Finance Bank', 'Andhra Bank', 'Syndicate Bank', 'HDFC Bank',
        'Indusind Bank', 'Madhya Bihar Gramin Bank', 'IDBI Bank', 'Indian Bank',
        'Axis Bank', 'ICICI Bank', 'Central Bank Of India', 'SBI BANK',
        'Baroda Uttar Pradesh Gramin Bank', 'ARYAVART BANK', 'India Post Payment Bank',
        'Allahabad Bank', 'Bharat Sahakari Bank Ltd', 'Punjab And Sind Bank',
        'Indian Overseas Bank', 'Yes bank', 'NSDL Payments Bank',
        'Maharastra Gramin Bank', 'Karnataka Bank', 'Airtel Payment Bank',
        'Zilla Sahakari Bank Ltd',
    ];

    apiRespond(200, [
        'status'      => 'ok',
        'plants'      => $plants,
        'addresses'   => $addresses,
        'banks'       => $banks,
        'next_emp_id' => $nextEmpId,
    ]);
}

function nextEmpIdPreview(mysqli $conn): string
{
    $prefix = 'SST-';
    $start  = strlen($prefix) + 1;
    $sql    = "
        SELECT COALESCE(MAX(CAST(SUBSTRING(empid, ?) AS UNSIGNED)), 0) AS mx
          FROM drivers
         WHERE empid LIKE CONCAT(?, '%')
           AND empid REGEXP CONCAT('^', ?, '[0-9]+$')
    ";
    $stmt = $conn->prepare($sql);
    if (!$stmt) return $prefix . '001';
    $stmt->bind_param('iss', $start, $prefix, $prefix);
    $stmt->execute();
    $row  = $stmt->get_result()->fetch_assoc();
    $stmt->close();
    $next = (int) ($row['mx'] ?? 0) + 1;
    return $prefix . $next;
}

// ── POST: save ──────────────────────────────────────────────────────────────
function handleSave(mysqli $conn): void
{
    // Accept JSON body or form-encoded
    $raw  = file_get_contents('php://input');
    $data = json_decode($raw ?: '', true);
    if (!is_array($data)) {
        $data = $_POST;
    }

    $empid    = trim((string) ($data['empid'] ?? ''));
    $name     = trim((string) ($data['name'] ?? ''));
    $userId   = (int) ($data['user_id'] ?? 0);
    $username = trim((string) ($data['username'] ?? ('User#' . $userId)));

    if ($name === '') {
        apiRespond(400, ['success' => false, 'message' => 'Name is required']);
    }

    $updatedBy = "Last Updated by {$username} on " . date('Y-m-d H:i:s');

    // Normalise contact (digits only)
    $contactRaw = (string) ($data['contact'] ?? '');
    $contactCsv = preg_replace('/\D+/', '', $contactRaw);
    if (strlen($contactCsv) > 50) $contactCsv = substr($contactCsv, 0, 50);

    // Normalise nominee contact
    $nomineeContactDigits = preg_replace('/\D+/', '', (string) ($data['nominee_contact'] ?? ''));
    $nomineeContactDigits = strlen($nomineeContactDigits) > 20 ? substr($nomineeContactDigits, 0, 20) : $nomineeContactDigits;

    // Normalise ref_contact
    $refContactDigits = preg_replace('/\D+/', '', (string) ($data['ref_contact'] ?? ''));
    $refContactDigits = strlen($refContactDigits) > 20 ? substr($refContactDigits, 0, 20) : $refContactDigits;

    // Date-like columns: empty string → null
    $dateLikeCols = [
        'license_expiry_date', 'irte_license_validity', 'hazard_license_validity',
        'medical', 'dob', 'joining_date', 'dl_issue_date',
        'exp_start_date_1', 'exp_end_date_1', 'exp_start_date_2', 'exp_end_date_2',
        'exp_start_date_3', 'exp_end_date_3', 'pant_issue_date', 'shirt_issue_date', 'shoes_issue_date',
    ];

    $strOrNull = static function ($v) use ($dateLikeCols): ?string {
        return ($v === '' || $v === null) ? null : (string) $v;
    };
    $dateOrNull = static function ($v): ?string {
        return ($v === '' || $v === null) ? null : (string) $v;
    };

    $fields = [
        'role'                   => strOrNullSimple($data['role'] ?? null),
        'status'                 => ($data['status'] ?? '') !== '' ? (string) $data['status'] : 'Active',
        'esi_number'             => strOrNullSimple($data['esi_number'] ?? null),
        'uan_number'             => strOrNullSimple($data['uan_number'] ?? null),
        'father_name'            => strOrNullSimple($data['father_name'] ?? null),
        'gender'                 => ($data['gender'] ?? '') !== '' ? (string) $data['gender'] : 'Male',
        'marital_status'         => strOrNullSimple($data['marital_status'] ?? null),
        'dob'                    => nullIfEmpty($data['dob'] ?? null),
        'joining_date'           => nullIfEmpty($data['joining_date'] ?? null),
        'salary'                 => strOrNullSimple($data['salary'] ?? null),
        'address_local_id'       => strOrNullSimple($data['address_local_id'] ?? null),
        'address_permanent'      => strOrNullSimple($data['address_permanent'] ?? null),
        'state_permanent'        => strOrNullSimple($data['state_permanent'] ?? null),
        'pincode_permanent'      => strOrNullSimple($data['pincode_permanent'] ?? null),
        'nominee_name'           => strOrNullSimple($data['nominee_name'] ?? null),
        'relation_nominee'       => strOrNullSimple($data['relation_nominee'] ?? null),
        'nominee_contact'        => $nomineeContactDigits !== '' ? $nomineeContactDigits : null,
        'ifsc_code'              => strOrNullSimple($data['ifsc_code'] ?? null),
        'bank_account_number'    => strOrNullSimple($data['bank_account_number'] ?? null),
        'branch_name'            => strOrNullSimple($data['branch_name'] ?? null),
        'ref_name'               => strOrNullSimple($data['ref_name'] ?? null),
        'ref_relation'           => strOrNullSimple($data['ref_relation'] ?? null),
        'ref_contact'            => $refContactDigits !== '' ? $refContactDigits : null,
        'aadhaar_number'         => strOrNullSimple($data['aadhaar_number'] ?? null),
        'plant_id'               => strOrNullSimple($data['plant_id'] ?? null),
        'pan_card'               => strOrNullSimple($data['pan_card'] ?? null),
        'age'                    => strOrNullSimple($data['age'] ?? null),
        'company_id'             => strOrNullSimple($data['company_id'] ?? null),
        'dl_number'              => strOrNullSimple($data['dl_number'] ?? null),
        'dl_address'             => strOrNullSimple($data['dl_address'] ?? null),
        'dl_issue_date'          => nullIfEmpty($data['dl_issue_date'] ?? null),
        'dl_experience'          => strOrNullSimple($data['dl_experience'] ?? null),
        'license_expiry_date'    => nullIfEmpty($data['license_expiry_date'] ?? null),
        'irte'                   => strOrNullSimple($data['irte'] ?? null),
        'irte_license_validity'  => nullIfEmpty($data['irte_license_validity'] ?? null),
        'hazards'                => strOrNullSimple($data['hazards'] ?? null),
        'hazard_license_validity'=> nullIfEmpty($data['hazard_license_validity'] ?? null),
        'medical'                => nullIfEmpty($data['medical'] ?? null),
        'paint'                  => strOrNullSimple($data['paint'] ?? null),
        'shirt'                  => strOrNullSimple($data['shirt'] ?? null),
        'shoes'                  => strOrNullSimple($data['shoes'] ?? null),
        'pant_issue_date'        => nullIfEmpty($data['pant_issue_date'] ?? null),
        'shirt_issue_date'       => nullIfEmpty($data['shirt_issue_date'] ?? null),
        'shoes_issue_date'       => nullIfEmpty($data['shoes_issue_date'] ?? null),
        'first_name'             => strOrNullSimple($data['first_name'] ?? null),
        'last_name'              => strOrNullSimple($data['last_name'] ?? null),
        'father_first_name'      => strOrNullSimple($data['father_first_name'] ?? null),
        'father_last_name'       => strOrNullSimple($data['father_last_name'] ?? null),
        'exp_company_1'          => strOrNullSimple($data['exp_company_1'] ?? null),
        'exp_start_date_1'       => nullIfEmpty($data['exp_start_date_1'] ?? null),
        'exp_end_date_1'         => nullIfEmpty($data['exp_end_date_1'] ?? null),
        'exp_company_2'          => strOrNullSimple($data['exp_company_2'] ?? null),
        'exp_start_date_2'       => nullIfEmpty($data['exp_start_date_2'] ?? null),
        'exp_end_date_2'         => nullIfEmpty($data['exp_end_date_2'] ?? null),
        'exp_company_3'          => strOrNullSimple($data['exp_company_3'] ?? null),
        'exp_start_date_3'       => nullIfEmpty($data['exp_start_date_3'] ?? null),
        'exp_end_date_3'         => nullIfEmpty($data['exp_end_date_3'] ?? null),
        'bulk_pgp'               => strOrNullSimple($data['bulk_pgp'] ?? null),
        'company'                => strOrNullSimple($data['company'] ?? null),
        'location'               => strOrNullSimple($data['location'] ?? null),
        'license_verification'   => strOrNullSimple($data['license_verification'] ?? null),
        'contact'                => $contactCsv !== '' ? $contactCsv : null,
    ];

    // UPDATE path
    if ($empid !== '') {
        $stmt = $conn->prepare("SELECT 1 FROM drivers WHERE empid = ? LIMIT 1");
        $stmt->bind_param('s', $empid);
        $stmt->execute();
        $exists = (bool) $stmt->get_result()->fetch_row();
        $stmt->close();

        if ($exists) {
            $sets   = ["name = ?", "updated_by = ?", "updated_at = CURRENT_TIMESTAMP"];
            $params = [$name, $updatedBy];
            $types  = 'ss';

            foreach ($fields as $col => $val) {
                $sets[]   = "$col = ?";
                $params[] = $val;
                $types   .= 's';
            }

            $sql  = "UPDATE drivers SET " . implode(', ', $sets) . " WHERE empid = ?";
            $params[] = $empid;
            $types   .= 's';
            $stmt = $conn->prepare($sql);
            if (!$stmt) {
                apiRespond(500, ['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
            }
            $stmt->bind_param($types, ...$params);
            $ok  = $stmt->execute();
            $err = $stmt->error;
            $stmt->close();
            if ($ok) {
                apiRespond(200, ['success' => true, 'message' => 'Employee updated successfully', 'empid' => $empid]);
            } else {
                apiRespond(500, ['success' => false, 'message' => 'Update failed: ' . $err]);
            }
        }
        // else fall through to INSERT with provided empid
    }

    // INSERT path
    mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
    $conn->set_charset('utf8mb4');
    $conn->begin_transaction();

    try {
        $prefix    = 'SST-';
        $startPos  = strlen($prefix) + 1;

        if ($empid === '') {
            // Auto-generate
            $conn->query("SELECT 1 FROM drivers WHERE empid LIKE 'SST-%' FOR UPDATE");
            $sql2 = "
                SELECT COALESCE(MAX(CAST(SUBSTRING(empid, ?) AS UNSIGNED)), 0) AS mx
                  FROM drivers
                 WHERE empid LIKE CONCAT(?, '%')
                   AND empid REGEXP CONCAT('^', ?, '[0-9]+$')
                 FOR UPDATE
            ";
            $s2 = $conn->prepare($sql2);
            $s2->bind_param('iss', $startPos, $prefix, $prefix);
            $s2->execute();
            $row2       = $s2->get_result()->fetch_assoc();
            $s2->close();
            $finalEmpId = $prefix . ((int) ($row2['mx'] ?? 0) + 1);
        } else {
            $finalEmpId = strtoupper(trim($empid));
            if (!preg_match('/^SST-\d+$/', $finalEmpId)) {
                throw new RuntimeException('Invalid EmpID format; expected SST-<digits>');
            }
            $conn->query("SELECT 1 FROM drivers WHERE empid LIKE 'SST-%' FOR UPDATE");
        }

        $insert = array_merge(
            ['empid' => $finalEmpId, 'name' => $name, 'updated_by' => $updatedBy],
            $fields
        );

        $cols = []; $holders = []; $params = []; $types = '';
        foreach ($insert as $col => $val) {
            if ($val !== null && $val !== '') {
                $cols[]    = $col;
                $holders[] = '?';
                $params[]  = (string) $val;
                $types    .= 's';
            }
        }

        $sql  = "INSERT INTO drivers (" . implode(',', $cols) . ") VALUES (" . implode(',', $holders) . ")";
        $stmt = $conn->prepare($sql);
        if (!$stmt) throw new RuntimeException("Prepare failed: " . $conn->error);

        $stmt->bind_param($types, ...$params);
        try {
            $stmt->execute();
            $stmt->close();
            $conn->commit();
            apiRespond(200, ['success' => true, 'message' => 'Employee added successfully', 'empid' => $finalEmpId]);
        } catch (mysqli_sql_exception $e) {
            if ((int) $e->getCode() === 1062) {
                // Duplicate key - retry with new empid
                $conn->rollback();
                $conn->begin_transaction();
                $conn->query("SELECT 1 FROM drivers WHERE empid LIKE 'SST-%' FOR UPDATE");
                $s3 = $conn->prepare($sql2 ?? "SELECT COALESCE(MAX(CAST(SUBSTRING(empid, ?) AS UNSIGNED)), 0) AS mx FROM drivers WHERE empid LIKE CONCAT(?, '%') AND empid REGEXP CONCAT('^', ?, '[0-9]+\$') FOR UPDATE");
                $s3->bind_param('iss', $startPos, $prefix, $prefix);
                $s3->execute();
                $row3 = $s3->get_result()->fetch_assoc();
                $s3->close();
                $finalEmpId     = $prefix . ((int) ($row3['mx'] ?? 0) + 1);
                $insert['empid'] = $finalEmpId;

                $cols = []; $holders = []; $params = []; $types = '';
                foreach ($insert as $col => $val) {
                    if ($val !== null && $val !== '') {
                        $cols[]    = $col;
                        $holders[] = '?';
                        $params[]  = (string) $val;
                        $types    .= 's';
                    }
                }
                $sql2b = "INSERT INTO drivers (" . implode(',', $cols) . ") VALUES (" . implode(',', $holders) . ")";
                $s4    = $conn->prepare($sql2b);
                $s4->bind_param($types, ...$params);
                $s4->execute();
                $s4->close();
                $conn->commit();
                apiRespond(200, ['success' => true, 'message' => 'Employee added successfully', 'empid' => $finalEmpId]);
            }
            $conn->rollback();
            apiRespond(500, ['success' => false, 'message' => 'Insert failed: ' . $e->getMessage()]);
        }
    } catch (Throwable $e) {
        $conn->rollback();
        apiRespond(500, ['success' => false, 'message' => 'Insert failed: ' . $e->getMessage()]);
    }
}

function handleUploadDocuments(mysqli $conn): void
{
    $empid = strtoupper(trim((string) ($_POST['empid'] ?? '')));
    if ($empid === '') {
        apiRespond(400, ['success' => false, 'message' => 'empid is required']);
    }

    if (
        (empty($_FILES['aadhar_front']) || (int) ($_FILES['aadhar_front']['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) &&
        (empty($_FILES['aadhar_back']) || (int) ($_FILES['aadhar_back']['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) &&
        (empty($_FILES['dl_front']) || (int) ($_FILES['dl_front']['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) &&
        (empty($_FILES['dl_back']) || (int) ($_FILES['dl_back']['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) &&
        (empty($_FILES['profile_photo']) || (int) ($_FILES['profile_photo']['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK)
    ) {
        apiRespond(400, ['success' => false, 'message' => 'No document files received']);
    }

    $driverStmt = $conn->prepare('SELECT id, empid, name FROM drivers WHERE empid = ? LIMIT 1');
    if (!$driverStmt) {
        apiRespond(500, ['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    }
    $driverStmt->bind_param('s', $empid);
    $driverStmt->execute();
    $driver = $driverStmt->get_result()->fetch_assoc();
    $driverStmt->close();

    if (!$driver) {
        apiRespond(404, ['success' => false, 'message' => 'Driver not found for uploaded documents']);
    }

    $uploadBase = realpath(__DIR__ . '/../../../public_html/DriverDocs/uploads/raw');
    if ($uploadBase === false) {
        $uploadBase = __DIR__ . '/../../../public_html/DriverDocs/uploads/raw';
    }
    $uploadBase = rtrim((string) $uploadBase, '/\\');

    if (!is_dir($uploadBase) && !@mkdir($uploadBase, 0755, true) && !is_dir($uploadBase)) {
        apiRespond(500, ['success' => false, 'message' => 'Upload directory could not be created']);
    }

    $safeEmpId = preg_replace('/[^A-Z0-9_-]+/', '_', $empid) ?: 'SST';
    $safeName = preg_replace('/[^a-zA-Z0-9_-]+/', '_', strtolower(trim((string) ($driver['name'] ?? 'driver')))) ?: 'driver';
    $timestampToken = date('Ymd_His');

    $uploadedUrls = [];
    $savedPaths = [];

    $saveUpload = static function (string $fileKey, string $prefix) use (
        $uploadBase,
        $safeEmpId,
        $safeName,
        $timestampToken,
        &$savedPaths
    ): ?string {
        if (empty($_FILES[$fileKey]) || (int) ($_FILES[$fileKey]['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
            return null;
        }

        $original = (string) ($_FILES[$fileKey]['name'] ?? '');
        $tmpPath = (string) ($_FILES[$fileKey]['tmp_name'] ?? '');
        if ($tmpPath === '' || !is_uploaded_file($tmpPath)) {
            throw new RuntimeException('Uploaded file is invalid for ' . $fileKey);
        }

        $extRaw = strtolower((string) (pathinfo($original, PATHINFO_EXTENSION) ?: 'jpg'));
        $ext = preg_replace('/[^a-z0-9]/', '', $extRaw) ?: 'jpg';
        $filename = $prefix . '_' . $safeEmpId . '_' . $safeName . '_' . $timestampToken . '.' . $ext;
        $targetPath = $uploadBase . '/' . $filename;

        if (!move_uploaded_file($tmpPath, $targetPath)) {
            throw new RuntimeException('Failed to move uploaded file for ' . $fileKey);
        }

        $savedPaths[] = $targetPath;
        return '/DriverDocs/uploads/raw/' . $filename;
    };

    try {
        $uploadedUrls['aadhar_front'] = $saveUpload('aadhar_front', 'aadhar_front');
        $uploadedUrls['aadhar_back'] = $saveUpload('aadhar_back', 'aadhar_back');
        $uploadedUrls['dl_front'] = $saveUpload('dl_front', 'dl_front');
        $uploadedUrls['dl_back'] = $saveUpload('dl_back', 'dl_back');
        $uploadedUrls['profile_photo'] = $saveUpload('profile_photo', 'profile_photo');
    } catch (Throwable $e) {
        foreach ($savedPaths as $path) {
            if (is_file($path)) {
                @unlink($path);
            }
        }
        apiRespond(500, ['success' => false, 'message' => $e->getMessage()]);
    }

    $existingColumns = [];
    $columnsResult = $conn->query('SHOW COLUMNS FROM drivers');
    if ($columnsResult) {
        while ($column = $columnsResult->fetch_assoc()) {
            $existingColumns[] = (string) ($column['Field'] ?? '');
        }
        $columnsResult->close();
    }

    $updates = [];
    $params = [];
    $types = '';
    $updatedColumns = [];

    $rawAadhar = implode(',', array_values(array_filter([
        $uploadedUrls['aadhar_front'] ?? null,
        $uploadedUrls['aadhar_back'] ?? null,
    ])));
    $rawDriving = implode(',', array_values(array_filter([
        $uploadedUrls['dl_front'] ?? null,
        $uploadedUrls['dl_back'] ?? null,
    ])));
    $rawPhoto = $uploadedUrls['profile_photo'] ?? null;

    if ($rawAadhar !== '' && in_array('raw_aadhar', $existingColumns, true)) {
        $updates[] = 'raw_aadhar = ?';
        $params[] = $rawAadhar;
        $types .= 's';
        $updatedColumns['aadhar'] = 'raw_aadhar';
    }

    if ($rawDriving !== '' && in_array('raw_drivinglice', $existingColumns, true)) {
        $updates[] = 'raw_drivinglice = ?';
        $params[] = $rawDriving;
        $types .= 's';
        $updatedColumns['driving_licence'] = 'raw_drivinglice';
    }

    if ($rawPhoto !== null && $rawPhoto !== '' && in_array('raw_photo', $existingColumns, true)) {
        $updates[] = 'raw_photo = ?';
        $params[] = $rawPhoto;
        $types .= 's';
        $updatedColumns['profile_photo'] = 'raw_photo';
    }

    if (empty($updates)) {
        foreach ($savedPaths as $path) {
            if (is_file($path)) {
                @unlink($path);
            }
        }
        apiRespond(500, ['success' => false, 'message' => 'raw_aadhar/raw_drivinglice/raw_photo columns were not found on drivers table']);
    }

    $updates[] = 'updated_at = CURRENT_TIMESTAMP';
    $params[] = $empid;
    $types .= 's';

    $sql = 'UPDATE drivers SET ' . implode(', ', $updates) . ' WHERE empid = ? LIMIT 1';
    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        apiRespond(500, ['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    }

    $stmt->bind_param($types, ...$params);
    $ok = $stmt->execute();
    $err = $stmt->error;
    $stmt->close();

    if (!$ok) {
        foreach ($savedPaths as $path) {
            if (is_file($path)) {
                @unlink($path);
            }
        }
        apiRespond(500, ['success' => false, 'message' => 'Document link update failed: ' . $err]);
    }

    apiRespond(200, [
        'success' => true,
        'message' => 'Documents uploaded successfully',
        'empid' => $empid,
        'uploaded_urls' => array_filter($uploadedUrls),
        'raw_values' => array_filter([
            'raw_aadhar' => $rawAadhar,
            'raw_drivinglice' => $rawDriving,
            'raw_photo' => $rawPhoto,
        ], static fn($value) => $value !== null && $value !== ''),
        'updated_columns' => $updatedColumns,
    ]);
}

function strOrNullSimple($v): ?string
{
    if ($v === null || $v === '') return null;
    return (string) $v;
}

function nullIfEmpty($v): ?string
{
    if ($v === null || $v === '' || $v === '0000-00-00') return null;
    return (string) $v;
}
