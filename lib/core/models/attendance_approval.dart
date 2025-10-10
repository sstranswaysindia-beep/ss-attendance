class AttendanceApproval {
  const AttendanceApproval({
    required this.attendanceId,
    required this.driverId,
    required this.driverName,
    required this.plantId,
    required this.plantName,
    this.vehicleId,
    this.vehicleNumber,
    this.inTime,
    this.outTime,
    this.inPhotoUrl,
    this.outPhotoUrl,
    this.status,
    this.source,
    this.notes,
    this.createdAt,
  });

  factory AttendanceApproval.fromJson(Map<String, dynamic> json) {
    return AttendanceApproval(
      attendanceId: json['attendanceId']?.toString() ?? '',
      driverId: json['driverId']?.toString() ?? '',
      driverName: json['driverName']?.toString() ?? '',
      plantId: json['plantId']?.toString() ?? '',
      plantName: json['plantName']?.toString() ?? '',
      vehicleId: json['vehicleId']?.toString(),
      vehicleNumber: json['vehicleNumber']?.toString(),
      inTime: json['inTime']?.toString(),
      outTime: json['outTime']?.toString(),
      inPhotoUrl: json['inPhotoUrl']?.toString(),
      outPhotoUrl: json['outPhotoUrl']?.toString(),
      status: json['status']?.toString(),
      source: json['source']?.toString(),
      notes: json['notes']?.toString(),
      createdAt: json['createdAt']?.toString(),
    );
  }

  final String attendanceId;
  final String driverId;
  final String driverName;
  final String plantId;
  final String plantName;
  final String? vehicleId;
  final String? vehicleNumber;
  final String? inTime;
  final String? outTime;
  final String? inPhotoUrl;
  final String? outPhotoUrl;
  final String? status;
  final String? source;
  final String? notes;
  final String? createdAt;
}

class SupervisorPlantOption {
  const SupervisorPlantOption({
    required this.plantId,
    required this.plantName,
  });

  factory SupervisorPlantOption.fromJson(Map<String, dynamic> json) {
    return SupervisorPlantOption(
      plantId: json['plantId']?.toString() ?? '',
      plantName: json['plantName']?.toString() ?? '',
    );
  }

  final String plantId;
  final String plantName;
}
