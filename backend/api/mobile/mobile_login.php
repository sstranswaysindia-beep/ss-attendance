<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require __DIR__ . '/common.php';

$raw = file_get_contents('php://input');
$data = json_decode($raw ?: '', true);
if (!is_array($data)) {
    $data = $_POST;
}

$username = trim($data['username'] ?? '');
$password = $data['password'] ?? '';

if ($username === '' || $password === '') {
    apiRespond(400, ['status' => 'error', 'error' => 'missing_credentials']);
}

$stmt = $conn->prepare('SELECT id, username, password, role, driver_id FROM users WHERE username = ? LIMIT 1');
$stmt->bind_param('s', $username);
$stmt->execute();
$userRow = $stmt->get_result()->fetch_assoc();
$stmt->close();

if (!$userRow) {
    apiRespond(401, ['status' => 'error', 'error' => 'invalid_credentials']);
}

$isValid = password_verify($password, $userRow['password'])
    || hash('sha256', $password) === $userRow['password'];

if (!$isValid) {
    apiRespond(401, ['status' => 'error', 'error' => 'invalid_credentials']);
}

if (hash('sha256', $password) === $userRow['password']) {
    $newHash = password_hash($password, PASSWORD_DEFAULT);
    $upgrade = $conn->prepare('UPDATE users SET password = ? WHERE id = ?');
    $upgrade->bind_param('si', $newHash, $userRow['id']);
    $upgrade->execute();
    $upgrade->close();
}

$driverInfo = null;
$vehicles = [];
$supervisorInfo = null;

// Handle supervisors - fetch supervised plants
if (strcasecmp($userRow['role'], 'supervisor') === 0) {
    $supervisedPlants = [];
    $supervisedPlantIds = [];
    
    $sqlSup = "
        SELECT DISTINCT p.id, p.plant_name
        FROM plants p
        LEFT JOIN supervisor_plants sp ON sp.plant_id = p.id
        WHERE p.supervisor_user_id = ? OR sp.user_id = ?
        ORDER BY p.plant_name
    ";
    $stSup = $conn->prepare($sqlSup);
    if ($stSup) {
        $stSup->bind_param('ii', $userRow['id'], $userRow['id']);
        $stSup->execute();
        $resSup = $stSup->get_result();
        while ($rowSup = $resSup->fetch_assoc()) {
            $pid = (int)$rowSup['id'];
            $supervisedPlants[] = ['id' => $pid, 'plant_name' => (string)$rowSup['plant_name']];
            $supervisedPlantIds[] = $pid;
        }
        $stSup->close();
    }
    
    // Get vehicles for all supervised plants
    if (!empty($supervisedPlantIds)) {
        $placeholders = str_repeat('?,', count($supervisedPlantIds) - 1) . '?';
        $vehicleStmt = $conn->prepare(
            "SELECT id, vehicle_no, plant_id FROM vehicles WHERE plant_id IN ($placeholders) ORDER BY plant_id, vehicle_no"
        );
        if ($vehicleStmt) {
            $vehicleStmt->bind_param(str_repeat('i', count($supervisedPlantIds)), ...$supervisedPlantIds);
            $vehicleStmt->execute();
            $vehicles = $vehicleStmt->get_result()->fetch_all(MYSQLI_ASSOC);
            $vehicleStmt->close();
        }
    }
    
    $supervisorInfo = [
        'supervisedPlants' => $supervisedPlants,
        'supervisedPlantIds' => $supervisedPlantIds,
        'totalSupervisedPlants' => count($supervisedPlants),
    ];
}

