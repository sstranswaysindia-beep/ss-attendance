class DriverAbsenceStatus {
  const DriverAbsenceStatus({
    required this.isAbsent,
    this.note,
    this.supervisorUserId,
    this.absenceDate,
    this.plantId,
  });

  final bool isAbsent;
  final String? note;
  final int? supervisorUserId;
  final DateTime? absenceDate;
  final int? plantId;

  factory DriverAbsenceStatus.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      final raw = value?.toString();
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    }

    return DriverAbsenceStatus(
      isAbsent:
          json['isAbsent'] == true || json['isAbsent']?.toString() == '1',
      note: json['note']?.toString(),
      supervisorUserId: json['supervisorUserId'] != null
          ? int.tryParse(json['supervisorUserId'].toString())
          : null,
      absenceDate: parseDate(json['absenceDate']),
      plantId: json['plantId'] != null
          ? int.tryParse(json['plantId'].toString())
          : null,
    );
  }
}
