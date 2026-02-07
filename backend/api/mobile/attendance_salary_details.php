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

apiEnsurePost();

$data = apiRequireJson();

$driverId = apiSanitizeInt($data['driverId'] ?? null);
$monthKey = trim((string)($data['month'] ?? ''));

if (!$driverId) {
    apiRespond(400, ['status' => 'error', 'error' => 'driverId is required']);
}

if ($monthKey === '' || !preg_match('/^\d{4}-\d{2}$/', $monthKey)) {
    $monthKey = date('Y-m');
}

function table_exists(mysqli $conn, string $table): bool {
    $st = $conn->prepare("SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? LIMIT 1");
    $st->bind_param('s', $table);
    $st->execute();
    $ok = (bool)$st->get_result()->fetch_row();
    $st->close();
    return $ok;
}

function column_exists(mysqli $conn, string $table, string $col): bool {
    $st = $conn->prepare("SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND COLUMN_NAME=? LIMIT 1");
    $st->bind_param('ss', $table, $col);
    $st->execute();
    $ok = (bool)$st->get_result()->fetch_row();
    $st->close();
    return $ok;
}

function ym_add_months(string $ym, int $add): string {
    $dt = DateTime::createFromFormat('Y-m-d', $ym . '-01');
    if (!$dt) return $ym;
    $dt->modify(($add >= 0 ? '+' : '') . $add . ' month');
    return $dt->format('Y-m');
}

function ym_cmp(string $a, string $b): int {
    return strcmp($a, $b);
}

