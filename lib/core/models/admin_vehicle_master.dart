class AdminVehicle {
  const AdminVehicle({
    required this.id,
    required this.vehicleNumber,
    required this.plantName,
    this.plantId,
    this.gps,
    this.company,
    this.location,
    this.modelNumber,
    this.registrationDate,
    this.fitnessExpiry,
    this.insuranceExpiry,
    this.pollutionExpiry,
    this.brakeTestExpiry,
  });

  final int id;
  final String vehicleNumber;
  final String plantName;
  final int? plantId;
  final String? gps;
  final String? company;
  final String? location;
  final String? modelNumber;
  final DateTime? registrationDate;
  final DateTime? fitnessExpiry;
  final DateTime? insuranceExpiry;
  final DateTime? pollutionExpiry;
  final DateTime? brakeTestExpiry;

  factory AdminVehicle.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      final raw = value?.toString();
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    }

    return AdminVehicle(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      vehicleNumber: json['vehicleNo']?.toString() ?? '',
      plantName: json['plantName']?.toString() ?? '',
      plantId: int.tryParse(json['plantId']?.toString() ?? ''),
      gps: json['gps']?.toString(),
      company: json['company']?.toString(),
      location: json['location']?.toString(),
      modelNumber: json['modelNo']?.toString(),
      registrationDate: parseDate(json['registrationDate']),
      fitnessExpiry: parseDate(json['fitnessExpiry']),
      insuranceExpiry: parseDate(json['insuranceExpiry']),
      pollutionExpiry: parseDate(json['pollutionExpiry']),
      brakeTestExpiry: parseDate(json['brakeTestExpiry']),
    );
  }

  String get displayTitle => vehicleNumber.isEmpty ? 'Vehicle #$id' : vehicleNumber;
}
