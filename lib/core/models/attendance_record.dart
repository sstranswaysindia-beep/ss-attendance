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
    this.inLocationJson,
    this.outLocationJson,
    this.inPhotoUrl,
    this.outPhotoUrl,
    this.status,
    this.notes,
    this.pendingSync = false,
    this.source,
    this.geofence,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      attendanceId:
          json['attendanceId']?.toString() ??
          json['attendance_id']?.toString() ??
          json['id']?.toString() ??
          '',
      driverId:
          json['driverId']?.toString() ?? json['driver_id']?.toString() ?? '',
      plantId: json['plantId']?.toString() ?? json['plant_id']?.toString(),
      plantName:
          json['plantName']?.toString() ?? json['plant_name']?.toString(),
      vehicleId:
          json['vehicleId']?.toString() ?? json['vehicle_id']?.toString(),
      vehicleNumber:
          json['vehicleNumber']?.toString() ??
          json['vehicle_number']?.toString() ??
          json['vehicle_no']?.toString(),
      assignmentId:
          json['assignmentId']?.toString() ?? json['assignment_id']?.toString(),
      inTime:
          json['inTime']?.toString() ??
          json['in_time']?.toString() ??
          json['check_in']?.toString(),
      outTime:
          json['outTime']?.toString() ??
          json['out_time']?.toString() ??
          json['check_out']?.toString(),
      inLocationJson:
          json['inLocationJson']?.toString() ??
          json['in_location_json']?.toString(),
      outLocationJson:
          json['outLocationJson']?.toString() ??
          json['out_location_json']?.toString(),
      inPhotoUrl:
          json['inPhotoUrl']?.toString() ?? json['in_photo_url']?.toString(),
      outPhotoUrl:
          json['outPhotoUrl']?.toString() ?? json['out_photo_url']?.toString(),
      status: json['status']?.toString() ?? json['approval_status']?.toString(),
      notes: json['notes']?.toString(),
      pendingSync: json['pendingSync'] == 1 || json['pendingSync'] == true,
      source: json['source']?.toString() ?? json['type']?.toString(),
      geofence: json['geofence'] is Map<String, dynamic>
          ? json['geofence'] as Map<String, dynamic>
          : json['geofence'] is Map
          ? Map<String, dynamic>.from(json['geofence'] as Map)
          : null,
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
  final String? inLocationJson;
  final String? outLocationJson;
  final String? inPhotoUrl;
  final String? outPhotoUrl;
  final String? status;
  final String? notes;
  final bool pendingSync;
  final String? source;
  final Map<String, dynamic>? geofence;

  bool get isAdjustRequest => source == 'adjust_request';
}
