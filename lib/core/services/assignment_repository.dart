import 'dart:convert';

import 'package:http/http.dart' as http;

class AssignmentFailure implements Exception {
  AssignmentFailure(this.message);

  final String message;

  @override
  String toString() => 'AssignmentFailure: $message';
}

class AssignmentRepository {
  AssignmentRepository({http.Client? client, Uri? endpoint})
      : _client = client ?? http.Client(),
        _endpoint = endpoint ?? Uri.parse(_defaultEndpoint);

  static const String _defaultEndpoint =
      'https://sstranswaysindia.com/api/mobile/assign_vehicle.php';

  final http.Client _client;
  final Uri _endpoint;

  Future<Map<String, dynamic>> assignVehicle({
    required String driverId,
    required String vehicleId,
    required String plantId,
    String? userId,
  }) async {
    try {
      final response = await _client.post(
        _endpoint,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driverId': driverId,
          'vehicleId': vehicleId,
          'plantId': plantId,
          if (userId != null) 'userId': userId,
        }),
      );

      final statusCode = response.statusCode;
      late final Map<String, dynamic> payload;
      try {
        payload = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw AssignmentFailure('Invalid response from server (status: $statusCode).');
      }

      if (statusCode != 200 || payload['status'] != 'ok') {
        throw AssignmentFailure(payload['error']?.toString() ?? 'Unable to save assignment.');
      }

      return payload;
    } on AssignmentFailure {
      rethrow;
    } catch (_) {
      throw AssignmentFailure('Unable to reach server. Please try again later.');
    }
  }
}
