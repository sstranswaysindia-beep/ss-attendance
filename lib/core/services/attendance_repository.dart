import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../models/admin_attendance_overview.dart';
import '../models/attendance_record.dart';
import '../models/daily_attendance_summary.dart';
import '../models/monthly_stat.dart';

class AttendanceFailure implements Exception {
  AttendanceFailure(this.message);

  final String message;

  @override
  String toString() => 'AttendanceFailure: $message';
}

enum AttendanceAction { checkIn, checkOut }

class AttendanceSubmissionResult {
  const AttendanceSubmissionResult({
    required this.attendanceId,
    required this.action,
    required this.timestamp,
    this.photoUrl,
  });

  factory AttendanceSubmissionResult.fromJson(Map<String, dynamic> json) {
    return AttendanceSubmissionResult(
      attendanceId: json['attendanceId']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      timestamp: json['timestamp']?.toString() ?? '',
      photoUrl: json['photo']?.toString(),
    );
  }

  final String attendanceId;
  final String action;
  final String timestamp;
  final String? photoUrl;
}

class AttendanceRepository {
  AttendanceRepository({
    http.Client? client,
    Uri? submitEndpoint,
    Uri? historyEndpoint,
    Uri? statsEndpoint,
    Uri? deleteEndpoint,
    Uri? adjustRequestEndpoint,
    Uri? adminOverviewEndpoint,
  }) : _client = client ?? http.Client(),
       _submitEndpoint = submitEndpoint ?? Uri.parse(_defaultSubmitEndpoint),
       _historyEndpoint = historyEndpoint ?? Uri.parse(_defaultHistoryEndpoint),
       _statsEndpoint = statsEndpoint ?? Uri.parse(_defaultStatsEndpoint),
       _deleteEndpoint = deleteEndpoint ?? Uri.parse(_defaultDeleteEndpoint),
       _adjustRequestEndpoint =
           adjustRequestEndpoint ?? Uri.parse(_defaultAdjustRequestEndpoint),
       _adminOverviewEndpoint =
           adminOverviewEndpoint ?? Uri.parse(_defaultAdminOverviewEndpoint);

  static const String _defaultSubmitEndpoint =
      'https://sstranswaysindia.com/api/mobile/attendance_submit.php';
  static const String _defaultHistoryEndpoint =
      'https://sstranswaysindia.com/api/mobile/attendance_history.php';
  static const String _defaultStatsEndpoint =
      'https://sstranswaysindia.com/api/mobile/monthly_stats.php';
  static const String _defaultDeleteEndpoint =
      'https://sstranswaysindia.com/api/mobile/attendance_delete.php';
  static const String _defaultAdjustRequestEndpoint =
      'https://sstranswaysindia.com/api/mobile/attendance_adjust_request_submit.php';
  static const String _defaultAdminOverviewEndpoint =
      'https://sstranswaysindia.com/api/mobile/attendance_admin_overview.php';

  final http.Client _client;
  final Uri _submitEndpoint;
  final Uri _historyEndpoint;
  final Uri _statsEndpoint;
  final Uri _deleteEndpoint;
  final Uri _adjustRequestEndpoint;
  final Uri _adminOverviewEndpoint;

