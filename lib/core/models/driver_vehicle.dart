class DriverVehicle {
  const DriverVehicle({
    required this.id,
    required this.vehicleNumber,
    this.plantId,
  });

  final String id;
  final String vehicleNumber;
  final int? plantId;

  factory DriverVehicle.fromJson(Map<String, dynamic> json) {
    return DriverVehicle(
      id: json['id']?.toString() ?? '',
      vehicleNumber: json['vehicleNumber']?.toString() ?? json['vehicle_no']?.toString() ?? '',
      plantId: json['plantId'] != null ? int.tryParse(json['plantId'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'vehicleNumber': vehicleNumber,
      'plantId': plantId,
    };
  }
}
