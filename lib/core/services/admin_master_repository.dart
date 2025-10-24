import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/admin_driver_master.dart';
import '../models/admin_vehicle_master.dart';

class AdminMasterFailure implements Exception {
  AdminMasterFailure(this.message);
  final String message;

  @override
  String toString() => 'AdminMasterFailure: $message';
}

class AdminMasterRepository {
  AdminMasterRepository({http.Client? client})
      : _client = client ?? http.Client();

  static const String _driverEndpoint =
      'https://sstranswaysindia.com/api/mobile/admin_driver_master.php';
  static const String _vehicleEndpoint =
      'https://sstranswaysindia.com/api/mobile/admin_vehicle_master.php';

  final http.Client _client;

  Uri _buildUri(String base, Map<String, String?> params) {
    final filtered = <String, String>{};
    params.forEach((key, value) {
      if (value != null && value.isNotEmpty) {
        filtered[key] = value;
      }
    });
    return Uri.parse(base).replace(queryParameters: filtered.isEmpty ? null : filtered);
  }

  Future<List<AdminDriver>> fetchDrivers({
    String? search,
    String? status,
  }) async {
    final uri = _buildUri(_driverEndpoint, {
      if (search != null) 'q': search.trim(),
      if (status != null) 'status': status.trim(),
    });

    final response = await _client.get(uri);
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw AdminMasterFailure(
        'Invalid response from server (status: ${response.statusCode}).',
      );
    }

    if (response.statusCode != 200 || payload['status'] != 'ok') {
      throw AdminMasterFailure(
        payload['error']?.toString() ?? 'Unable to load drivers.',
      );
    }

    final items = payload['drivers'] as List<dynamic>? ?? const [];
    return items
        .map((item) => AdminDriver.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<AdminVehicle>> fetchVehicles({
    String? search,
    String? plantId,
  }) async {
    final uri = _buildUri(_vehicleEndpoint, {
      if (search != null) 'q': search.trim(),
      if (plantId != null) 'plantId': plantId.trim(),
    });

    final response = await _client.get(uri);
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw AdminMasterFailure(
        'Invalid response from server (status: ${response.statusCode}).',
      );
    }

    if (response.statusCode != 200 || payload['status'] != 'ok') {
      throw AdminMasterFailure(
        payload['error']?.toString() ?? 'Unable to load vehicles.',
      );
    }

    final items = payload['vehicles'] as List<dynamic>? ?? const [];
    return items
        .map((item) => AdminVehicle.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }
}
