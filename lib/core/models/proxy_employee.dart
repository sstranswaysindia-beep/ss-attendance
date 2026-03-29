import 'package:intl/intl.dart';

class ProxyEmployee {
  const ProxyEmployee({
    required this.userId,
    required this.driverId,
    required this.fullName,
    required this.username,
    required this.plantId,
    required this.plantName,
    required this.driverRole,
    required this.hasOpenShift,
    this.lastCheckIn,
    this.lastCheckOut,
  });

  factory ProxyEmployee.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic raw) {
      final value = raw?.toString();
      if (value == null || value.isEmpty) {
        return null;
      }
      return DateTime.tryParse(value);
    }

    return ProxyEmployee(
      userId: json['userId']?.toString() ?? '',
      driverId: json['driverId']?.toString() ?? '',
      fullName:
          json['fullName']?.toString() ?? json['driverName']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      plantId: json['plantId']?.toString(),
      plantName: json['plantName']?.toString(),
      driverRole: json['driverRole']?.toString(),
      hasOpenShift:
          json['hasOpenShift'] == true ||
          json['hasOpenShift']?.toString() == '1',
      lastCheckIn: parseDate(json['lastCheckIn']),
      lastCheckOut: parseDate(json['lastCheckOut']),
    );
  }

  final String userId;
  final String driverId;
  final String fullName;
  final String username;
  final String? plantId;
  final String? plantName;
  final String? driverRole;
  final bool hasOpenShift;
  final DateTime? lastCheckIn;
  final DateTime? lastCheckOut;

  DateTime _normalizeDate(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  bool _isSameDay(DateTime? value, DateTime referenceDate) {
    if (value == null) return false;
    final normalized = _normalizeDate(value);
    return normalized == _normalizeDate(referenceDate);
  }

  bool hasCheckInOn(DateTime referenceDate) =>
      _isSameDay(lastCheckIn, referenceDate);

  bool hasCheckOutOn(DateTime referenceDate) =>
      _isSameDay(lastCheckOut, referenceDate);

  bool hasOpenShiftOn(DateTime referenceDate) =>
      hasOpenShift &&
      hasCheckInOn(referenceDate) &&
      !hasCheckOutOn(referenceDate);

  bool attendanceCompletedOn(DateTime referenceDate) =>
      hasCheckInOn(referenceDate) &&
      hasCheckOutOn(referenceDate) &&
      !hasOpenShiftOn(referenceDate);

  bool hasAttendanceOn(DateTime referenceDate) =>
      hasCheckInOn(referenceDate) || hasCheckOutOn(referenceDate);

  String statusLabelFor(DateTime referenceDate) {
    if (hasOpenShiftOn(referenceDate)) {
      return 'Checked in';
    }
    if (attendanceCompletedOn(referenceDate)) {
      return 'Checked out';
    }
    if (!hasAttendanceOn(referenceDate)) {
      return 'No attendance';
    }
    return 'Pending';
  }

  String get roleBadge {
    final normalized = (driverRole ?? '').toLowerCase();
    if (normalized == 'helper') {
      return 'Helper';
    }
    if (normalized == 'supervisor') {
      return 'Supervisor';
    }
    return 'Driver';
  }

  String lastCheckInDisplay([DateFormat? formatter]) {
    final date = lastCheckIn;
    if (date == null) return '—';
    final fmt = formatter ?? DateFormat('dd MMM • HH:mm');
    return fmt.format(date);
  }

  String lastCheckInDisplayFor(
    DateTime referenceDate, [
    DateFormat? formatter,
  ]) {
    if (!hasCheckInOn(referenceDate)) return '—';
    return lastCheckInDisplay(formatter);
  }

  String lastCheckOutDisplay([DateFormat? formatter]) {
    final date = lastCheckOut;
    if (date == null) {
      return '—';
    }
    final fmt = formatter ?? DateFormat('dd MMM • HH:mm');
    return fmt.format(date);
  }

  String lastCheckOutDisplayFor(
    DateTime referenceDate, [
    DateFormat? formatter,
  ]) {
    if (hasOpenShiftOn(referenceDate)) return 'Pending';
    if (!hasCheckOutOn(referenceDate)) return '—';
    return lastCheckOutDisplay(formatter);
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get hasCheckInToday => hasCheckInOn(_today());

  bool get hasCheckOutToday => hasCheckOutOn(_today());

  bool get hasOpenShiftToday => hasOpenShiftOn(_today());

  bool get attendanceCompletedToday => attendanceCompletedOn(_today());

  bool get hasAttendanceToday => hasAttendanceOn(_today());

  String get statusLabel => statusLabelFor(_today());
}

class ProxyAttendanceResponse {
  const ProxyAttendanceResponse({
    required this.employees,
    required this.plants,
  });

  final List<ProxyEmployee> employees;
  final List<ProxyPlantOption> plants;
}

class ProxyPlantOption {
  const ProxyPlantOption({required this.plantId, required this.plantName});

  factory ProxyPlantOption.fromJson(Map<String, dynamic> json) {
    return ProxyPlantOption(
      plantId: json['plantId']?.toString() ?? '',
      plantName: json['plantName']?.toString() ?? '',
    );
  }

  final String plantId;
  final String plantName;
}
