class AttendanceSalaryDetails {
  const AttendanceSalaryDetails({
    required this.salary,
    required this.advance,
    required this.totalDays,
    required this.totalPaidDays,
    required this.holidayTaken,
    required this.holidayDeduction,
    required this.totalDeduction,
    required this.pfSalary,
    required this.empPf,
    required this.empEsic,
    required this.remSalary,
    required this.erPf,
    required this.erEsic,
  });

  factory AttendanceSalaryDetails.fromJson(Map<String, dynamic> json) {
    double readDouble(String key) =>
        (json[key] is num) ? (json[key] as num).toDouble() : 0.0;
    int readInt(String key) =>
        (json[key] is num) ? (json[key] as num).toInt() : 0;

    return AttendanceSalaryDetails(
      salary: readDouble('salary'),
      advance: readDouble('advance'),
      totalDays: readInt('total_days'),
      totalPaidDays: readInt('total_paid_days'),
      holidayTaken: readInt('holiday_taken'),
      holidayDeduction: readDouble('holiday_deduction'),
      totalDeduction: readDouble('total_deduction'),
      pfSalary: readDouble('pf_salary'),
      empPf: readDouble('emp_pf'),
      empEsic: readDouble('emp_esic'),
      remSalary: readDouble('rem_salary'),
      erPf: readDouble('er_pf'),
      erEsic: readDouble('er_esic'),
    );
  }

  final double salary;
  final double advance;
  final int totalDays;
  final int totalPaidDays;
  final int holidayTaken;
  final double holidayDeduction;
  final double totalDeduction;
  final double pfSalary;
  final double empPf;
  final double empEsic;
  final double remSalary;
  final double erPf;
  final double erEsic;
}
