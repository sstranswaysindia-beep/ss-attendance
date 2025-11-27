import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/admin_proxy_user.dart';

class AdminProxyFailure implements Exception {
  AdminProxyFailure(this.message);

  final String message;

  @override
  String toString() => 'AdminProxyFailure: $message';
}

class AdminProxyRepository {
  AdminProxyRepository({http.Client? client}) : _client = client ?? http.Client();

  static const String _listEndpoint =
      'https://sstranswaysindia.com/api/mobile/admin_proxy_list.php';
  static const String _updateEndpoint =
      'https://sstranswaysindia.com/api/mobile/admin_proxy_update.php';

  final http.Client _client;

  Uri _buildUri({int? plantId}) {
    final params = <String, String>{};
    if (plantId != null && plantId > 0) {
      params['plantId'] = plantId.toString();
    }
    return Uri.parse(_listEndpoint).replace(
      queryParameters: params.isEmpty ? null : params,
    );
  }

  Future<AdminProxyPayload> fetchUsers({int? plantId}) async {
    final uri = _buildUri(plantId: plantId);
    final response = await _client.get(uri);

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw AdminProxyFailure(
        'Invalid response from server (status: ${response.statusCode}).',
      );
    }

    if (response.statusCode != 200 || payload['status'] != 'ok') {
      throw AdminProxyFailure(
        payload['error']?.toString() ??
            'Unable to load proxy attendance configuration.',
      );
    }

    return AdminProxyPayload.fromJson(payload);
  }

  Future<void> updateProxy({
    required int userId,
    required bool enabled,
  }) async {
    final response = await _client.post(
      Uri.parse(_updateEndpoint),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': userId,
        'enabled': enabled,
      }),
    );

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw AdminProxyFailure(
        'Unexpected server response (status: ${response.statusCode}).',
      );
    }

    if (response.statusCode != 200 || payload['status'] != 'ok') {
      throw AdminProxyFailure(
        payload['error']?.toString() ??
            'Unable to update proxy attendance preference.',
      );
    }
  }
}
