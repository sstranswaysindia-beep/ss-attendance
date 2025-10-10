class TripDriver {
  const TripDriver({
    required this.id,
    required this.name,
    this.plantId,
    this.role,
    this.supervisorName,
  });

  final int id;
  final String name;
  final int? plantId;
  final String? role;
  final String? supervisorName;

  factory TripDriver.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic value) {
      final str = value?.toString();
      if (str == null) return null;
      return int.tryParse(str);
    }

    return TripDriver(
      id: parseInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? '',
      plantId: parseInt(json['plant_id']),
      role: json['role']?.toString(),
      supervisorName: json['supervisor_name']?.toString(),
    );
  }
}
