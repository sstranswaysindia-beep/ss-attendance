import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;

class GpsPingFailure implements Exception {
  GpsPingFailure(this.message);

  final String message;

  @override
  String toString() => 'GpsPingFailure: $message';
}

class GpsPingRepository {
  GpsPingRepository({http.Client? client, Uri? endpoint})
      : _client = client ?? http.Client(),
        _endpoint = endpoint ?? Uri.parse(_defaultEndpoint);

  static const String _defaultEndpoint =
      'https://sstranswaysindia.com/api/mobile/gps_ping_submit.php';

  final http.Client _client;
  final Uri _endpoint;
  static const Duration _requestTimeout = Duration(seconds: 15);

  Future<void> sendPing({
    required String driverId,
    String? plantId,
    required double latitude,
    required double longitude,
    double? accuracy,
    DateTime? timestamp,
    String source = 'mobile_fg',
  }) async {
    final body = <String, dynamic>{
      'driverId': driverId,
      if (plantId != null && plantId.isNotEmpty) 'plantId': plantId,
      'lat': latitude,
      'lng': longitude,
      'source': source,
      if (accuracy != null) 'accuracy': accuracy,
      if (timestamp != null) 'capturedAt': timestamp.toIso8601String(),
    };

    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final response = await _client
            .post(
              _endpoint,
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(_requestTimeout);

        if (response.statusCode >= 300) {
          throw GpsPingFailure(
            'Unable to record GPS ping (status: ${response.statusCode}).',
          );
        }

        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        if (payload['status'] != 'ok') {
          throw GpsPingFailure(
            payload['error']?.toString() ?? 'Unable to record GPS ping.',
          );
        }
        return;
      } on GpsPingFailure {
        rethrow;
      } on TimeoutException {
        if (attempt == 2) {
          throw GpsPingFailure('GPS ping timed out.');
        }
      } catch (_) {
        if (attempt == 2) {
          throw GpsPingFailure('Unable to record GPS ping.');
        }
      }
    }
  }
}
