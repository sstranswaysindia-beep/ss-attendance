import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_user.dart';
import '../models/trip_sheet_record.dart';

class TripSheetFailure implements Exception {
  TripSheetFailure(this.message);
  final String message;

  @override
  String toString() => 'TripSheetFailure: $message';
}

class TripSheetRepository {
  TripSheetRepository({http.Client? client})
    : _client = client ?? http.Client();

  static const String _base = 'https://sstranswaysindia.com/api/mobile/';

  final http.Client _client;

  /// Upload a trip sheet image.
  Future<Map<String, dynamic>> upload({
    required AppUser user,
    required int plantId,
    required String plantName,
    required int vehicleId,
    required String vehicleNumber,
    required File imageFile,
    DateTime? captureDate,
    String? notes,
  }) async {
    final uri = Uri.parse('${_base}trip_sheet_upload.php');

    try {
      final request = http.MultipartRequest('POST', uri);

      request.fields['user_id'] = user.id;
      if (user.driverId != null && user.driverId!.isNotEmpty) {
        request.fields['driver_id'] = user.driverId!;
      }
      request.fields['plant_id'] = plantId.toString();
      request.fields['plant_name'] = plantName;
      request.fields['vehicle_id'] = vehicleId.toString();
      request.fields['vehicle_number'] = vehicleNumber;
      request.fields['user_role'] = user.role.name;
      if (captureDate != null) {
        request.fields['capture_date'] = _formatDate(captureDate);
      }
      if (notes != null && notes.isNotEmpty) {
        request.fields['notes'] = notes;
      }

      request.files.add(
        await http.MultipartFile.fromPath('trip_sheet', imageFile.path),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 300) {
        throw TripSheetFailure(
          'Upload failed (status: ${response.statusCode}).',
        );
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (payload['status'] != 'ok') {
        throw TripSheetFailure(
          payload['error']?.toString() ?? 'Upload failed.',
        );
      }

      return payload;
    } on TripSheetFailure {
      rethrow;
    } catch (error) {
      debugPrint('TripSheetRepository.upload: $error');
      throw TripSheetFailure('Unable to upload trip sheet.');
    }
  }

  /// Fetch trip sheet records.
  Future<List<TripSheetRecord>> fetchRecords({
    required AppUser user,
    int? plantId,
    int? vehicleId,
    String? dateFrom,
    String? dateTo,
  }) async {
    final uri = Uri.parse('${_base}trip_sheet_list.php');

    try {
      final body = <String, dynamic>{
        'user_id': int.tryParse(user.id) ?? user.id,
        'user_role': user.role.name,
      };
      if (plantId != null && plantId > 0) {
        body['plant_id'] = plantId;
      }
      if (vehicleId != null && vehicleId > 0) {
        body['vehicle_id'] = vehicleId;
      }
      if (dateFrom != null && dateFrom.isNotEmpty) {
        body['date_from'] = dateFrom;
      }
      if (dateTo != null && dateTo.isNotEmpty) {
        body['date_to'] = dateTo;
      }

      final response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode >= 300) {
        throw TripSheetFailure(
          'Unable to load trip sheets (status: ${response.statusCode}).',
        );
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (payload['status'] != 'ok') {
        throw TripSheetFailure(
          payload['error']?.toString() ?? 'Unable to load trip sheets.',
        );
      }

      final recordsJson = payload['records'] as List<dynamic>? ?? const [];
      return recordsJson
          .map((item) => TripSheetRecord.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } on TripSheetFailure {
      rethrow;
    } catch (error) {
      debugPrint('TripSheetRepository.fetchRecords: $error');
      throw TripSheetFailure('Unable to load trip sheets.');
    }
  }

  /// Delete a trip sheet record uploaded by the current user.
  Future<void> deleteRecord({
    required AppUser user,
    required int recordId,
  }) async {
    final uri = Uri.parse('${_base}trip_sheet_delete.php');

    try {
      final response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'user_id': int.tryParse(user.id) ?? user.id,
          'record_id': recordId,
        }),
      );

      if (response.statusCode >= 300) {
        throw TripSheetFailure(
          'Unable to delete trip sheet (status: ${response.statusCode}).',
        );
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (payload['status'] != 'ok') {
        throw TripSheetFailure(
          payload['error']?.toString() ?? 'Unable to delete trip sheet.',
        );
      }
    } on TripSheetFailure {
      rethrow;
    } catch (error) {
      debugPrint('TripSheetRepository.deleteRecord: $error');
      throw TripSheetFailure('Unable to delete trip sheet.');
    }
  }

  String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
