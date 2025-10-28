import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/proxy_employee.dart';

class ProxyAttendanceFailure implements Exception {
  ProxyAttendanceFailure(this.message);

  final String message;

  @override
  String toString() => 'ProxyAttendanceFailure: $message';
}

class ProxyAttendanceRepository {
  ProxyAttendanceRepository({
    http.Client? client,
    Uri? listEndpoint,
    Uri? submitEndpoint,
  }) : _client = client ?? http.Client(),
       _listEndpoint =
           listEndpoint ??
           Uri.parse(
             'https://sstranswaysindia.com/api/mobile/attendance_proxy_list.php',
           ),
       _submitEndpoint =
           submitEndpoint ??
           Uri.parse(
             'https://sstranswaysindia.com/api/mobile/attendance_proxy_submit.php',
           );

  final http.Client _client;
  final Uri _listEndpoint;
  final Uri _submitEndpoint;

  Future<ProxyAttendanceResponse> fetchEmployees({
    required String supervisorUserId,
    String? plantId,
  }) async {
    final query = <String, String>{'supervisorUserId': supervisorUserId};
    if (plantId != null && plantId.isNotEmpty) {
      query['plantId'] = plantId;
    }

    final uri = _listEndpoint.replace(queryParameters: query);
    final response = await _client.get(uri);

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ProxyAttendanceFailure(
        'Invalid response from server (status: ${response.statusCode}).',
      );
    }

    if (response.statusCode >= 300 || payload['status'] != 'ok') {
      throw ProxyAttendanceFailure(
        payload['error']?.toString() ?? 'Unable to load proxy list.',
      );
    }

    final employees = (payload['employees'] as List<dynamic>? ?? const [])
        .map((json) => ProxyEmployee.fromJson(json as Map<String, dynamic>))
        .toList(growable: false);

    final plants = (payload['plants'] as List<dynamic>? ?? const [])
        .map((json) => ProxyPlantOption.fromJson(json as Map<String, dynamic>))
        .toList(growable: false);

    return ProxyAttendanceResponse(employees: employees, plants: plants);
  }

  Future<Map<String, dynamic>> submit({
    required String supervisorUserId,
    required String driverId,
    required String userId,
    required String action,
    String? notes,
  }) async {
    final response = await _client.post(
      _submitEndpoint,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'supervisorUserId': supervisorUserId,
        'driverId': driverId,
        'userId': userId,
        'action': action,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      }),
    );

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ProxyAttendanceFailure(
        'Invalid response from server (status: ${response.statusCode}).',
      );
    }

    if (response.statusCode >= 300 || payload['status'] != 'ok') {
      throw ProxyAttendanceFailure(
        payload['error']?.toString() ?? 'Unable to submit proxy attendance.',
      );
    }

    return payload;
  }
}
