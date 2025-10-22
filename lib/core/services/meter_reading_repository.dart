import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/meter_reading_models.dart';

class MeterReadingFailure implements Exception {
  MeterReadingFailure(this.message);
  final String message;

  @override
  String toString() => 'MeterReadingFailure: $message';
}

class MeterReadingRepository {
  MeterReadingRepository({http.Client? client, Uri? baseUri})
    : _client = client ?? http.Client(),
      _baseUri = baseUri ?? Uri.parse(_defaultBaseUrl);

  static const String _defaultBaseUrl =
      'https://sstranswaysindia.com/api/mobile/';

  final http.Client _client;
  final Uri _baseUri;

  Uri _resolve(String path, [Map<String, dynamic>? query]) {
    final uri = _baseUri.resolve(path);
    if (query == null) {
      return uri;
    }
    return uri.replace(
      queryParameters: query.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }

  Future<MeterStatusData> fetchStatus({required int userId}) async {
    final uri = _resolve('meter_readings.php', {
      'action': 'status',
      'userId': userId,
    });
    final response = await _client.get(uri);
    return _parseStatus(response);
  }

  Future<MeterStatusData> submitReading(MeterReadingRequest request) async {
    final uri = _resolve('meter_readings.php');
    final multipart = http.MultipartRequest('POST', uri)
      ..fields['action'] = 'submit'
      ..fields['userId'] = request.userId.toString()
      ..fields['driverId'] = request.driverId.toString()
      ..fields['vehicleId'] = request.vehicleId.toString()
      ..fields['readingKm'] = request.readingKm.toStringAsFixed(1);
    if (request.notes != null && request.notes!.trim().isNotEmpty) {
      multipart.fields['notes'] = request.notes!.trim();
    }

    final file = File(request.photoPath);
    final fileName = file.uri.pathSegments.isEmpty
        ? 'meter.jpg'
        : file.uri.pathSegments.last;
    multipart.files.add(
      await http.MultipartFile.fromPath('photo', file.path, filename: fileName),
    );

    final streamed = await multipart.send();
    final response = await http.Response.fromStream(streamed);
    return _parseStatus(response);
  }

  Future<List<MeterHistoryEntry>> fetchHistory({
    required int userId,
    required int vehicleId,
    String? monthKey,
    int limit = 10,
  }) async {
    final uri = _resolve('meter_readings.php', {
      'action': 'history',
      'userId': userId,
      'vehicleId': vehicleId,
      if (monthKey != null) 'monthKey': monthKey,
      'limit': limit,
    });
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw MeterReadingFailure(
        'Unable to load meter history (${response.statusCode})',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>?;
    if (payload == null || payload['status'] != 'ok') {
      throw MeterReadingFailure(
        payload?['error']?.toString() ?? 'Unexpected response from server',
      );
    }
    final historyJson = payload['data'] as List<dynamic>? ?? const [];
    return historyJson
        .map((item) => MeterHistoryEntry.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  MeterStatusData _parseStatus(http.Response response) {
    if (response.statusCode != 200) {
      throw MeterReadingFailure(
        'Unable to load meter status (${response.statusCode})',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>?;
    if (payload == null || payload['status'] != 'ok') {
      throw MeterReadingFailure(
        payload?['error']?.toString() ?? 'Unexpected response from server',
      );
    }
    return MeterStatusData.fromJson(
      payload['data'] as Map<String, dynamic>? ?? payload,
    );
  }
}
