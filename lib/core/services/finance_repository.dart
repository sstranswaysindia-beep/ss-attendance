import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/advance_request.dart';
import '../models/salary_credit.dart';
import '../../features/attendance/attendance_log_screen.dart';

// Mobile-side API logging
class ApiLogger {
  static void logApiCall(
    String method,
    String url,
    Map<String, dynamic>? requestData,
  ) {
    final timestamp = DateTime.now().toIso8601String();
    print('🔵 API CALL [$timestamp]');
    print('   Method: $method');
    print('   URL: $url');
    if (requestData != null) {
      print('   Request Data: ${jsonEncode(requestData)}');
    }
  }

  static void logApiResponse(
    String method,
    String url,
    int statusCode,
    String responseBody, {
    Duration? duration,
  }) {
    final timestamp = DateTime.now().toIso8601String();
    print('🟢 API RESPONSE [$timestamp]');
    print('   Method: $method');
    print('   URL: $url');
    print('   Status: $statusCode');
    print('   Duration: ${duration?.inMilliseconds}ms');
    print('   Response: $responseBody');

    // Add to global log manager
    final log = AttendanceLogEntry(
      name: 'API Response - $method $url',
      timestamp: DateTime.now(),
      method: method,
      url: url,
      statusCode: statusCode,
      responseBody: responseBody,
      success: statusCode >= 200 && statusCode < 300,
    );
    GlobalApiLogManager.addLog(log);
  }