  Future<AttendanceSubmissionResult> submit({
    required String driverId,
    required String plantId,
    required String vehicleId,
    String? assignmentId,
    AttendanceAction action = AttendanceAction.checkIn,
    File? photoFile,
    String? notes,
    DateTime? timestamp,
    Map<String, dynamic>? locationJson,
  }) async {
    final request = http.MultipartRequest('POST', _submitEndpoint);
    request.fields.addAll(<String, String>{
      'driverId': driverId,
      'plantId': plantId,
      'vehicleId': vehicleId,
      'action': action == AttendanceAction.checkIn ? 'check_in' : 'check_out',
      'source': 'mobile',
      'timestamp': (timestamp ?? DateTime.now()).toIso8601String(),
    });

    if (assignmentId != null && assignmentId.isNotEmpty) {
      request.fields['assignmentId'] = assignmentId;
    }

    if (notes != null && notes.isNotEmpty) {
      request.fields['notes'] = notes;
    }

    if (locationJson != null && locationJson.isNotEmpty) {
      request.fields['locationJson'] = jsonEncode(locationJson);
    }

    if (photoFile != null && await photoFile.exists()) {
      // Import ImageUtils for compression
      final compressedBytes = await _compressPhotoForUpload(photoFile.path);
      if (compressedBytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'photo',
            compressedBytes,
            filename: 'attendance_photo.jpg',
          ),
        );

        // Add server path information for proper folder structure
        final now = DateTime.now();
        final dateFolder =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        request.fields['photo_path'] =
            'public_html/DriverDocs/uploads/$driverId/$dateFolder/';
        request.fields['photo_filename'] =
            '${action == AttendanceAction.checkIn ? 'checkin' : 'checkout'}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}.jpg';
      }
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    final statusCode = response.statusCode;

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw AttendanceFailure(
        'Invalid response from server (status: $statusCode).',
      );
    }

    if (statusCode != 200 || payload['status'] != 'ok') {
      final errorMessage = payload['error']?.toString();
      throw AttendanceFailure(errorMessage ?? 'Unable to submit attendance.');
    }

    return AttendanceSubmissionResult.fromJson(payload);
  }

  Future<List<AttendanceRecord>> fetchHistory({
    required String driverId,
    required DateTime month,
    int? limit,
  }) async {
    final formattedMonth =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
    final params = <String, String>{
      'driverId': driverId,
      'month': formattedMonth,
    };
    if (limit != null) {
      params['limit'] = limit.toString();
    }
    final uri = _historyEndpoint.replace(queryParameters: params);

    final response = await _client.get(uri);
    final statusCode = response.statusCode;
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw AttendanceFailure(
        'Invalid response from server (status: $statusCode).',
      );
    }

    if (statusCode != 200 || payload['status'] != 'ok') {
      throw AttendanceFailure(
        payload['error']?.toString() ?? 'Unable to load attendance history.',
      );
    }

    final items =
        payload['records'] as List<dynamic>? ??
        payload['data'] as List<dynamic>? ??
        const [];
    return items
        .map((item) => AttendanceRecord.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<AttendanceRecord?> fetchLatestRecord({
    required String driverId,
    required DateTime month,
  }) async {
    final records = await fetchHistory(
      driverId: driverId,
      month: month,
      limit: 1,
    );
    return records.isNotEmpty ? records.first : null;
  }

  Future<void> deleteAttendance({
    required String driverId,
    required String attendanceId,
  }) async {
    final response = await _client.post(
      _deleteEndpoint,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'driverId': driverId,
        'attendanceId': attendanceId,
      }),
    );

    if (response.statusCode >= 300) {
      String message = 'Unable to delete attendance.';
      try {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        message = payload['error']?.toString() ?? message;
      } catch (_) {}
      throw AttendanceFailure(message);
    }
  }

  Future<void> submitAdjustRequest({
    required String driverId,
    required String requestedById,
    required DateTime proposedIn,
    required DateTime proposedOut,
    required String reason,
    String? plantId,
    String? vehicleId,
  }) async {
    final response = await _client.post(
      _adjustRequestEndpoint,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'driverId': driverId,
        'requestedById': requestedById,
        'proposedIn': proposedIn.toIso8601String(),
        'proposedOut': proposedOut.toIso8601String(),
        'reason': reason,
        if (plantId != null && plantId.isNotEmpty) 'plantId': plantId,
        if (vehicleId != null && vehicleId.isNotEmpty) 'vehicleId': vehicleId,
      }),
    );

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw AttendanceFailure(
        'Invalid response from server (status: ${response.statusCode}).',
      );
    }

    if (response.statusCode >= 300 || payload['status'] != 'ok') {
      throw AttendanceFailure(
        payload['error']?.toString() ?? 'Unable to submit request.',
      );
    }
  }

  Future<List<MonthlyStat>> fetchMonthlyStats({
    required String driverId,
    int limit = 12,
  }) async {
    final uri = _statsEndpoint.replace(
      queryParameters: <String, String>{
        'driverId': driverId,
        'limit': limit.toString(),
      },
    );

    final response = await _client.get(uri);
    final statusCode = response.statusCode;
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw AttendanceFailure(
        'Invalid response from server (status: $statusCode).',
      );
    }

    if (statusCode != 200 || payload['status'] != 'ok') {
      throw AttendanceFailure(
        payload['error']?.toString() ?? 'Unable to load statistics.',
      );
    }

    final stats = payload['stats'] as List<dynamic>? ?? const [];
    return stats
        .map((item) => MonthlyStat.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<AdminAttendanceOverview> fetchAdminOverview({
    required DateTime month,
    String? searchTerm,
    String? plantId,
  }) async {
    final formattedMonth =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
    final queryParameters = <String, String>{'month': formattedMonth};
    final trimmedSearch = searchTerm?.trim();
    if (trimmedSearch != null && trimmedSearch.isNotEmpty) {
      queryParameters['search'] = trimmedSearch;
    }
    if (plantId != null && plantId.isNotEmpty) {
      queryParameters['plantId'] = plantId;
    }
    final uri = _adminOverviewEndpoint.replace(
      queryParameters: queryParameters,
    );

    final response = await _client.get(uri);
    final statusCode = response.statusCode;
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw AttendanceFailure(
        'Invalid response from server (status: $statusCode).',
      );
    }

    if (statusCode != 200 || payload['status'] != 'ok') {
      throw AttendanceFailure(
        payload['error']?.toString() ?? 'Unable to load attendance overview.',
      );
    }

    return AdminAttendanceOverview.fromJson(payload);
  }

  Future<List<DailyAttendanceSummary>> fetchDailySummary({
    required String driverId,
    required DateTime month,
  }) async {
    final records = await fetchHistory(driverId: driverId, month: month);
    final Map<String, _DailyAccumulator> buckets = {};

    for (final record in records) {
      final inTimeRaw = record.inTime;
      if (inTimeRaw == null || inTimeRaw.isEmpty) {
        continue;
      }
      final inDateTime = DateTime.tryParse(inTimeRaw);
      if (inDateTime == null) {
        continue;
      }
      final key =
          '${inDateTime.year}-${inDateTime.month.toString().padLeft(2, '0')}-${inDateTime.day.toString().padLeft(2, '0')}';
      final bucket = buckets.putIfAbsent(
        key,
        () => _DailyAccumulator(date: inDateTime),
      );
      bucket.addInTime(inDateTime);

      final outTimeRaw = record.outTime;
      if (outTimeRaw != null && outTimeRaw.isNotEmpty) {
        final outDateTime = DateTime.tryParse(outTimeRaw);
        if (outDateTime != null) {
          bucket.addOutTime(outDateTime);
          final duration = outDateTime.difference(inDateTime);
          if (!duration.isNegative) {
            bucket.addDuration(duration);
          }
        }
      } else {
        bucket.markOpenShift();
      }
    }

    final summaries = buckets.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return summaries
        .map(
          (bucket) => DailyAttendanceSummary(
            dateLabel: bucket.formattedDate,
            inTimes: bucket.inTimes,
            outTimes: bucket.outTimes,
            totalMinutes: bucket.totalMinutes,
            hasOpenShift: bucket.hasOpenShift,
          ),
        )
        .toList(growable: false);
  }

  /// Compress photo for upload with proper quality and size
  Future<Uint8List?> _compressPhotoForUpload(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      // Resize image to max 800x800 while maintaining aspect ratio
      final resizedImage = img.copyResize(
        image,
        width: image.width > image.height ? 800 : null,
        height: image.height > image.width ? 800 : null,
        maintainAspect: true,
      );

      // Compress as JPEG with 85% quality for optimal file size
      final compressedBytes = img.encodeJpg(resizedImage, quality: 85);
      return Uint8List.fromList(compressedBytes);
    } catch (e) {
      print('Error compressing photo for upload: $e');
      return null;
    }
  }
}

class _DailyAccumulator {
  _DailyAccumulator({required this.date});

  final DateTime date;
  final List<String> inTimes = <String>[];
  final List<String> outTimes = <String>[];
  Duration _total = Duration.zero;
  bool hasOpenShift = false;

  void addInTime(DateTime inTime) {
    inTimes.add(_formatTime(inTime));
  }

  void addOutTime(DateTime outTime) {
    outTimes.add(_formatTime(outTime));
  }

  void addDuration(Duration value) {
    _total += value;
  }

  void markOpenShift() {
    hasOpenShift = true;
  }

  int get totalMinutes => _total.inMinutes;

  String get formattedDate =>
      '${date.day.toString().padLeft(2, '0')} ${_monthNames[date.month - 1]} ${date.year}';

  static String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

const List<String> _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