try {
    $year = (int)substr($monthKey, 0, 4);
    $month = (int)substr($monthKey, 5, 2);
    $firstDay = sprintf('%04d-%02d-01', $year, $month);
    $daysInMonth = (int)date('t', strtotime($firstDay));
    $lastDay = sprintf('%04d-%02d-%02d', $year, $month, $daysInMonth);
    $today = date('Y-m-d');
    $isCurrentMonth = ($monthKey === date('Y-m'));
    $cutoff = $isCurrentMonth ? min($today, $lastDay) : $lastDay;

    $driverStmt = $conn->prepare(
        'SELECT id, plant_id, salary, esi_number, uan_number
           FROM drivers
          WHERE id = ?
          LIMIT 1'
    );
    $driverStmt->bind_param('i', $driverId);
    $driverStmt->execute();
    $driverRow = $driverStmt->get_result()->fetch_assoc();
    $driverStmt->close();

    if (!$driverRow) {
        apiRespond(404, ['status' => 'error', 'error' => 'Driver not found']);
    }

    $plantId = isset($driverRow['plant_id']) ? (int)$driverRow['plant_id'] : null;
    $salaryRaw = (string)($driverRow['salary'] ?? '0');
    $salaryClean = preg_replace('/[^\d.\-]/', '', $salaryRaw);
    $salaryNum = is_numeric($salaryClean) ? (float)$salaryClean : 0.0;
    $esiVal = trim((string)($driverRow['esi_number'] ?? ''));
    $uanVal = trim((string)($driverRow['uan_number'] ?? ''));

    $advanceBal = 0.0;
    $advStmt = $conn->prepare(
        "SELECT
            COALESCE(SUM(CASE WHEN t.type='advance_received' THEN t.amount ELSE 0 END),0) AS received,
            COALESCE(SUM(CASE WHEN t.type='expense' THEN t.amount ELSE 0 END),0) AS spent
         FROM advance_transactions t
         WHERE t.driver_id = ?
           AND t.created_at BETWEEN ? AND ?"
    );
    $startTs = $firstDay . ' 00:00:00';
    $endTs = $lastDay . ' 23:59:59';
    $advStmt->bind_param('iss', $driverId, $startTs, $endTs);
    $advStmt->execute();
    $advRow = $advStmt->get_result()->fetch_assoc();
    $advStmt->close();
    if ($advRow) {
        $advanceBal = (float)$advRow['received'] - (float)$advRow['spent'];
    }

    $LOAN_TOTAL_COL = 'principal';
    $LOAN_EMI_AMT_COL = 'emi_amount';
    $LOAN_EMI_COL = 'emi_count';
    $LOAN_START_COL = 'start_month';
    $LOAN_STATUS_COL = 'status';

    $HAS_LOANS_TBL = table_exists($conn, 'driver_loans');
    $HAS_LOAN_ADJ = table_exists($conn, 'driver_loan_adjustments');
    if ($HAS_LOANS_TBL) {
        $need = [$LOAN_TOTAL_COL, $LOAN_EMI_AMT_COL, $LOAN_EMI_COL, $LOAN_START_COL, $LOAN_STATUS_COL];
        foreach ($need as $col) {
            if (!column_exists($conn, 'driver_loans', $col)) {
                $HAS_LOANS_TBL = false;
                break;
            }
        }
    }

    $loanEmi = 0.0;
    $loanAdj = 0.0;
    $hasActiveLoan = false;

    if ($HAS_LOANS_TBL) {
        $loanStmt = $conn->prepare(
            "SELECT
                id AS loan_id,
                driver_id,
                `$LOAN_TOTAL_COL` AS total_amount,
                `$LOAN_EMI_COL` AS emi_count,
                `$LOAN_EMI_AMT_COL` AS emi_amount,
                `$LOAN_START_COL` AS start_ym,
                COALESCE($LOAN_STATUS_COL,'active') AS status
             FROM driver_loans
             WHERE driver_id = ?
               AND COALESCE($LOAN_STATUS_COL,'active')='active'"
        );
        $loanStmt->bind_param('i', $driverId);
        $loanStmt->execute();
        $loanRes = $loanStmt->get_result();
        while ($row = $loanRes->fetch_assoc()) {
            $hasActiveLoan = true;
            $emis = max(0, (int)$row['emi_count']);
            $startDate = (string)$row['start_ym'];
            if (!$startDate || $emis <= 0) {
                continue;
            }
            $start = date('Y-m', strtotime($startDate));
            if (!preg_match('/^\d{4}-\d{2}$/', $start)) {
                continue;
            }
            $end = ym_add_months($start, $emis - 1);
            if (ym_cmp($monthKey, $start) < 0 || ym_cmp($monthKey, $end) > 0) {
                continue;
            }
            $emiAmt = 0.0;
            if ($row['emi_amount'] !== null && $row['emi_amount'] !== '') {
                $emiAmt = (float)$row['emi_amount'];
            } else {
                $total = (float)$row['total_amount'];
                $emiAmt = $total != 0.0 && $emis > 0 ? ($total / $emis) : 0.0;
            }
            $loanEmi += $emiAmt;
        }
        $loanStmt->close();
    }

    if ($HAS_LOANS_TBL && $HAS_LOAN_ADJ) {
        $adjStmt = $conn->prepare(
            "SELECT COALESCE(SUM(a.adj_amount),0) AS adj_sum
               FROM driver_loan_adjustments a
               JOIN driver_loans l ON l.id = a.loan_id
              WHERE DATE_FORMAT(a.adj_month, '%Y-%m') = ?
                AND l.driver_id = ?"
        );
        $adjStmt->bind_param('si', $monthKey, $driverId);
        $adjStmt->execute();
        $adjRow = $adjStmt->get_result()->fetch_assoc();
        $adjStmt->close();
        if ($adjRow) {
            $loanAdj = (float)$adjRow['adj_sum'];
        }
    }

    $HAS_MONTH_ADJ_TBL = table_exists($conn, 'driver_month_adjustments');
    if ($HAS_MONTH_ADJ_TBL && !$hasActiveLoan && $loanAdj == 0.0) {
        $adjStmt = $conn->prepare(
            "SELECT adj_amount FROM driver_month_adjustments WHERE month_key = ? AND driver_id = ? LIMIT 1"
        );
        $adjStmt->bind_param('si', $monthKey, $driverId);
        $adjStmt->execute();
        $adjRow = $adjStmt->get_result()->fetch_assoc();
        $adjStmt->close();
        if ($adjRow) {
            $loanAdj = (float)($adjRow['adj_amount'] ?? 0.0);
        }
    }

    $loanDeduct = $loanEmi + $loanAdj;

    $attMap = [];
    $attStmt = $conn->prepare(
        "SELECT
            DATE(COALESCE(a.in_time, a.out_time)) AS d,
            SUM(
              CASE
                WHEN a.in_time IS NOT NULL
                 AND UPPER(COALESCE(a.approval_status,'PENDING')) <> 'REJECTED'
                 AND (a.out_time IS NULL OR UPPER(COALESCE(a.approval_status,'PENDING')) <> 'APPROVED')
                THEN 1 ELSE 0
              END
            ) AS open_cnt,
            SUM(
              CASE
                WHEN a.in_time IS NOT NULL
                 AND a.out_time IS NOT NULL
                 AND UPPER(COALESCE(a.approval_status,'PENDING')) = 'APPROVED'
                THEN 1 ELSE 0
              END
            ) AS closed_cnt,
            SUM(
              CASE
                WHEN UPPER(COALESCE(a.approval_status,'PENDING')) = 'REJECTED'
                THEN 1 ELSE 0
              END
            ) AS rej_cnt
         FROM attendance a
         WHERE (
             (a.in_time  IS NOT NULL AND DATE(a.in_time)  BETWEEN ? AND ?)
          OR (a.out_time IS NOT NULL AND DATE(a.out_time) BETWEEN ? AND ?)
         )
           AND a.driver_id = ?
         GROUP BY DATE(COALESCE(a.in_time, a.out_time))"
    );
    $attStmt->bind_param('ssssi', $firstDay, $lastDay, $firstDay, $lastDay, $driverId);
    $attStmt->execute();
    $attRes = $attStmt->get_result();
    while ($row = $attRes->fetch_assoc()) {
        $d = (string)$row['d'];
        $attMap[$d] = [
            'P' => ((int)$row['closed_cnt']) > 0,
            'O' => ((int)$row['open_cnt']) > 0,
            'Ronly' => (((int)$row['closed_cnt'] + (int)$row['open_cnt']) === 0) && ((int)$row['rej_cnt'] > 0),
        ];
    }
    $attStmt->close();

    $holidayByDate = [];
    $addHoliday = function (&$map, string $date, ?int $pId, string $name): void {
        $k = $pId ?? 0;
        if (!isset($map[$date])) $map[$date] = [];
        $map[$date][$k] = $name;
    };

    if ($conn->query("SHOW TABLES LIKE 'national_holidays'")->num_rows) {
        $sql = "SELECT holiday_date,name,is_recurring FROM national_holidays
                WHERE is_active=1 AND ((is_recurring=1 AND MONTH(holiday_date)=MONTH(?)) OR (is_recurring=0 AND holiday_date BETWEEN ? AND ?))";
        $st = $conn->prepare($sql);
        $st->bind_param('sss', $firstDay, $firstDay, $lastDay);
        $st->execute();
        $res = $st->get_result();
        while ($row = $res->fetch_assoc()) {
            $mm = (int)date('m', strtotime($row['holiday_date']));
            $dd = (int)date('d', strtotime($row['holiday_date']));
            $dt = ((int)$row['is_recurring'] === 1)
                ? sprintf('%04d-%02d-%02d', $year, $mm, $dd)
                : $row['holiday_date'];
            $addHoliday($holidayByDate, $dt, null, $row['name']);
        }
        $st->close();
    }

    if ($conn->query("SHOW TABLES LIKE 'plant_holidays'")->num_rows) {
        $sql = "SELECT plant_id,holiday_date,name,is_recurring FROM plant_holidays
                WHERE is_active=1 AND ((is_recurring=1 AND MONTH(holiday_date)=MONTH(?)) OR (is_recurring=0 AND holiday_date BETWEEN ? AND ?))";
        $st = $conn->prepare($sql);
        $st->bind_param('sss', $firstDay, $firstDay, $lastDay);
        $st->execute();
        $res = $st->get_result();
        while ($row = $res->fetch_assoc()) {
            $mm = (int)date('m', strtotime($row['holiday_date']));
            $dd = (int)date('d', strtotime($row['holiday_date']));
            $dt = ((int)$row['is_recurring'] === 1)
                ? sprintf('%04d-%02d-%02d', $year, $mm, $dd)
                : $row['holiday_date'];
            $addHoliday(
                $holidayByDate,
                $dt,
                $row['plant_id'] !== null ? (int)$row['plant_id'] : null,
                $row['name']
            );
        }
        $st->close();
    }

    $ALWAYS_WORK_PLANTS = [39, 28, 54, 40, 46, 33, 61];
    $isAlwaysWorkPlant = ($plantId !== null && in_array($plantId, $ALWAYS_WORK_PLANTS, true));
    $restPlants = [33, 61, 54, 46, 39, 21, 28];

    $pC = $oC = $eC = $hC = $aC = $rC = 0;
    $hadPresenceSoFar = false;
    $dayStates = [];

    for ($d = 1; $d <= $daysInMonth; $d++) {
        $date = sprintf('%04d-%02d-%02d', $year, $month, $d);
        $isPastOrCutoff = ($date <= $cutoff);
        $sunday = (date('w', strtotime($date)) == '0');

        if ($isAlwaysWorkPlant) {
            $flag = $attMap[$date] ?? null;
            $presentOrOpen = ($flag && ($flag['P'] || $flag['O']));

            if ($presentOrOpen) {
        if ($flag['O']) {
            $dayStates[$date] = ['txt' => 'O', 'sunday' => $sunday];
            $oC++;
        } else {
            $dayStates[$date] = ['txt' => 'P', 'sunday' => $sunday];
            $pC++;
        }
        continue;
    }

    if ($isPastOrCutoff) {
        // ✅ Plant 33: Sunday absent should be R (not A)
            if (in_array((int)$plantId, $restPlants, true) && $sunday) {
                $dayStates[$date] = ['txt' => 'R', 'sunday' => $sunday];
                $rC++;
            } else {
            $dayStates[$date] = ['txt' => 'A', 'sunday' => $sunday];
            $aC++;
        }
    } else {
        $dayStates[$date] = ['txt' => '—', 'sunday' => $sunday];
    }
    continue;
}


        $flag = $attMap[$date] ?? null;
        $holidayName = null;
        if (isset($holidayByDate[$date])) {
            if ($plantId !== null && isset($holidayByDate[$date][$plantId])) {
                $holidayName = $holidayByDate[$date][$plantId];
            } elseif (isset($holidayByDate[$date][0])) {
                $holidayName = $holidayByDate[$date][0];
            }
        }
        $isHoliday = (bool)$holidayName;

        $presentOrOpen = ($flag && ($flag['P'] || $flag['O']));
        if ($presentOrOpen) $hadPresenceSoFar = true;
        $isContinuousAbsent = ($isPastOrCutoff && !$presentOrOpen && !$hadPresenceSoFar);

        if ($presentOrOpen && ($sunday || $isHoliday)) {
            $dayStates[$date] = ['txt' => 'E', 'sunday' => $sunday];
            $eC++;
        } elseif ($presentOrOpen && ($flag && $flag['O'])) {
            $dayStates[$date] = ['txt' => 'O', 'sunday' => $sunday];
            $oC++;
        } elseif ($presentOrOpen) {
            $dayStates[$date] = ['txt' => 'P', 'sunday' => $sunday];
            $pC++;
        } elseif ($isContinuousAbsent) {
            $dayStates[$date] = ['txt' => 'A', 'sunday' => $sunday];
            $aC++;
        } elseif ($isPastOrCutoff && $isHoliday) {
            $dayStates[$date] = ['txt' => 'H', 'sunday' => $sunday];
            $hC++;
        } elseif ($isPastOrCutoff && $sunday) {
            $dayStates[$date] = ['txt' => 'R', 'sunday' => $sunday];
            $rC++;
        } elseif ($isPastOrCutoff) {
            $dayStates[$date] = ['txt' => 'A', 'sunday' => $sunday];
            $aC++;
        } else {
            $dayStates[$date] = ['txt' => '—', 'sunday' => $sunday];
        }
    }

    foreach ($dayStates as $date => $state) {
        if (!$state['sunday']) continue;
        if ($date > $cutoff) continue;

    // ✅ Plant 33: do NOT auto-convert Sunday to A (Sat+Mon rule disabled)
        if (in_array((int)$plantId, $restPlants, true)) continue;

    $ts  = strtotime($date);
    $sat = date('Y-m-d', strtotime('-1 day', $ts));
    $mon = date('Y-m-d', strtotime('+1 day', $ts));

    if (!isset($dayStates[$sat]) || !isset($dayStates[$mon])) continue;
    if ($sat > $cutoff || $mon > $cutoff) continue;

    $satTxt = $dayStates[$sat]['txt'] ?? '';
    $monTxt = $dayStates[$mon]['txt'] ?? '';

    if ($satTxt === 'A' && $monTxt === 'A') {
        $curTxt = $dayStates[$date]['txt'] ?? '';
        if ($curTxt !== 'A') {

            // adjust counters for whatever we are replacing
            if ($curTxt === 'R') $rC = max(0, $rC - 1);
            if ($curTxt === 'H') $hC = max(0, $hC - 1);
            if ($curTxt === 'E') $eC = max(0, $eC - 1);
            if ($curTxt === 'P') $pC = max(0, $pC - 1);
            if ($curTxt === 'O') $oC = max(0, $oC - 1);

            // set Sunday as A
            $aC++;
            $dayStates[$date]['txt'] = 'A';
        }
    }
}


    $workingDays = $pC + $eC + $hC;
    $totalDays = $aC + $pC + $rC + $eC;
    $totalPaidDays = $pC + $rC + $eC;
    $holidayTaken = $totalDays - $totalPaidDays - $eC;

    $holidayDeduction = ($daysInMonth > 0)
        ? ($salaryNum / $daysInMonth) * $holidayTaken
        : 0.0;

    $totalDeduction = $advanceBal + $loanDeduct + $holidayDeduction;

    $pfEnabled = ($uanVal !== '');
    $esicEnabled = ($esiVal !== '');

    $pfSalary = $salaryNum - $holidayDeduction;
    if ($pfEnabled) {
        $empPf = ($daysInMonth > 0)
            ? round((1800.0 / $daysInMonth) * $totalPaidDays, 2)
            : 0.0;
        $erPf = $empPf;
    } else {
        $empPf = 0.0;
        $erPf = 0.0;
    }

    $empEsic = $esicEnabled ? round(0.0075 * $pfSalary, 2) : 0.0;
    $erEsic = $esicEnabled ? round(0.0325 * $pfSalary, 2) : 0.0;

    $remSalary = $salaryNum - $totalDeduction - $empPf - $empEsic;

    apiRespond(200, [
        'status' => 'ok',
        'driverId' => $driverId,
        'month' => $monthKey,
        'salary' => round($salaryNum, 2),
        'advance' => round($advanceBal, 2),
        'total_days' => (int)$totalDays,
        'total_paid_days' => (int)$totalPaidDays,
        'holiday_taken' => (int)$holidayTaken,
        'holiday_deduction' => round($holidayDeduction, 2),
        'total_deduction' => round($totalDeduction, 2),
        'pf_salary' => round($pfSalary, 2),
        'emp_pf' => round($empPf, 2),
        'emp_esic' => round($empEsic, 2),
        'rem_salary' => round($remSalary, 2),
        'er_pf' => round($erPf, 2),
        'er_esic' => round($erEsic, 2),
    ]);
} catch (Throwable $error) {
    apiRespond(500, ['status' => 'error', 'error' => $error->getMessage()]);
}
