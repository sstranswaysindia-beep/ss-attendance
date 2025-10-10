class AttendanceRecord {
  const AttendanceRecord({
    required this.attendanceId,
    required this.driverId,
    this.plantId,
    this.plantName,
    this.vehicleId,
    this.vehicleNumber,
    this.assignmentId,
    this.inTime,
    this.outTime,
    this.inPhotoUrl,
    this.outPhotoUrl,
    this.status,
    this.notes,
    this.pendingSync = false,
    this.source,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      attendanceId: json['attendanceId']?.toString() ?? json['id']?.toString() ?? '',
      driverId: json['driverId']?.toString() ?? '',
      plantId: json['plantId']?.toString(),
      plantName: json['plantName']?.toString(),
      vehicleId: json['vehicleId']?.toString(),
      vehicleNumber: json['vehicleNumber']?.toString(),
      assignmentId: json['assignmentId']?.toString(),
      inTime: json['inTime']?.toString(),
      outTime: json['outTime']?.toString(),
      inPhotoUrl: json['inPhotoUrl']?.toString(),
      outPhotoUrl: json['outPhotoUrl']?.toString(),
      status: json['status']?.toString(),
      notes: json['notes']?.toString(),
      pendingSync: json['pendingSync'] == 1 || json['pendingSync'] == true,
      source: json['source']?.toString(),
    );
  }

  final String attendanceId;
  final String driverId;
  final String? plantId;
  final String? plantName;
  final String? vehicleId;
  final String? vehicleNumber;
  final String? assignmentId;
  final String? inTime;
  final String? outTime;
  final String? inPhotoUrl;
  final String? outPhotoUrl;
  final String? status;
  final String? notes;
  final bool pendingSync;
  final String? source;

  bool get isAdjustRequest => source == 'adjust_request';
}
