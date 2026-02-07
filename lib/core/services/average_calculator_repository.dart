import 'dart:convert';

import 'package:http/http.dart' as http;

class AveragePlant {
  AveragePlant({required this.id, required this.name});

  final int id;
  final String name;

  factory AveragePlant.fromJson(Map<String, dynamic> json) {
    return AveragePlant(
      id: int.tryParse(json['id'].toString()) ?? 0,
      name: (json['plant_name'] ?? '').toString(),
    );
  }
}

class AverageVehicle {
  AverageVehicle({required this.id, required this.vehicleNo});

  final int id;
  final String vehicleNo;

  factory AverageVehicle.fromJson(Map<String, dynamic> json) {
    return AverageVehicle(
      id: int.tryParse(json['id'].toString()) ?? 0,
      vehicleNo: (json['vehicle_no'] ?? '').toString(),
    );
  }
}

class AverageDriver {
  AverageDriver({
    required this.id,
    required this.name,
    this.plant,
  });

  final int id;
  final String name;
  final String? plant;

  factory AverageDriver.fromJson(Map<String, dynamic> json) {
    return AverageDriver(
      id: int.tryParse(json['id'].toString()) ?? 0,
      name: (json['name'] ?? '').toString(),
      plant: json['plant']?.toString(),
    );
  }

  @override
  String toString() => name;
}

class AverageEntry {
  AverageEntry({
    required this.id,
    required this.entryDate,
    required this.plantId,
    required this.vehicleId,
    required this.vehicleNo,
    this.plantName,
    this.name,
    this.initialReading,
    this.finalReading,
    this.running,
    this.avgValue,
    this.fuelQty,
    this.fuelTaken,
    this.dieselDiff,
    this.fuelPrice,
    this.amount,
    this.currentAvg,
    this.total,
    this.avgFuelAmount,
  });

  final int id;
  final String entryDate;
  final int plantId;
  final int vehicleId;
  final String vehicleNo;
  final String? plantName;
  final String? name;
  final String? initialReading;
  final String? finalReading;
  final String? running;
  final String? avgValue;
  final String? fuelQty;
  final String? fuelTaken;
  final String? dieselDiff;
  final String? fuelPrice;
  final String? amount;
  final String? currentAvg;
  final String? total;
  final String? avgFuelAmount;

  factory AverageEntry.fromJson(Map<String, dynamic> json) {
    return AverageEntry(
      id: int.tryParse(json['id'].toString()) ?? 0,
      entryDate: (json['entry_date'] ?? '').toString(),
      plantId: int.tryParse(json['plant_id'].toString()) ?? 0,
      vehicleId: int.tryParse(json['vehicle_id'].toString()) ?? 0,
      vehicleNo: (json['vehicle_no'] ?? '').toString(),
      plantName: json['plant_name']?.toString(),
      name: json['name']?.toString(),
      initialReading: json['initial_reading']?.toString(),
      finalReading: json['final_reading']?.toString(),
      running: json['running']?.toString(),
      avgValue: json['avg_value']?.toString(),
      fuelQty: json['fuel_qty']?.toString(),
      fuelTaken: json['fuel_taken']?.toString(),
      dieselDiff: json['diesel_diff']?.toString(),
      fuelPrice: json['fuel_price']?.toString(),
      amount: json['amount']?.toString(),
      currentAvg: json['current_avg']?.toString(),
      total: json['total']?.toString(),
      avgFuelAmount: json['avg_fuel_amount']?.toString(),
    );
  }
}

class SpecialLedgerRow {
  SpecialLedgerRow({
    required this.id,
    required this.date,
    this.price,
    this.volume,
    this.amount,
  });

  final int id;
  final String date;
  final double? price;
  final double? volume;
  final double? amount;

  factory SpecialLedgerRow.fromJson(Map<String, dynamic> json) {
    return SpecialLedgerRow(
      id: int.tryParse(json['id'].toString()) ?? 0,
      date: (json['date'] ?? '').toString(),
      price: json['price'] == null
          ? null
          : double.tryParse(json['price'].toString()),
      volume: json['volume'] == null
          ? null
          : double.tryParse(json['volume'].toString()),
      amount: json['amount'] == null
          ? null
          : double.tryParse(json['amount'].toString()),
    );
  }
}

class SpecialBounds {
  SpecialBounds({this.minDate, this.maxDate});

  final String? minDate;
  final String? maxDate;

  factory SpecialBounds.fromJson(Map<String, dynamic> json) {
    return SpecialBounds(
      minDate: json['min_date']?.toString(),
      maxDate: json['max_date']?.toString(),
    );
  }
}

