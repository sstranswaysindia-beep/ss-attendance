class TripSheetRecord {
  const TripSheetRecord({
    required this.id,
    required this.userId,
    this.driverId,
    required this.plantId,
    required this.plantName,
    required this.vehicleId,
    required this.vehicleNumber,
    required this.userRole,
    required this.imageUrl,
    this.notes,
    required this.createdAt,
  });

  factory TripSheetRecord.fromJson(Map<String, dynamic> json) {
    return TripSheetRecord(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      userId: int.tryParse(json['user_id']?.toString() ?? '') ?? 0,
      driverId: int.tryParse(json['driver_id']?.toString() ?? ''),
      plantId: int.tryParse(json['plant_id']?.toString() ?? '') ?? 0,
      plantName: json['plant_name']?.toString() ?? '',
      vehicleId: int.tryParse(json['vehicle_id']?.toString() ?? '') ?? 0,
      vehicleNumber: json['vehicle_number']?.toString() ?? '',
      userRole: json['user_role']?.toString() ?? 'driver',
      imageUrl: json['image_url']?.toString() ?? '',
      notes: json['notes']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  final int id;
  final int userId;
  final int? driverId;
  final int plantId;
  final String plantName;
  final int vehicleId;
  final String vehicleNumber;
  final String userRole;
  final String imageUrl;
  final String? notes;
  final DateTime createdAt;
}
