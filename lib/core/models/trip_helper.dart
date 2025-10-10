class TripHelper {
  const TripHelper({
    required this.id,
    required this.name,
    this.plantId,
  });

  final int id;
  final String name;
  final int? plantId;

  factory TripHelper.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic value) {
      final str = value?.toString();
      if (str == null) return null;
      return int.tryParse(str);
    }

    return TripHelper(
      id: parseInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? '',
      plantId: parseInt(json['plant_id']),
    );
  }
}
