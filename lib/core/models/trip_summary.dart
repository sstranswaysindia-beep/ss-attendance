class TripSummary {
  const TripSummary({
    required this.totalTrips,
    required this.completedTrips,
    required this.openTrips,
    required this.totalRunKm,
  });

  factory TripSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const TripSummary(totalTrips: 0, completedTrips: 0, openTrips: 0, totalRunKm: 0);
    }
    double _asDouble(dynamic value) => double.tryParse(value?.toString() ?? '') ?? 0;
    int _asInt(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;

    return TripSummary(
      totalTrips: _asInt(json['totalTrips']),
      completedTrips: _asInt(json['completedTrips']),
      openTrips: _asInt(json['openTrips']),
      totalRunKm: _asDouble(json['totalRunKm']),
    );
  }

  final int totalTrips;
  final int completedTrips;
  final int openTrips;
  final double totalRunKm;
}
