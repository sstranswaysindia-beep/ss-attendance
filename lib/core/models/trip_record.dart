class TripRecord {
  TripRecord({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.vehicleNumber,
    required this.status,
    this.plantId,
    this.plantName,
    this.drivers,
    this.helper,
    this.helperNames = const <String>[],
    this.customers,
    this.startKm,
    this.endKm,
    this.runKm,
    this.note,
    this.gpsLat,
    this.gpsLng,
    this.canCurrentUserDelete = false,
  });

  factory TripRecord.fromJson(Map<String, dynamic> json) {
    double? _doubleOrNull(dynamic value) {
      if (value == null || value.toString().isEmpty) {
        return null;
      }
      return double.tryParse(value.toString());
    }

    bool _boolFromJson(dynamic value) {
      if (value is bool) return value;
      if (value == null) return false;
      final stringValue = value.toString().toLowerCase();
      return stringValue == 'true' || stringValue == '1';
    }

    List<String> _parseHelperNames() {
      final rawSources = <String>[
        json['helper']?.toString() ?? '',
        json['helpers']?.toString() ?? '',
      ];
      final seen = <String>{};
      final parts = <String>[];
      for (final raw in rawSources) {
        if (raw.isEmpty) continue;
        for (final entry in raw.split(',')) {
          final name = entry.trim();
          if (name.isEmpty) continue;
          final key = name.toLowerCase();
          if (seen.add(key)) {
            parts.add(name);
          }
        }
      }
      return parts;
    }

    final helperParts = _parseHelperNames();
    return TripRecord(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      startDate: json['startDate']?.toString() ?? '',
      endDate: json['endDate']?.toString(),
      vehicleNumber: json['vehicleNumber']?.toString() ?? '',
      status: json['status']?.toString() ?? 'planned',
      plantId: json['plantId'] != null
          ? int.tryParse(json['plantId'].toString())
          : null,
      plantName: json['plantName']?.toString(),
      drivers: json['drivers']?.toString(),
      helper: helperParts.isEmpty ? null : helperParts.join(', '),
      helperNames: helperParts,
      customers: json['customers']?.toString(),
      startKm: _doubleOrNull(json['startKm']),
      endKm: _doubleOrNull(json['endKm']),
      runKm: _doubleOrNull(json['runKm']),
      note: json['note']?.toString(),
      gpsLat: _doubleOrNull(json['gpsLat']),
      gpsLng: _doubleOrNull(json['gpsLng']),
      canCurrentUserDelete: _boolFromJson(json['canDelete']),
    );
  }

  final int id;
  final String startDate;
  final String? endDate;
  final int? plantId;
  final String? plantName;
  final String vehicleNumber;
  final String status;
  final String? drivers;
  final String? helper;
  final List<String> helperNames;
  final String? customers;
  final double? startKm;
  final double? endKm;
  final double? runKm;
  final String? note;
  final double? gpsLat;
  final double? gpsLng;
  final bool canCurrentUserDelete;
}
