import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_user.dart';
import '../models/watch_ads_models.dart';

class WatchAdsRepository {
  WatchAdsRepository({http.Client? client, Uri? baseUri, AppUser? currentUser})
    : _client = client ?? http.Client(),
      _baseUri =
          baseUri ?? Uri.parse('https://sstranswaysindia.com/api/rewards/'),
      _currentUser = currentUser;

  final http.Client _client;
  final Uri _baseUri;
  final AppUser? _currentUser;

  Uri _resolve(String path, [Map<String, String>? query]) {
    return _baseUri.replace(
      path: '${_baseUri.path}$path',
      queryParameters: query ?? _baseUri.queryParameters,
    );
  }

  Map<String, String> _authQuery([AppUser? user]) {
    final target = user ?? _currentUser;
    if (target == null) return const {};

    String? role;
    switch (target.role) {
      case UserRole.driver:
        role = 'driver';
        break;
      case UserRole.supervisor:
        role = 'supervisor';
        break;
      case UserRole.admin:
        role = 'admin';
        break;
      case UserRole.referral:
        role = 'referral';
        break;
    }

    int? toInt(String? value) => value == null ? null : int.tryParse(value);

    final Map<String, String> params = {};
    final userId = toInt(target.id);
    if (userId != null) params['userId'] = userId.toString();
    final driverId = toInt(target.driverId);
    if (driverId != null) params['driverId'] = driverId.toString();
    if (role != null) params['role'] = role;
    return params;
  }

  Map<String, dynamic> _decodeJsonMap(String body, String action) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw Exception('$action failed: empty response body');
    }
    if (_isLikelyHtml(trimmed)) {
      throw Exception(
        '$action failed: expected JSON but received HTML. '
        'Body preview: ${_truncate(trimmed)}',
      );
    }
    try {
      final parsed = json.decode(trimmed);
      if (parsed is Map<String, dynamic>) {
        return parsed;
      }
      throw Exception(
        '$action failed: unexpected payload type ${parsed.runtimeType}. '
        'Body preview: ${_truncate(trimmed)}',
      );
    } on FormatException catch (err) {
      throw Exception(
        '$action failed: invalid JSON (${err.message}). '
        'Body preview: ${_truncate(trimmed)}',
      );
    }
  }

  bool _isLikelyHtml(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('<!doctype') ||
        lower.startsWith('<html') ||
        lower.startsWith('<head') ||
        lower.startsWith('<body') ||
        lower.startsWith('<br') ||
        lower.contains('<html') ||
        lower.contains('<body') ||
        lower.contains('<br');
  }

  String _truncate(String value, [int maxLength = 160]) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength)}…';
  }

  Future<WatchAdsStatus> fetchStatus({AppUser? user}) async {
    final uri = _resolve('watch/status.php', _authQuery(user));
    final response = await _client.get(uri);
    if (response.statusCode >= 300) {
      throw Exception(
        'Failed to load watch ads status (${response.statusCode})',
      );
    }
    final decoded = _decodeJsonMap(response.body, 'Watch ads status fetch');
    if (decoded['ok'] != true) {
      throw Exception(decoded['error']?.toString() ?? 'Failed to load status');
    }
    return WatchAdsStatus.fromJson(decoded);
  }

  Future<WatchAdsSession> startSession({
    AppUser? user,
    String adNetwork = 'admob',
  }) async {
    final uri = _resolve('watch/start.php', _authQuery(user));
    final body = json.encode({'ad_network': adNetwork});
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode >= 300) {
      throw Exception('Unable to start watch session (${response.statusCode})');
    }
    final decoded = _decodeJsonMap(response.body, 'Watch ads session start');
    if (decoded['ok'] != true) {
      throw Exception(
        decoded['error']?.toString() ?? 'Unable to start session',
      );
    }
    final sessionJson =
        decoded['session'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return WatchAdsSession.fromJson(sessionJson);
  }

  Future<WatchAdsConfirmResult> confirmSession({
    required String sessionToken,
    AppUser? user,
  }) async {
    final uri = _resolve('watch/confirm.php', _authQuery(user));
    final body = json.encode({'session_token': sessionToken});
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode >= 300) {
      throw Exception('Unable to confirm reward (${response.statusCode})');
    }
    final decoded = _decodeJsonMap(response.body, 'Watch ads reward confirm');
    if (decoded['ok'] != true) {
      throw Exception(
        decoded['error']?.toString() ?? 'Unable to confirm reward',
      );
    }
    return WatchAdsConfirmResult.fromJson(decoded);
  }
}
