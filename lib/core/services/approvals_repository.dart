import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/attendance_approval.dart';

class ApprovalsFailure implements Exception {
  ApprovalsFailure(this.message);

  final String message;

  @override
  String toString() => 'ApprovalsFailure: $message';
}

class ApprovalsRepository {
  ApprovalsRepository({
    http.Client? client,
    Uri? endpoint,
    Uri? actionEndpoint,
  })  : _client = client ?? http.Client(),
        _endpoint = endpoint ?? Uri.parse(_defaultEndpoint),
        _actionEndpoint = actionEndpoint ?? Uri.parse(_defaultActionEndpoint);

  static const String _defaultEndpoint =
      'https://sstranswaysindia.com/api/mobile/attendance_approvals.php';
  static const String _defaultActionEndpoint =
      'https://sstranswaysindia.com/api/mobile/attendance_approval_action.php';

  final http.Client _client;
  final Uri _endpoint;
  final Uri _actionEndpoint;

  Future<ApprovalsResponse> fetchApprovals({
    required String supervisorUserId,
    String userIdParamKey = 'supervisorUserId',
    String status = 'Pending',
    String? date,
    String? plantId,
    int? rangeDays,
  }) async {
    final params = <String, String>{
      userIdParamKey: supervisorUserId,
      'status': status,
      if (date != null && date.isNotEmpty) 'date': date,
      if (plantId != null && plantId.isNotEmpty) 'plantId': plantId,
      if (rangeDays != null) 'rangeDays': rangeDays.toString(),
    };

    final uri = _endpoint.replace(queryParameters: params);
    final response = await _client.get(uri);

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApprovalsFailure(
        'Invalid response from server (status: ${response.statusCode}).',
      );
    }

    if (response.statusCode >= 300 || payload['status'] != 'ok') {
      throw ApprovalsFailure(payload['error']?.toString() ?? 'Unable to load approvals.');
    }

    final plants = (payload['plants'] as List<dynamic>? ?? const [])
        .map((item) => SupervisorPlantOption.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);

    final approvals = (payload['approvals'] as List<dynamic>? ?? const [])
        .map((item) => AttendanceApproval.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);

    return ApprovalsResponse(plants: plants, approvals: approvals);
  }

  Future<void> submitApprovalAction({
    required String supervisorUserId,
    required String attendanceId,
    required String action,
    String? notes,
  }) async {
    try {
      final response = await _client.post(
        _actionEndpoint,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'supervisorUserId': supervisorUserId,
          'attendanceId': attendanceId,
          'action': action,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        }),
      );

      final body = response.body;
      Map<String, dynamic>? payload;
      try {
        payload = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        payload = null;
      }

      final isOkStatus = response.statusCode < 300 && payload?['status'] == 'ok';
      if (!isOkStatus) {
        final message = payload?['error']?.toString() ?? 'Unable to update approval.';
        throw ApprovalsFailure(message);
      }
    } on ApprovalsFailure {
      rethrow;
    } catch (_) {
      throw ApprovalsFailure('Unable to update approval.');
    }
  }
}

class ApprovalsResponse {
  const ApprovalsResponse({
    required this.plants,
    required this.approvals,
  });

  final List<SupervisorPlantOption> plants;
  final List<AttendanceApproval> approvals;
}
