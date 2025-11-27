class SupervisorTodayAttendanceDriver {
  const SupervisorTodayAttendanceDriver({
    required this.driverId,
    required this.driverName,
    required this.hasCheckIn,
    required this.hasCheckOut,
    required this.isAbsent,
    this.profilePhoto,
    this.checkInTime,
    this.checkOutTime,
    this.role,
    this.absenceNote,
    this.absenceMarkedBy,
  });

  final int driverId;
  final String driverName;
  final bool hasCheckIn;
  final bool hasCheckOut;
  final bool isAbsent;
  final String? profilePhoto;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final String? role;
  final String? absenceNote;
  final int? absenceMarkedBy;

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
      isAbsent:
          json['isAbsent'] == true || json['isAbsent']?.toString() == '1',
      profilePhoto: json['profilePhoto']?.toString(),
      checkInTime: parseDate(json['checkInTime']),
      checkOutTime: parseDate(json['checkOutTime']),
      absenceNote: json['absenceNote']?.toString(),
      absenceMarkedBy: json['absenceMarkedBy'] != null
          ? int.tryParse(json['absenceMarkedBy'].toString())
          : null,
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

  SupervisorTodayAttendanceDriver copyWith({
    bool? hasCheckIn,
    bool? hasCheckOut,
    bool? isAbsent,
    String? profilePhoto,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    String? role,
    String? absenceNote,
    int? absenceMarkedBy,
  }) {
    return SupervisorTodayAttendanceDriver(
      driverId: driverId,
      driverName: driverName,
      hasCheckIn: hasCheckIn ?? this.hasCheckIn,
      hasCheckOut: hasCheckOut ?? this.hasCheckOut,
      isAbsent: isAbsent ?? this.isAbsent,
      profilePhoto: profilePhoto ?? this.profilePhoto,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOutTime: checkOutTime ?? this.checkOutTime,
      role: role ?? this.role,
      absenceNote: absenceNote ?? this.absenceNote,
      absenceMarkedBy: absenceMarkedBy ?? this.absenceMarkedBy,
    );
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

  SupervisorTodayAttendancePlant copyWith({
    List<SupervisorTodayAttendanceDriver>? drivers,
  }) {
    return SupervisorTodayAttendancePlant(
      plantId: plantId,
      plantName: plantName,
      drivers: drivers ?? this.drivers,
    );
  }
}