  static void logApiError(
    String method,
    String url,
    dynamic error, {
    Duration? duration,
  }) {
    final timestamp = DateTime.now().toIso8601String();
    print('🔴 API ERROR [$timestamp]');
    print('   Method: $method');
    print('   URL: $url');
    print('   Duration: ${duration?.inMilliseconds}ms');
    print('   Error: $error');

    // Add to global log manager
    final log = AttendanceLogEntry(
      name: 'API Error - $method $url',
      timestamp: DateTime.now(),
      method: method,
      url: url,
      error: error.toString(),
      success: false,
    );
    GlobalApiLogManager.addLog(log);
  }
}

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
  }) : _client = client ?? http.Client(),
       _salaryEndpoint = salaryEndpoint ?? Uri.parse(_defaultSalaryEndpoint),
       _advanceEndpoint = advanceEndpoint ?? Uri.parse(_defaultAdvanceEndpoint),
       _advanceSubmitEndpoint =
           advanceSubmitEndpoint ?? Uri.parse(_defaultAdvanceSubmitEndpoint),
       _salaryDeleteEndpoint =
           salaryDeleteEndpoint ?? Uri.parse(_defaultSalaryDeleteEndpoint),
       _advanceDeleteEndpoint =
           advanceDeleteEndpoint ?? Uri.parse(_defaultAdvanceDeleteEndpoint),
       _fundTransferEndpoint = Uri.parse(_defaultFundTransferEndpoint);

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
  static const String _defaultFundTransferEndpoint =
      'https://sstranswaysindia.com/api/mobile/fund_transfer_submit.php';

  final http.Client _client;
  final Uri _salaryEndpoint;
  final Uri _advanceEndpoint;
  final Uri _advanceSubmitEndpoint;
  final Uri _salaryDeleteEndpoint;
  final Uri _advanceDeleteEndpoint;
  final Uri _fundTransferEndpoint;

  Future<List<SalaryCredit>> fetchSalaryCredits(String driverId) async {
    final stopwatch = Stopwatch()..start();
    final uri = _salaryEndpoint.replace(
      queryParameters: <String, String>{'driverId': driverId},
    );

    try {
      final requestData = {'driverId': driverId};
      ApiLogger.logApiCall('GET', uri.toString(), requestData);

      final response = await _client.get(uri);
      final statusCode = response.statusCode;

      stopwatch.stop();
      ApiLogger.logApiResponse(
        'GET',
        uri.toString(),
        statusCode,
        response.body,
        duration: stopwatch.elapsed,
      );

      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw FinanceFailure(
          'Invalid response from server (status: $statusCode).',
        );
      }

      if (statusCode != 200 || payload['status'] != 'ok') {
        throw FinanceFailure(
          payload['error']?.toString() ?? 'Unable to load salary credits.',
        );
      }

      final entries = payload['salaryCredits'] as List<dynamic>? ?? const [];
      return entries
          .map((item) => SalaryCredit.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } catch (e) {
      stopwatch.stop();
      ApiLogger.logApiError(
        'GET',
        uri.toString(),
        e,
        duration: stopwatch.elapsed,
      );
      rethrow;
    }
  }

  Future<List<AdvanceRequest>> fetchAdvanceRequests(
    String driverId, {
    String? status,
  }) async {
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
      throw FinanceFailure(
        'Invalid response from server (status: $statusCode).',
      );
    }

    if (statusCode != 200 || payload['status'] != 'ok') {
      throw FinanceFailure(
        payload['error']?.toString() ?? 'Unable to load advance requests.',
      );
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
      throw FinanceFailure(
        'Invalid response from server (status: ${response.statusCode}).',
      );
    }

    if (response.statusCode >= 300 || payload['status'] != 'ok') {
      throw FinanceFailure(
        payload['error']?.toString() ?? 'Unable to submit advance request.',
      );
    }

    final requestedAt =
        payload['requestedAt']?.toString() ?? DateTime.now().toIso8601String();
    final amountValue =
        double.tryParse(payload['amount']?.toString() ?? '') ?? amount;
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

  Future<Map<String, dynamic>> submitFundTransfer({
    required String driverId,
    required String senderId,
    required double amount,
    required String description,
    String? senderName,
  }) async {
    print(
      'DEBUG: FinanceRepository.submitFundTransfer called - driverId: $driverId, senderId: $senderId, amount: $amount, senderName: $senderName',
    );
    print('DEBUG: API endpoint: $_fundTransferEndpoint');

    final trimmedSenderName = senderName?.trim();
    final requestPayload = <String, dynamic>{
      'driverId': driverId,
      'senderId': senderId,
      'amount': amount,
      'description': description,
    };
    if (trimmedSenderName != null && trimmedSenderName.isNotEmpty) {
      requestPayload['senderName'] = trimmedSenderName;
    }
    final requestBody = jsonEncode(requestPayload);
    print('DEBUG: Request body: $requestBody');

    final response = await _client.post(
      _fundTransferEndpoint,
      headers: const {'Content-Type': 'application/json'},
      body: requestBody,
    );

    print('DEBUG: API response status: ${response.statusCode}');
    print('DEBUG: API response body: ${response.body}');

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw FinanceFailure(
        'Invalid response from server (status: ${response.statusCode}).',
      );
    }

    if (response.statusCode >= 300 || payload['status'] != 'ok') {
      throw FinanceFailure(
        payload['error']?.toString() ?? 'Unable to submit fund transfer.',
      );
    }

    return payload;
  }

  Future<Map<String, dynamic>> deleteTransaction(String transactionId) async {
    final deleteEndpoint = Uri.parse(
      'https://sstranswaysindia.com/api/mobile/delete_transaction.php',
    );

    final requestBody = jsonEncode(<String, dynamic>{
      'transactionId': transactionId,
    });

    final response = await _client.post(
      deleteEndpoint,
      headers: const {'Content-Type': 'application/json'},
      body: requestBody,
    );

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw FinanceFailure(
        'Invalid response from server (status: ${response.statusCode}).',
      );
    }

    if (response.statusCode >= 300 || payload['status'] != 'ok') {
      throw FinanceFailure(
        payload['error']?.toString() ?? 'Unable to delete transaction.',
      );
    }

    return payload;
  }

  Future<Map<String, dynamic>> uploadReceipt({
    required String transactionId,
    required String driverId,
    required String filePath,
  }) async {
    final stopwatch = Stopwatch()..start();
    final uri = Uri.parse(
      'https://sstranswaysindia.com/api/mobile/upload_receipt.php',
    );

    try {
      // Check if file exists
      final file = File(filePath);
      if (!await file.exists()) {
        throw FinanceFailure('File does not exist: $filePath');
      }

      final requestData = {
        'transactionId': transactionId,
        'driverId': driverId,
        'filePath': filePath,
        'fileSize': await file.length(),
      };

      ApiLogger.logApiCall('POST', uri.toString(), requestData);

      // Create multipart request
      final request = http.MultipartRequest('POST', uri);

      // Add fields
      request.fields['transactionId'] = transactionId;
      request.fields['driverId'] = driverId;

      // Add file
      final bytes = await file.readAsBytes();
      final multipartFile = http.MultipartFile.fromBytes(
        'receipt',
        bytes,
        filename: filePath.split('/').last,
      );
      request.files.add(multipartFile);

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      stopwatch.stop();
      ApiLogger.logApiResponse(
        'POST',
        uri.toString(),
        response.statusCode,
        response.body,
        duration: stopwatch.elapsed,
      );

      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        throw FinanceFailure(
          'Invalid response from server (status: ${response.statusCode}). Response: ${response.body}',
        );
      }

      if (response.statusCode >= 300 || payload['status'] != 'ok') {
        throw FinanceFailure(
          payload['error']?.toString() ??
              'Unable to upload receipt. Status: ${response.statusCode}',
        );
      }

      return payload;
    } catch (e) {
      stopwatch.stop();
      ApiLogger.logApiError(
        'POST',
        uri.toString(),
        e,
        duration: stopwatch.elapsed,
      );
      if (e is FinanceFailure) {
        rethrow;
      }
      throw FinanceFailure('Upload failed: $e');
    }
  }
}
