class MonthlyStat {
  const MonthlyStat({
    required this.month,
    required this.daysPresent,
    this.totalHours,
    this.averageInTime,
    this.averageHours,
  });

  factory MonthlyStat.fromJson(Map<String, dynamic> json) {
    return MonthlyStat(
      month: json['month']?.toString() ?? '',
      daysPresent: int.tryParse(json['daysPresent']?.toString() ?? '') ?? 0,
      totalHours: json['totalHours']?.toString(),
      averageInTime: json['averageInTime']?.toString(),
      averageHours: json['averageHours']?.toString(),
    );
  }

  final String month;
  final int daysPresent;
  final String? totalHours;
  final String? averageInTime;
  final String? averageHours;
}
