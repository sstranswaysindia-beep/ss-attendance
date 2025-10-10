class DailyAttendanceSummary {
  const DailyAttendanceSummary({
    required this.dateLabel,
    required this.inTimes,
    required this.outTimes,
    required this.totalMinutes,
    this.hasOpenShift = false,
  });

  final String dateLabel;
  final List<String> inTimes;
  final List<String> outTimes;
  final int totalMinutes;
  final bool hasOpenShift;

  String get formattedDuration {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
  }
}
