class SupervisorTodayAttendanceDriver {
  const SupervisorTodayAttendanceDriver({
    required this.driverId,
    required this.driverName,
    required this.hasCheckIn,
    required this.hasCheckOut,
    this.profilePhoto,
    this.checkInTime,
    this.checkOutTime,
    this.role,
  });

  final int driverId;
  final String driverName;
  final bool hasCheckIn;
  final bool hasCheckOut;
  final String? profilePhoto;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final String? role;

  factory SupervisorTodayAttendanceDriver.fromJson(
    Map<String, dynamic> json,
  ) {
    DateTime? parseDate(dynamic value) {
      final raw = value?.toString();
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    }

    return SupervisorTodayAttendanceDriver(
      driverId: int.tryParse(json['driverId']?.toString() ?? '') ?? 0,
      driverName: json['driverName']?.toString() ?? '',
      role: json['role']?.toString(),
      hasCheckIn:
          json['hasCheckIn'] == true || json['hasCheckIn']?.toString() == '1',
      hasCheckOut:
          json['hasCheckOut'] == true || json['hasCheckOut']?.toString() == '1',
      profilePhoto: json['profilePhoto']?.toString(),
      checkInTime: parseDate(json['checkInTime']),
      checkOutTime: parseDate(json['checkOutTime']),
    );
  }

  String get roleBadge {
    switch ((role ?? '').toLowerCase()) {
      case 'helper':
        return 'H';
      case 'supervisor':
        return 'S';
      case 'driver':
      default:
        return 'D';
    }
  }
}

class SupervisorTodayAttendancePlant {
  const SupervisorTodayAttendancePlant({
    required this.plantId,
    required this.plantName,
    required this.drivers,
  });

  final int plantId;
  final String plantName;
  final List<SupervisorTodayAttendanceDriver> drivers;

  factory SupervisorTodayAttendancePlant.fromJson(
    Map<String, dynamic> json,
  ) {
    final driversJson = json['drivers'] as List<dynamic>? ?? const [];
    return SupervisorTodayAttendancePlant(
      plantId: int.tryParse(json['plantId']?.toString() ?? '') ?? 0,
      plantName: json['plantName']?.toString() ?? '',
      drivers: driversJson
          .map(
            (item) => SupervisorTodayAttendanceDriver.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(growable: false),
    );
  }
}
