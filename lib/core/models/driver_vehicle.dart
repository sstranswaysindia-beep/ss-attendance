class DriverVehicle {
  const DriverVehicle({
    required this.id,
    required this.vehicleNumber,
  });

  final String id;
  final String vehicleNumber;

  factory DriverVehicle.fromJson(Map<String, dynamic> json) {
    return DriverVehicle(
      id: json['id']?.toString() ?? '',
      vehicleNumber: json['vehicleNumber']?.toString() ?? json['vehicle_no']?.toString() ?? '',
    );
  }
}
