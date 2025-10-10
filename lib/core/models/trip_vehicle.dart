class TripVehicle {
  const TripVehicle({
    required this.id,
    required this.number,
    this.lastEndKm,
    this.lastEndDate,
    List<String>? recentCustomers,
  }) : recentCustomers = recentCustomers ?? const <String>[];

  factory TripVehicle.fromJson(Map<String, dynamic> json) {
    int? _tryParseInt(dynamic value) {
      if (value == null) {
        return null;
      }
      final text = value.toString();
      if (text.isEmpty) {
        return null;
      }
      return int.tryParse(text);
    }

    List<String> _parseCustomerList(dynamic raw) {
      if (raw is List) {
        return raw
            .map((item) => item?.toString().trim() ?? '')
            .where((name) => name.isNotEmpty)
            .toList(growable: false);
      }
      if (raw is String) {
        final decoded = raw
            .split(',')
            .map((item) => item.trim())
            .where((name) => name.isNotEmpty)
            .toList(growable: false);
        return decoded;
      }
      return const <String>[];
    }

    return TripVehicle(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      number: json['vehicle_no']?.toString() ?? '',
      lastEndKm: _tryParseInt(json['last_end_km']),
      lastEndDate: json['last_end_date']?.toString(),
      recentCustomers: _parseCustomerList(json['recent_customers']),
    );
  }

  TripVehicle copyWith({
    int? id,
    String? number,
    int? lastEndKm,
    String? lastEndDate,
    List<String>? recentCustomers,
  }) {
    return TripVehicle(
      id: id ?? this.id,
      number: number ?? this.number,
      lastEndKm: lastEndKm ?? this.lastEndKm,
      lastEndDate: lastEndDate ?? this.lastEndDate,
      recentCustomers: recentCustomers ?? this.recentCustomers,
    );
  }

  final int id;
  final String number;
  final int? lastEndKm;
  final String? lastEndDate;
  final List<String> recentCustomers;
}