class AverageCalculatorRepository {
  AverageCalculatorRepository({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ??
            Uri.parse(
              'https://sstranswaysindia.com/AverageCalculator/api/mobile/',
            );

  final http.Client _client;
  final Uri _baseUri;
  final Uri _legacyBaseUri =
      Uri.parse('https://sstranswaysindia.com/AverageCalculator/');
  final Uri _driversUri =
      Uri.parse('https://sstranswaysindia.com/api/mobile/get_drivers.php');

  Uri _endpoint(String path, [Map<String, String>? query]) {
    return _baseUri.replace(path: '${_baseUri.path}$path', queryParameters: query);
  }

  Uri _legacyEndpoint(String path, [Map<String, String>? query]) {
    return _legacyBaseUri.replace(
      path: '${_legacyBaseUri.path}$path',
      queryParameters: query,
    );
  }

  Map<String, dynamic>? _decodeJson(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<Map<String, dynamic>> _getJson(
    Uri primary, {
    Uri? fallback,
  }) async {
    try {
      final response = await _client.get(primary);
      final payload = _decodeJson(response);
      if (payload != null) {
        return payload;
      }
    } catch (_) {
      // Try fallback below.
    }

    if (fallback != null) {
      final response = await _client.get(fallback);
      final payload = _decodeJson(response);
      if (payload != null) {
        return payload;
      }
    }

    throw FormatException('Invalid response from Average Calculator API.');
  }

  Future<List<AverageDriver>> fetchDrivers() async {
    try {
      final response = await _client.get(_driversUri);
      final payload = _decodeJson(response);
      if (payload == null || payload['status'] != 'ok') {
        throw Exception(
          payload?['error']?.toString() ??
              'Unable to load drivers list.',
        );
      }
      final rawDrivers = payload['drivers'] as List<dynamic>? ?? [];
      return rawDrivers
          .whereType<Map<String, dynamic>>()
          .map(AverageDriver.fromJson)
          .toList(growable: false);
    } catch (_) {
      throw Exception('Unable to load drivers list.');
    }
  }

  Future<Map<String, dynamic>> _postJson(
    Uri primary,
    Map<String, String> fields, {
    Uri? fallback,
  }) async {
    try {
      final response = await _client.post(primary, body: fields);
      final payload = _decodeJson(response);
      if (payload != null) {
        return payload;
      }
    } catch (_) {
      // Try fallback below.
    }

    if (fallback != null) {
      final response = await _client.post(fallback, body: fields);
      final payload = _decodeJson(response);
      if (payload != null) {
        return payload;
      }
    }

    throw FormatException('Invalid response from Average Calculator API.');
  }

  Future<List<AveragePlant>> fetchPlants() async {
    final payload = await _getJson(
      _endpoint('get_plants.php'),
      fallback: _legacyEndpoint('get_plants.php'),
    );
    final rawList = payload['plants'] as List<dynamic>? ?? [];
    return rawList.map((item) => AveragePlant.fromJson(item)).toList();
  }

  Future<List<AverageVehicle>> fetchVehicles(int plantId) async {
    final payload = await _getJson(
      _endpoint('get_vehicles.php', {'plant_id': plantId.toString()}),
      fallback:
          _legacyEndpoint('get_vehicles.php', {'plant_id': plantId.toString()}),
    );
    final rawList = payload['vehicles'] as List<dynamic>? ?? [];
    return rawList.map((item) => AverageVehicle.fromJson(item)).toList();
  }

  Future<List<AverageEntry>> fetchEntries(int vehicleId) async {
    final payload = await _getJson(
      _endpoint('get_entries.php', {'vehicle_id': vehicleId.toString()}),
      fallback: _legacyEndpoint(
        'get_entries.php',
        {'vehicle_id': vehicleId.toString()},
      ),
    );
    final rawList = payload['entries'] as List<dynamic>? ?? [];
    return rawList.map((item) => AverageEntry.fromJson(item)).toList();
  }

  Future<SpecialBounds> fetchSpecialBounds(int vehicleId) async {
    final payload = await _getJson(
      _endpoint('special_bounds.php', {'vehicle_id': vehicleId.toString()}),
      fallback: _legacyEndpoint('index.php', {
        'action': 'special_bounds',
        'vehicle_id': vehicleId.toString(),
      }),
    );
    return SpecialBounds.fromJson(payload);
  }

  Future<Map<String, List<SpecialLedgerRow>>> fetchSpecialMap({
    required int vehicleId,
    required String from,
    required String to,
  }) async {
    final payload = await _getJson(
      _endpoint('special_map.php', {
        'vehicle_id': vehicleId.toString(),
        'from': from,
        'to': to,
      }),
      fallback: _legacyEndpoint('index.php', {
        'action': 'special_map',
        'vehicle_id': vehicleId.toString(),
        'from': from,
        'to': to,
      }),
    );
    final rawMap = payload['map'] as Map<String, dynamic>? ?? {};

    final mapped = <String, List<SpecialLedgerRow>>{};
    rawMap.forEach((key, value) {
      final rows = (value as List<dynamic>?) ?? [];
      mapped[key] = rows.map((row) => SpecialLedgerRow.fromJson(row)).toList();
    });
    return mapped;
  }

  Future<Map<String, dynamic>> addEntry(Map<String, String> fields) async {
    return _postJson(
      _endpoint('add_entry.php'),
      fields,
      fallback: _legacyEndpoint('add_entry.php'),
    );
  }

  Future<Map<String, dynamic>> updateEntry(Map<String, String> fields) async {
    return _postJson(
      _endpoint('update_entry.php'),
      fields,
      fallback: _legacyEndpoint('update_entry.php'),
    );
  }

  Future<Map<String, dynamic>> deleteEntry(int entryId) async {
    return _postJson(
      _endpoint('delete_entry.php'),
      {'id': entryId.toString()},
      fallback: _legacyEndpoint('delete_entry.php'),
    );
  }
}
