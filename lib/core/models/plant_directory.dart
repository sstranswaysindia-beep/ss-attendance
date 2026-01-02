class PlantDirectoryEntry {
  PlantDirectoryEntry({
    required this.id,
    required this.name,
    required this.vehicles,
    required this.drivers,
  });

  factory PlantDirectoryEntry.fromJson(Map<String, dynamic> json) {
    return PlantDirectoryEntry(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      vehicles: (json['vehicles'] as List<dynamic>? ?? const [])
          .map((item) => PlantDirectoryVehicle.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      drivers: (json['drivers'] as List<dynamic>? ?? const [])
          .map((item) => PlantDirectoryDriver.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  final int id;
  final String name;
  final List<PlantDirectoryVehicle> vehicles;
  final List<PlantDirectoryDriver> drivers;
}

class PlantDirectoryVehicle {
  const PlantDirectoryVehicle({required this.id, required this.number});

  factory PlantDirectoryVehicle.fromJson(Map<String, dynamic> json) {
    return PlantDirectoryVehicle(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      number: json['number']?.toString() ?? '',
    );
  }

  final int id;
  final String number;
}

class PlantDirectoryDriver {
  const PlantDirectoryDriver({required this.id, required this.name});

  factory PlantDirectoryDriver.fromJson(Map<String, dynamic> json) {
    return PlantDirectoryDriver(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
    );
  }

  final int id;
  final String name;
}
