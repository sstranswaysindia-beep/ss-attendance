class SalaryDistributionRow {
  const SalaryDistributionRow({
    required this.driverId,
    required this.plantId,
    required this.plant,
    required this.employee,
    required this.key,
    required this.category,
    required this.vehicleNumber,
    required this.billingDone,
    required this.advance,
    required this.loanEmi,
    required this.loanAdj,
    required this.da,
    required this.remainingSalary,
    required this.training,
    required this.esiEmployee,
    required this.pfEmployee,
    required this.esiEmployer,
    required this.pfEmployer,
    required this.medical,
    required this.uniform,
    required this.safetyShoes,
    required this.travel,
    required this.room,
    required this.incentive,
    required this.extra,
    required this.paper,
    required this.empPaper,
    required this.total,
    required this.baseSalary,
    required this.totalDays,
    required this.totalPaidDays,
    required this.holidayTaken,
    required this.holidayDeduction,
  });

  factory SalaryDistributionRow.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
    double asDouble(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
    bool asBool(dynamic v) {
      if (v is bool) return v;
      final s = (v?.toString() ?? '').trim().toLowerCase();
      return s == '1' || s == 'true' || s == 'y' || s == 'yes';
    }

    return SalaryDistributionRow(
      driverId: asInt(json['driver_id']),
      plantId: asInt(json['plant_id']),
      plant: (json['plant'] ?? '').toString(),
      employee: (json['employee'] ?? '').toString(),
      key: (json['key'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      vehicleNumber: (json['vehicle_number'] ?? '').toString(),
      billingDone: asBool(json['billing_done']),
      advance: asDouble(json['advance']),
      loanEmi: asDouble(json['loan']),
      loanAdj: asDouble(json['adj']),
      da: asDouble(json['da']),
      remainingSalary: asDouble(json['remaining_salary']),
      training: asDouble(json['training']),
      esiEmployee: asDouble(json['esi_employee']),
      pfEmployee: asDouble(json['pf_employee']),
      esiEmployer: asDouble(json['esi_employer']),
      pfEmployer: asDouble(json['pf_employer']),
      medical: asDouble(json['medical']),
      uniform: asDouble(json['uniform']),
      safetyShoes: asDouble(json['safety_shoes']),
      travel: asDouble(json['travel']),
      room: asDouble(json['room']),
      incentive: asDouble(json['incentive']),
      extra: asDouble(json['extra']),
      paper: asDouble(json['paper']),
      empPaper: asDouble(json['emp_paper']),
      total: asDouble(json['total']),
      baseSalary: asDouble(json['base_salary']),
      totalDays: asInt(json['total_days']),
      totalPaidDays: asInt(json['total_paid_days']),
      holidayTaken: asInt(json['holiday_taken']),
      holidayDeduction: asDouble(json['holiday_deduction']),
    );
  }

  final int driverId;
  final int plantId;
  final String plant;
  final String employee;
  final String key;
  final String category;
  final String vehicleNumber;
  final bool billingDone;

  final double advance;
  final double loanEmi;
  final double loanAdj;
  final double da;
  final double remainingSalary;
  final double training;
  final double esiEmployee;
  final double pfEmployee;
  final double esiEmployer;
  final double pfEmployer;
  final double medical;
  final double uniform;
  final double safetyShoes;
  final double travel;
  final double room;
  final double incentive;
  final double extra;
  final double paper;
  final double empPaper;
  final double total;

  final double baseSalary;
  final int totalDays;
  final int totalPaidDays;
  final int holidayTaken;
  final double holidayDeduction;
}
