class TripPlant {
  const TripPlant({required this.id, required this.name});

  factory TripPlant.fromJson(Map<String, dynamic> json) {
    int _parseId() {
      final candidates = [
        json['id'],
        json['plantId'],
      ];
      for (final value in candidates) {
        final parsed = int.tryParse(value?.toString() ?? '');
        if (parsed != null && parsed > 0) {
          return parsed;
        }
      }
      return 0;
    }

    String _parseName() {
      final candidates = [
        json['plant_name'],
        json['plantName'],
        json['name'],
        json['title'],
      ];
      for (final value in candidates) {
        final str = value?.toString();
        if (str != null && str.isNotEmpty) {
          return str;
        }
      }
      return '';
    }

    return TripPlant(
      id: _parseId(),
      name: _parseName(),
    );
  }

  final int id;
  final String name;
}
