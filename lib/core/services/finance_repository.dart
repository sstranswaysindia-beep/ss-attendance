import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/advance_request.dart';
import '../models/salary_credit.dart';

class FinanceFailure implements Exception {
  FinanceFailure(this.message);

  final String message;

  @override
  String toString() => 'FinanceFailure: $message';
}

class FinanceRepository {
  FinanceRepository({
    http.Client? client,
    Uri? salaryEndpoint,
    Uri? advanceEndpoint,
    Uri? advanceSubmitEndpoint,
    Uri? salaryDeleteEndpoint,
    Uri? advanceDeleteEndpoint,
  })  : _client = client ?? http.Client(),
        _salaryEndpoint = salaryEndpoint ?? Uri.parse(_defaultSalaryEndpoint),
        _advanceEndpoint = advanceEndpoint ?? Uri.parse(_defaultAdvanceEndpoint),
        _advanceSubmitEndpoint =
            advanceSubmitEndpoint ?? Uri.parse(_defaultAdvanceSubmitEndpoint),
        _salaryDeleteEndpoint =
            salaryDeleteEndpoint ?? Uri.parse(_defaultSalaryDeleteEndpoint),
        _advanceDeleteEndpoint =
            advanceDeleteEndpoint ?? Uri.parse(_defaultAdvanceDeleteEndpoint);

  static const String _defaultSalaryEndpoint =
      'https://sstranswaysindia.com/api/mobile/salary_credits.php';
  static const String _defaultAdvanceEndpoint =
      'https://sstranswaysindia.com/api/mobile/advance_requests.php';
  static const String _defaultAdvanceSubmitEndpoint =
      'https://sstranswaysindia.com/api/mobile/advance_request_submit.php';
  static const String _defaultSalaryDeleteEndpoint =
      'https://sstranswaysindia.com/api/mobile/salary_credit_delete.php';
  static const String _defaultAdvanceDeleteEndpoint =
      'https://sstranswaysindia.com/api/mobile/advance_request_delete.php';

  final http.Client _client;
  final Uri _salaryEndpoint;
  final Uri _advanceEndpoint;
  final Uri _advanceSubmitEndpoint;
  final Uri _salaryDeleteEndpoint;
  final Uri _advanceDeleteEndpoint;

  Future<List<SalaryCredit>> fetchSalaryCredits(String driverId) async {
    final uri = _salaryEndpoint.replace(queryParameters: <String, String>{
      'driverId': driverId,
    });
    final response = await _client.get(uri);
    final statusCode = response.statusCode;

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw FinanceFailure('Invalid response from server (status: $statusCode).');
    }

    if (statusCode != 200 || payload['status'] != 'ok') {
      throw FinanceFailure(payload['error']?.toString() ?? 'Unable to load salary credits.');
    }

    final entries = payload['salaryCredits'] as List<dynamic>? ?? const [];
    return entries
        .map((item) => SalaryCredit.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<AdvanceRequest>> fetchAdvanceRequests(String driverId, {String? status}) async {
    final params = <String, String>{'driverId': driverId};
    if (status != null && status.isNotEmpty) {
      params['status'] = status;
    }
    final uri = _advanceEndpoint.replace(queryParameters: params);
    final response = await _client.get(uri);
    final statusCode = response.statusCode;

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw FinanceFailure('Invalid response from server (status: $statusCode).');
    }

    if (statusCode != 200 || payload['status'] != 'ok') {
      throw FinanceFailure(payload['error']?.toString() ?? 'Unable to load advance requests.');
    }

    final items = payload['advanceRequests'] as List<dynamic>? ?? const [];
    return items
        .map((item) => AdvanceRequest.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<AdvanceRequest> submitAdvanceRequest({
    required String driverId,
    required double amount,
    required String purpose,
    String? notes,
  }) async {
    final response = await _client.post(
      _advanceSubmitEndpoint,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'driverId': driverId,
        'amount': amount,
        'purpose': purpose,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      }),
    );

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw FinanceFailure('Invalid response from server (status: ${response.statusCode}).');
    }

    if (response.statusCode >= 300 || payload['status'] != 'ok') {
      throw FinanceFailure(payload['error']?.toString() ?? 'Unable to submit advance request.');
    }

    final requestedAt = payload['requestedAt']?.toString() ?? DateTime.now().toIso8601String();
    final amountValue = double.tryParse(payload['amount']?.toString() ?? '') ?? amount;
    final remarks = payload['notes']?.toString();
    final statusLabel = payload['recordStatus']?.toString() ?? 'Pending';

    return AdvanceRequest(
      advanceRequestId: payload['advanceRequestId']?.toString() ?? '',
      amount: amountValue,
      purpose: payload['purpose']?.toString() ?? purpose,
      status: statusLabel,
      requestedAt: requestedAt,
      remarks: remarks,
      approvalAt: null,
      approvalById: null,
      disbursedAt: null,
    );
  }

  Future<void> deleteSalaryCredit({
    required String driverId,
    required String salaryCreditId,
  }) async {
    final response = await _client.post(
      _salaryDeleteEndpoint,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'driverId': driverId,
        'salaryCreditId': salaryCreditId,
      }),
    );

    if (response.statusCode >= 300) {
      String message = 'Unable to delete salary credit.';
      try {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        message = payload['error']?.toString() ?? message;
      } catch (_) {}
      throw FinanceFailure(message);
    }
  }

  Future<void> deleteAdvanceRequest({
    required String driverId,
    required String advanceRequestId,
  }) async {
    final response = await _client.post(
      _advanceDeleteEndpoint,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'driverId': driverId,
        'advanceRequestId': advanceRequestId,
      }),
    );

    if (response.statusCode >= 300) {
      String message = 'Unable to delete advance request.';
      try {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        message = payload['error']?.toString() ?? message;
      } catch (_) {}
      throw FinanceFailure(message);
    }
  }
}
