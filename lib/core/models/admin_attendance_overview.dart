import 'package:intl/intl.dart';

class AdminAttendanceOverview {
  const AdminAttendanceOverview({
    required this.month,
    required this.startDate,
    required this.endDate,
    required this.totalDays,
    required this.generatedAt,
    required this.driverCount,
    required this.drivers,
  });

  factory AdminAttendanceOverview.fromJson(Map<String, dynamic> json) {
    final driversJson = json['drivers'] as List<dynamic>? ?? const [];
    return AdminAttendanceOverview(
      month: json['month']?.toString() ?? '',
      startDate: DateTime.tryParse(json['startDate']?.toString() ?? ''),
      endDate: DateTime.tryParse(json['endDate']?.toString() ?? ''),
      totalDays: json['totalDays'] is int
          ? json['totalDays'] as int
          : int.tryParse(json['totalDays']?.toString() ?? '') ?? 0,
      generatedAt: DateTime.tryParse(json['generatedAt']?.toString() ?? ''),
      driverCount: json['driverCount'] is int
          ? json['driverCount'] as int
          : int.tryParse(json['driverCount']?.toString() ?? '') ??
                driversJson.length,
      drivers: driversJson
          .map(
            (driver) => DriverAttendanceOverview.fromJson(
              driver as Map<String, dynamic>,
            ),
          )
          .toList(growable: false),
    );
  }

  final String month;
  final DateTime? startDate;
  final DateTime? endDate;
  final int totalDays;
  final DateTime? generatedAt;
  final int driverCount;
  final List<DriverAttendanceOverview> drivers;

  String get formattedMonth {
    if (month.isEmpty) return '';
    final parsed = DateTime.tryParse('$month-01');
    if (parsed == null) return month;
    return DateFormat('MMMM yyyy').format(parsed);
  }
}

class DriverAttendanceOverview {
  const DriverAttendanceOverview({
    required this.driverId,
    required this.driverName,
    required this.role,
    required this.plantId,
    required this.plantName,
    required this.profilePhoto,
    required this.daysWorked,
    required this.totalDays,
    required this.datesWorked,
  });

  final int driverId;
  final String driverName;
  final String role;
  final int? plantId;
  final String? plantName;
  final String profilePhoto;
  final int daysWorked;
  final int totalDays;
  final List<String> datesWorked;

  factory DriverAttendanceOverview.fromJson(Map<String, dynamic> json) {
    final rawDates = json['datesWorked'];
    final List<String> parsedDates;
    if (rawDates is List) {
      parsedDates = rawDates
          .map((value) => value?.toString() ?? '')
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    } else if (rawDates is String) {
      parsedDates = rawDates
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    } else {
      parsedDates = const [];
    }

    return DriverAttendanceOverview(
      driverId: json['driverId'] is int
          ? json['driverId'] as int
          : int.tryParse(json['driverId']?.toString() ?? '') ?? 0,
      driverName: json['driverName']?.toString() ?? 'Unknown',
      role: json['role']?.toString() ?? '',
      plantId: json['plantId'] is int
          ? json['plantId'] as int
          : int.tryParse(json['plantId']?.toString() ?? ''),
      plantName: json['plantName']?.toString(),
      profilePhoto: json['profilePhoto']?.toString() ?? '',
      daysWorked: json['daysWorked'] is int
          ? json['daysWorked'] as int
          : int.tryParse(json['daysWorked']?.toString() ?? '') ?? 0,
      totalDays: json['totalDays'] is int
          ? json['totalDays'] as int
          : int.tryParse(json['totalDays']?.toString() ?? '') ?? 0,
      datesWorked: parsedDates,
    );
  }

  double get attendancePercentage {
    if (totalDays <= 0) return 0;
    return (daysWorked / totalDays) * 100;
  }

  String get displayRole {
    if (role.isEmpty) return 'Driver';
    final normalized = role.replaceAll('_', ' ').trim();
    if (normalized.isEmpty) return 'Driver';
    return normalized
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              part.substring(0, 1).toUpperCase() +
              part.substring(1).toLowerCase(),
        )
        .join(' ');
  }

  String get displayPlant {
    if ((plantName ?? '').trim().isEmpty) {
      return 'No plant assigned';
    }
    return plantName!;
  }

  String get initials {
    final parts = driverName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'D';
    if (parts.length == 1) {
      final word = parts.first;
      return word.length >= 2
          ? word.substring(0, 2).toUpperCase()
          : word.substring(0, 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  bool get hasProfilePhoto {
    if (profilePhoto.isEmpty) return false;
    final uri = Uri.tryParse(profilePhoto);
    if (uri == null) return false;
    return uri.hasScheme && uri.hasAuthority;
  }

  List<DateTime> get workedDates {
    return datesWorked
        .map((value) => DateTime.tryParse(value))
        .whereType<DateTime>()
        .toList(growable: false);
  }
}
