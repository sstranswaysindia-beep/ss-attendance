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

  String get statusLabel {
    if (hasOpenShift) {
      return 'Checked in';
    }
    if (lastCheckIn == null) {
      return 'No attendance';
    }
    return 'Checked out';
  }

  bool get attendanceCompleted =>
      !hasOpenShift && lastCheckIn != null && lastCheckOut != null;

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
    if (date == null) {
      return '—';
    }
    final fmt = formatter ?? DateFormat('dd MMM • HH:mm');
    return fmt.format(date);
  }

  String lastCheckOutDisplay([DateFormat? formatter]) {
    final date = lastCheckOut;
    if (date == null) {
      return hasOpenShift ? 'Pending' : '—';
    }
    final fmt = formatter ?? DateFormat('dd MMM • HH:mm');
    return fmt.format(date);
  }
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