if (!empty($userRow['driver_id'])) {
    $driverStmt = $conn->prepare(
        'SELECT d.*,
                a.id AS assignment_id,
                a.plant_id AS assignment_plant_id,
                a.vehicle_id AS assignment_vehicle_id,
                a.assigned_date,
                p.plant_name AS master_plant_name,
                vp.plant_name AS assignment_plant_name,
                v.vehicle_no AS assignment_vehicle_no,
                su.full_name AS assignment_supervisor_name,
                su.username AS assignment_supervisor_username,
                pu.full_name AS master_supervisor_name,
                pu.username AS master_supervisor_username
           FROM drivers d
           LEFT JOIN assignments a ON a.driver_id = d.id
           LEFT JOIN plants p      ON p.id = d.plant_id
           LEFT JOIN plants vp     ON vp.id = a.plant_id
           LEFT JOIN vehicles v    ON v.id = a.vehicle_id
           LEFT JOIN users su      ON su.id = vp.supervisor_user_id
           LEFT JOIN users pu      ON pu.id = p.supervisor_user_id
          WHERE d.id = ?
          LIMIT 1'
    );
    $driverStmt->bind_param('i', $userRow['driver_id']);
    $driverStmt->execute();
    $driver = $driverStmt->get_result()->fetch_assoc();
    $driverStmt->close();

    if ($driver) {
        $effectivePlantId   = $driver['assignment_plant_id'] ?? $driver['plant_id'];
        $effectivePlantName = $driver['assignment_plant_name'] ?? $driver['master_plant_name'];

        $assignmentSupervisorName = $driver['assignment_supervisor_name']
            ?? $driver['assignment_supervisor_username']
            ?? null;
        $defaultSupervisorName = $driver['master_supervisor_name']
            ?? $driver['master_supervisor_username']
            ?? null;
        $supervisorName = $assignmentSupervisorName ?: $defaultSupervisorName;

        if ($effectivePlantId) {
            $vehicleStmt = $conn->prepare(
                'SELECT id, vehicle_no FROM vehicles WHERE plant_id = ? ORDER BY vehicle_no'
            );
            $vehicleStmt->bind_param('i', $effectivePlantId);
            $vehicleStmt->execute();
            $vehicles = $vehicleStmt->get_result()->fetch_all(MYSQLI_ASSOC);
            $vehicleStmt->close();
        }

        $driverInfo = [
            'driverId'       => (int)$driver['id'],
            'employeeId'     => $driver['empid'],
            'name'           => $driver['name'],
            'role'           => $driver['role'],
            'status'         => $driver['status'],
            'profilePhoto'   => $driver['profile_photo_url'],
            'contact'        => $driver['contact'],
            'fatherName'     => $driver['father_name'],
            'gender'         => $driver['gender'],
            'maritalStatus'  => $driver['marital_status'],
            'dob'            => $driver['dob'],
            'joiningDate'    => $driver['joining_date'],
            'salary'         => $driver['salary'],
            'addressLocalId' => $driver['address_local_id'],
            'address'        => $driver['address_permanent'],
            'state'          => $driver['state_permanent'],
            'pincode'        => $driver['pincode_permanent'],
            'nomineeName'    => $driver['nominee_name'],
            'nomineeRelation'=> $driver['relation_nominee'],
            'ifsc'           => $driver['ifsc_code'],
            'ifscVerified'   => (bool)$driver['ifsc_code_verified'],
            'bankAccount'    => $driver['bank_account_number'],
            'branchName'     => $driver['branch_name'],
            'esiNumber'      => $driver['esi_number'],
            'uanNumber'      => $driver['uan_number'],
            'aadhaar'        => $driver['aadhaar_number'],
            'aadhaarVerified'=> (bool)$driver['aadhaar_verified'],
            'plantId'        => $driver['plant_id'],
            'supervisorOfPlantId' => $driver['supervisor_of_plant_id'],
            'pan'            => $driver['pan_card'],
            'panVerified'    => (bool)$driver['pan_verified'],
            'age'            => $driver['age'],
            'companyId'      => $driver['company_id'],
            'dlNumber'       => $driver['dl_number'],
            'dlValidity'     => $driver['dl_validity'],
            'dlIssueDate'    => $driver['dl_issue_date'],
            'dlExperience'   => $driver['dl_experience'],
            'rtoAuthority'   => $driver['rto_authority'],
            'pants'          => $driver['paint'],
            'shirt'          => $driver['shirt'],
            'shoes'          => $driver['shoes'],
            'hazardLicenseValidity' => $driver['hazard_license_validity'],
            'irteLicenseValidity'   => $driver['irte_license_validity'],
            'firstName'      => $driver['first_name'],
            'lastName'       => $driver['last_name'],
            'fatherFirstName'=> $driver['father_first_name'],
            'fatherLastName' => $driver['father_last_name'],
            'docsPlantId'    => $driver['docs_plant_id'],
            'bulkPgp'        => $driver['bulk_pgp'],
            'company'        => $driver['company'],
            'location'       => $driver['location'],
            'licenseExpiryDate' => $driver['license_expiry_date'],
            'hazards'        => $driver['hazards'],
            'irte'           => $driver['irte'],
            'medical'        => $driver['medical'],
            'licenseVerification' => $driver['license_verification'],
            'documentStatus' => $driver['document_status'],
            'documentPdfLink'=> $driver['document_pdf_link'],
            'pantIssueDate'  => $driver['pant_issue_date'],
            'shirtIssueDate' => $driver['shirt_issue_date'],
            'shoesIssueDate' => $driver['shoes_issue_date'],
            'createdAt'      => $driver['created_at'],
            'updatedAt'      => $driver['updated_at'],
            'assignment' => [
                'assignmentId'  => $driver['assignment_id'],
                'plantId'       => $effectivePlantId,
                'plantName'     => $effectivePlantName,
                'vehicleId'     => $driver['assignment_vehicle_id'],
                'vehicleNumber' => $driver['assignment_vehicle_no'],
                'assignedDate'  => $driver['assigned_date'],
            ],
            'defaultPlantId'   => $driver['plant_id'],
            'defaultPlantName' => $driver['master_plant_name'],
            'supervisorName'   => $supervisorName,
        ];
    }
}

apiRespond(200, [
    'status' => 'ok',
    'user' => [
        'id'       => (int)$userRow['id'],
        'username' => $userRow['username'],
        'role'     => $userRow['role'],
    ],
    'driver' => $driverInfo,
    'supervisor' => $supervisorInfo,
    'vehicles' => array_map(static function (array $row): array {
        return [
            'id'            => (int)$row['id'],
            'vehicleNumber' => $row['vehicle_no'],
            'plantId'       => isset($row['plant_id']) ? (int)$row['plant_id'] : null,
        ];
    }, $vehicles),
]);
