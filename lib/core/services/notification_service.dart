import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/app_user.dart';
import 'auth_storage_service.dart';
import 'gps_ping_repository.dart';

class InAppNotificationData {
  InAppNotificationData({
    required this.id,
    required this.title,
    required this.body,
    required this.data,
    required this.receivedAt,
  });

  final String id;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime receivedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'data': data,
    'receivedAt': receivedAt.toIso8601String(),
  };

  static InAppNotificationData? fromJson(Map<String, dynamic> json) {
    try {
      return InAppNotificationData(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        data: json['data'] is Map
            ? Map<String, dynamic>.from(json['data'] as Map)
            : <String, dynamic>{},
        receivedAt:
            DateTime.tryParse(json['receivedAt']?.toString() ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

class GpsPingRefreshRequest {
  GpsPingRefreshRequest({
    required this.requestId,
    this.driverId,
    this.plantId,
    this.reason,
  });

  final String requestId;
  final String? driverId;
  final String? plantId;
  final String? reason;

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'driverId': driverId ?? '',
    'plantId': plantId ?? '',
    'reason': reason ?? '',
  };

  static GpsPingRefreshRequest? fromJson(Map<String, dynamic> json) {
    final requestId = json['requestId']?.toString().trim() ?? '';
    if (requestId.isEmpty) {
      return null;
    }
    return GpsPingRefreshRequest(
      requestId: requestId,
      driverId: json['driverId']?.toString().trim(),
      plantId: json['plantId']?.toString().trim(),
      reason: json['reason']?.toString().trim(),
    );
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final StreamController<InAppNotificationData> _inAppNotificationController =
      StreamController<InAppNotificationData>.broadcast();
  final StreamController<List<InAppNotificationData>>
  _inAppNotificationListController =
      StreamController<List<InAppNotificationData>>.broadcast();
  final List<InAppNotificationData> _recentInAppNotifications = [];
  final StreamController<bool> _bellVisibilityController =
      StreamController<bool>.broadcast();
  final StreamController<GpsPingRefreshRequest> _gpsPingRefreshController =
      StreamController<GpsPingRefreshRequest>.broadcast();
  final List<GpsPingRefreshRequest> _pendingGpsPingRefreshRequests = [];
  bool _isInitialized = false;
  String? _fcmToken;
  String? _activeInboxUserId;
  Timer? _serverInboxSyncTimer;
  int _notificationCounter = 0;
  int _bellHideRequests = 0;

  static const _inboxPrefsKey = 'in_app_notification_inbox_v1';
  static const _pendingGpsPingRefreshPrefsKey =
      'pending_gps_ping_refresh_requests_v1';
  static const _handledGpsPingRefreshPrefsPrefix =
      'gps_ping_refresh_handled_v1_';
  static const String _notificationInboxUrl =
      'https://sstranswaysindia.com/api/mobile/notification_inbox.php';
  static const String _fcmTokenUpdateUrl =
      'https://sstranswaysindia.com/api/mobile/fcm_token_update.php';
  static const Duration _serverInboxSyncInterval = Duration(seconds: 10);
  static const Duration _maxCachedLocationAge = Duration(minutes: 20);
  static const int _handledGpsPingRefreshLimit = 40;

  static String _resolveGpsPingRequestId(
    Map<String, dynamic> data, {
    String? fallbackRequestId,
    String? prefix,
  }) {
    final resolved =
        data['requestId']?.toString().trim() ??
        data['request_id']?.toString().trim() ??
        fallbackRequestId?.trim() ??
        '';
    if (resolved.isNotEmpty) {
      return resolved;
    }
    final tag = (prefix ?? 'push').trim().isEmpty ? 'push' : prefix!.trim();
    return '${tag}_${DateTime.now().millisecondsSinceEpoch}';
  }

  GpsPingRefreshRequest? _buildGpsPingRefreshRequestFromData(
    Map<String, dynamic> rawData, {
    required String fallbackRequestId,
    String? fallbackReason,
    bool alwaysRefresh = false,
    bool allowSourceOnlySignal = true,
  }) {
    final data = Map<String, dynamic>.from(rawData);
    final action = data['action']?.toString().trim().toLowerCase() ?? '';
    final notificationSource =
        data['notification_source']?.toString().trim().toLowerCase() ??
        data['source']?.toString().trim().toLowerCase() ??
        '';
    final shouldRefresh =
        alwaysRefresh ||
        action == 'refresh_gps_ping' ||
        action == 'gps_ping_refresh' ||
        (allowSourceOnlySignal &&
            notificationSource == 'driverdocs_notification');
    if (!shouldRefresh) {
      return null;
    }

    final requestId = _resolveGpsPingRequestId(
      data,
      fallbackRequestId: fallbackRequestId,
      prefix: 'push',
    );
    if (requestId.isEmpty) {
      return null;
    }

    return GpsPingRefreshRequest(
      requestId: requestId,
      driverId: data['driverId']?.toString().trim().isNotEmpty == true
          ? data['driverId']?.toString().trim()
          : data['driver_id']?.toString().trim(),
      plantId: data['plantId']?.toString().trim().isNotEmpty == true
          ? data['plantId']?.toString().trim()
          : data['plant_id']?.toString().trim(),
      reason: data['reason']?.toString().trim().isNotEmpty == true
          ? data['reason']?.toString().trim()
          : (data['body']?.toString().trim().isNotEmpty == true
                ? data['body']?.toString().trim()
                : fallbackReason?.trim()),
    );
  }

  GpsPingRefreshRequest? _buildGpsPingRefreshRequest(RemoteMessage message) {
    return _buildGpsPingRefreshRequestFromData(
      message.data,
      fallbackRequestId: _resolveGpsPingRequestId(
        message.data,
        fallbackRequestId: message.messageId,
        prefix: 'live_push',
      ),
      fallbackReason:
          message.notification?.body ??
          message.data['body']?.toString() ??
          message.data['message']?.toString(),
      alwaysRefresh: true,
    );
  }

  GpsPingRefreshRequest? _buildGpsPingRefreshRequestFromNotification(
    InAppNotificationData notification,
  ) {
    return _buildGpsPingRefreshRequestFromData(
      notification.data,
      fallbackRequestId: notification.id,
      fallbackReason: notification.body,
      // Inbox sync can backfill older items, so only explicit GPS-refresh
      // actions should trigger a new immediate ping from this path.
      allowSourceOnlySignal: false,
    );
  }

  void _emitGpsPingRefreshIfNeeded(RemoteMessage message) {
    final request = _buildGpsPingRefreshRequest(message);
    if (request == null) {
      return;
    }
    _queuePendingGpsPingRefreshRequest(request);
  }

  void _queuePendingGpsPingRefreshRequest(GpsPingRefreshRequest request) {
    _pendingGpsPingRefreshRequests.removeWhere(
      (item) => item.requestId == request.requestId,
    );
    if (_gpsPingRefreshController.hasListener) {
      _gpsPingRefreshController.add(request);
      return;
    }
    _pendingGpsPingRefreshRequests.add(request);
  }

  void _emitGpsPingRefreshForNotificationIfNeeded(
    InAppNotificationData notification,
  ) {
    final request = _buildGpsPingRefreshRequestFromNotification(notification);
    if (request == null) {
      return;
    }
    _queuePendingGpsPingRefreshRequest(request);
  }

  Future<void> _loadInboxFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_inboxPrefsKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final loaded = <InAppNotificationData>[];
      for (final entry in decoded) {
        if (entry is Map) {
          final parsed = InAppNotificationData.fromJson(
            Map<String, dynamic>.from(entry),
          );
          if (parsed != null && parsed.id.trim().isNotEmpty) {
            loaded.add(parsed);
          }
        }
      }
      _recentInAppNotifications
        ..clear()
        ..addAll(loaded);
      _emitNotificationState();
    } catch (_) {
      // ignore
    }
  }

  Future<void> _loadPendingGpsPingRefreshRequestsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingGpsPingRefreshPrefsKey);
      if (raw == null || raw.trim().isEmpty) {
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return;
      }
      final loaded = <GpsPingRefreshRequest>[];
      for (final entry in decoded) {
        if (entry is! Map) {
          continue;
        }
        final parsed = GpsPingRefreshRequest.fromJson(
          Map<String, dynamic>.from(entry),
        );
        if (parsed != null) {
          loaded.add(parsed);
        }
      }
      for (final request in loaded) {
        _pendingGpsPingRefreshRequests.removeWhere(
          (item) => item.requestId == request.requestId,
        );
        _pendingGpsPingRefreshRequests.add(request);
      }
      await prefs.remove(_pendingGpsPingRefreshPrefsKey);
    } catch (_) {
      // ignore
    }
  }

  static Future<void> persistPendingGpsPingRefreshRequest(
    GpsPingRefreshRequest request,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingGpsPingRefreshPrefsKey);
      final list = <dynamic>[];
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          list.addAll(decoded);
        }
      }
      list.removeWhere(
        (item) =>
            item is Map && item['requestId']?.toString() == request.requestId,
      );
      list.insert(0, request.toJson());
      if (list.length > 50) {
        list.removeRange(50, list.length);
      }
      await prefs.setString(_pendingGpsPingRefreshPrefsKey, jsonEncode(list));
    } catch (_) {
      // ignore
    }
  }

  static Future<bool> hasHandledGpsPingRefreshRequest(
    String userId,
    String requestId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final handled = prefs.getStringList(
      '$_handledGpsPingRefreshPrefsPrefix$userId',
    );
    if (handled == null || handled.isEmpty) {
      return false;
    }
    return handled.contains(requestId);
  }

  static Future<void> markGpsPingRefreshRequestHandled(
    String userId,
    String requestId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_handledGpsPingRefreshPrefsPrefix$userId';
    final handled = List<String>.from(prefs.getStringList(key) ?? const []);
    handled.remove(requestId);
    handled.insert(0, requestId);
    if (handled.length > _handledGpsPingRefreshLimit) {
      handled.removeRange(_handledGpsPingRefreshLimit, handled.length);
    }
    await prefs.setStringList(key, handled);
  }

  static bool matchesGpsPingRefreshRequest(
    AppUser user,
    GpsPingRefreshRequest request,
  ) {
    final userDriverId = user.driverId?.trim() ?? '';
    if (userDriverId.isEmpty) {
      return false;
    }

    final requestedDriverId = request.driverId?.trim() ?? '';
    if (requestedDriverId.isEmpty) {
      return true;
    }

    return requestedDriverId == userDriverId;
  }

  static bool _isFresh(Position? position) {
    if (position == null) {
      return false;
    }
    final age = DateTime.now().difference(position.timestamp);
    return age <= _maxCachedLocationAge;
  }

  static Future<bool> trySendGpsPingForPushInBackground(
    GpsPingRefreshRequest request,
  ) async {
    try {
      final user = await AuthStorageService.getUser();
      if (user == null || !matchesGpsPingRefreshRequest(user, request)) {
        return false;
      }

      final alreadyHandled = await hasHandledGpsPingRefreshRequest(
        user.id,
        request.requestId,
      );
      if (alreadyHandled) {
        return true;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return false;
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }

      final lastKnown = await Geolocator.getLastKnownPosition();
      Position? position;
      if (_isFresh(lastKnown)) {
        position = lastKnown;
      } else if (permission == LocationPermission.always) {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 10),
        );
      }

      if (position == null) {
        return false;
      }

      await GpsPingRepository().sendPing(
        driverId: user.driverId!.trim(),
        plantId: user.plantId ?? user.assignmentPlantId ?? user.defaultPlantId,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        timestamp: position.timestamp,
        source: 'mobile_fg_push',
      );
      await markGpsPingRefreshRequestHandled(user.id, request.requestId);
      return true;
    } catch (_) {
      return false;
    }
  }

  static GpsPingRefreshRequest buildGpsPingRefreshRequestForAnyPush(
    Map<String, dynamic> rawData, {
    String? fallbackRequestId,
    String? fallbackReason,
  }) {
    final data = Map<String, dynamic>.from(rawData);
    final requestId = _resolveGpsPingRequestId(
      data,
      fallbackRequestId: fallbackRequestId,
      prefix: 'push',
    );
    return GpsPingRefreshRequest(
      requestId: requestId,
      driverId: data['driverId']?.toString().trim().isNotEmpty == true
          ? data['driverId']?.toString().trim()
          : data['driver_id']?.toString().trim(),
      plantId: data['plantId']?.toString().trim().isNotEmpty == true
          ? data['plantId']?.toString().trim()
          : data['plant_id']?.toString().trim(),
      reason: data['reason']?.toString().trim().isNotEmpty == true
          ? data['reason']?.toString().trim()
          : fallbackReason?.trim(),
    );
  }

  Future<void> _persistInboxToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _recentInAppNotifications
          .take(50)
          .map((e) => e.toJson())
          .toList(growable: false);
      await prefs.setString(_inboxPrefsKey, jsonEncode(list));
    } catch (_) {
      // ignore
    }
  }

  InAppNotificationData _buildInAppNotification(RemoteMessage message) {
    final notification = message.notification;
    final data = Map<String, dynamic>.from(message.data);
    final title =
        notification?.title ?? data['title']?.toString() ?? 'SS Transways';
    final body =
        notification?.body ??
        data['body']?.toString() ??
        data['message']?.toString() ??
        '';
    final notificationId =
        data['server_notification_id']?.toString().trim() ?? '';
    final resolvedId = notificationId.isNotEmpty
        ? notificationId
        : (message.messageId?.isNotEmpty == true
              ? message.messageId!
              : 'local_${DateTime.now().millisecondsSinceEpoch}_${_notificationCounter++}');
    return InAppNotificationData(
      id: resolvedId,
      title: title,
      body: body,
      data: data,
      receivedAt: DateTime.now(),
    );
  }

  Future<void> _storeAndEmitInAppNotification(
    InAppNotificationData notification,
  ) async {
    _recentInAppNotifications.removeWhere((item) => item.id == notification.id);
    _recentInAppNotifications.insert(0, notification);
    if (_recentInAppNotifications.length > 50) {
      _recentInAppNotifications.removeRange(
        50,
        _recentInAppNotifications.length,
      );
    }
    if (!_inAppNotificationController.isClosed) {
      _inAppNotificationController.add(notification);
    }
    _emitNotificationState();
    await _persistInboxToPrefs();
  }

  bool _isServerBackedNotificationId(String id) => int.tryParse(id) != null;

  Future<void> bindInboxUser(String userId) async {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _activeInboxUserId = trimmed;
    _restartInboxSyncTimer();
    await syncInboxFromServer(userId: trimmed);
  }

  void unbindInboxUser() {
    _activeInboxUserId = null;
    _serverInboxSyncTimer?.cancel();
    _serverInboxSyncTimer = null;
  }

  void _restartInboxSyncTimer() {
    _serverInboxSyncTimer?.cancel();
    _serverInboxSyncTimer = Timer.periodic(_serverInboxSyncInterval, (_) {
      final userId = _activeInboxUserId;
      if (userId == null || userId.isEmpty) {
        return;
      }
      unawaited(syncInboxFromServer(userId: userId));
    });
  }

  Future<void> syncInboxFromServer({String? userId}) async {
    final targetUserId = (userId ?? _activeInboxUserId)?.trim();
    if (targetUserId == null || targetUserId.isEmpty) {
      return;
    }

    try {
      final payload = await _postInboxRequest({
        'action': 'list',
        'userId': targetUserId,
        'limit': 50,
      });
      if (payload is! Map<String, dynamic> ||
          payload['status'] != 'ok' ||
          payload['notifications'] is! List) {
        return;
      }

      final existingIds = _recentInAppNotifications
          .map((item) => item.id)
          .toSet();
      final serverNotifications = <InAppNotificationData>[];
      for (final entry in payload['notifications'] as List) {
        if (entry is! Map) {
          continue;
        }
        final mappedData = entry['data'] is Map
            ? Map<String, dynamic>.from(entry['data'] as Map)
            : <String, dynamic>{};
        final serverSource = entry['source']?.toString().trim() ?? '';
        if (serverSource.isNotEmpty) {
          mappedData.putIfAbsent('source', () => serverSource);
          mappedData.putIfAbsent('notification_source', () => serverSource);
        }
        final mapped = InAppNotificationData(
          id: entry['id']?.toString() ?? '',
          title: entry['title']?.toString() ?? '',
          body: entry['body']?.toString() ?? '',
          data: mappedData,
          receivedAt:
              DateTime.tryParse(entry['createdAt']?.toString() ?? '') ??
              DateTime.now(),
        );
        if (mapped.id.trim().isNotEmpty) {
          serverNotifications.add(mapped);
        }
      }

      for (final notification in serverNotifications) {
        if (!existingIds.contains(notification.id)) {
          _emitGpsPingRefreshForNotificationIfNeeded(notification);
        }
      }

      final serverIds = serverNotifications.map((item) => item.id).toSet();
      final localOnly = _recentInAppNotifications
          .where((item) => !serverIds.contains(item.id))
          .toList(growable: false);

      _recentInAppNotifications
        ..clear()
        ..addAll(serverNotifications)
        ..addAll(localOnly);

      if (_recentInAppNotifications.length > 50) {
        _recentInAppNotifications.removeRange(
          50,
          _recentInAppNotifications.length,
        );
      }

      _emitNotificationState();
      await _persistInboxToPrefs();
    } catch (_) {
      // ignore
    }
  }

  Future<void> _syncRemoveWithServer(String id) async {
    final userId = _activeInboxUserId;
    if (userId == null ||
        userId.isEmpty ||
        !_isServerBackedNotificationId(id)) {
      return;
    }

    try {
      await _postInboxRequest({
        'action': 'remove',
        'userId': userId,
        'notificationId': id,
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _syncClearWithServer() async {
    final userId = _activeInboxUserId;
    if (userId == null || userId.isEmpty) {
      return;
    }

    try {
      await _postInboxRequest({'action': 'clear', 'userId': userId});
    } catch (_) {
      // ignore
    }
  }

  Future<dynamic> _postInboxRequest(Map<String, dynamic> payload) async {
    final response = await http.post(
      Uri.parse(_notificationInboxUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Notification inbox request failed: HTTP ${response.statusCode}',
      );
    }
    return jsonDecode(response.body);
  }

  void _emitNotificationState() {
    if (!_inAppNotificationListController.isClosed) {
      _inAppNotificationListController.add(
        List.unmodifiable(_recentInAppNotifications),
      );
    }
  }

  Stream<bool> get bellVisibilityChanges => _bellVisibilityController.stream;
  bool get isBellHidden => _bellHideRequests > 0;
  String? get activeInboxUserId => _activeInboxUserId;

  void requestBellHide() {
    _bellHideRequests++;
    _emitBellVisibility();
  }

  void releaseBellHide() {
    if (_bellHideRequests == 0) return;
    _bellHideRequests--;
    _emitBellVisibility();
  }

  void forceShowBell() {
    if (_bellHideRequests == 0) return;
    _bellHideRequests = 0;
    _emitBellVisibility();
  }

  void _emitBellVisibility() {
    if (!_bellVisibilityController.isClosed) {
      _bellVisibilityController.add(isBellHidden);
    }
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Skip initialization on web platform
    if (kIsWeb) {
      _isInitialized = true;
      return;
    }

    try {
      // Initialize timezone
      tz.initializeTimeZones();

      // Android initialization settings
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS initialization settings
      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      final result = await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      if (result == false) {
        throw Exception('Failed to initialize notifications');
      }

      // Initialize Firebase Cloud Messaging
      await _initializeFCM();

      // Load persisted in-app inbox (best-effort).
      await _loadInboxFromPrefs();
      await _loadPendingGpsPingRefreshRequestsFromPrefs();

      _isInitialized = true;
    } catch (e) {
      if (kDebugMode) {
        print('Notification service initialization failed: $e');
      }
      _isInitialized = true; // Mark as initialized to prevent retries
    }
  }

  Future<void> _initializeFCM() async {
    // Skip web platform for now due to Firebase compatibility issues
    if (kIsWeb) {
      if (kDebugMode) {
        print('FCM initialization skipped on web platform');
      }
      return;
    }

    try {
      // Request permission for notifications
      NotificationSettings settings = await _firebaseMessaging
          .requestPermission(
            alert: true,
            announcement: false,
            badge: true,
            carPlay: false,
            criticalAlert: false,
            provisional: false,
            sound: true,
          );

      if (kDebugMode) {
        print('User granted permission: ${settings.authorizationStatus}');
      }

      // Get FCM token
      _fcmToken = await _firebaseMessaging.getToken();
      if (kDebugMode) {
        print('FCM Token: $_fcmToken');
      }

      // Save token to local storage
      if (_fcmToken != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', _fcmToken!);
        await _syncCurrentFcmTokenToServer();
      }

      // Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) async {
        _fcmToken = newToken;
        if (kDebugMode) {
          print('FCM Token refreshed: $newToken');
        }
        // Save new token
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', newToken);
        await _syncCurrentFcmTokenToServer();
      });

      // Handle background messages
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle notification taps when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // If the app was launched by tapping a notification, capture it too.
      final initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        await _handleNotificationTap(initialMessage);
      }
    } catch (e) {
      if (kDebugMode) {
        print('FCM initialization failed: $e');
      }
    }
  }

  Future<void> _syncCurrentFcmTokenToServer() async {
    final token = _fcmToken?.trim();
    if (token == null || token.isEmpty) {
      return;
    }

    try {
      final user = await AuthStorageService.getUser();
      final userId = user?.id.trim() ?? '';
      if (userId.isEmpty) {
        return;
      }

      final response = await http.post(
        Uri.parse(_fcmTokenUpdateUrl),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'fcmToken': token,
          'platform': 'mobile',
        }),
      );

      if (kDebugMode) {
        print(
          'FCM token sync response: ${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('FCM token sync failed: $e');
      }
    }
  }

  // Handle background messages
  static Future<void> _firebaseMessagingBackgroundHandler(
    RemoteMessage message,
  ) async {
    if (kDebugMode) {
      print('Handling a background message: ${message.messageId}');
      print('Message data: ${message.data}');
      print('Message notification: ${message.notification?.title}');
    }

    // Best-effort: persist to inbox so it can show inside the app too.
    // Note: background delivery depends on message type (data vs notification).
    try {
      final data = Map<String, dynamic>.from(message.data);
      final request = buildGpsPingRefreshRequestForAnyPush(
        data,
        fallbackRequestId: message.messageId,
        fallbackReason:
            message.notification?.body ??
            data['body']?.toString() ??
            data['message']?.toString(),
      );
      final sentImmediately = await trySendGpsPingForPushInBackground(request);
      if (!sentImmediately) {
        await persistPendingGpsPingRefreshRequest(request);
      }
      final title =
          message.notification?.title ??
          data['title']?.toString() ??
          'SS Transways';
      final body =
          message.notification?.body ??
          data['body']?.toString() ??
          data['message']?.toString() ??
          '';
      final serverId = data['server_notification_id']?.toString().trim() ?? '';
      final id = serverId.isNotEmpty
          ? serverId
          : (message.messageId?.isNotEmpty == true
                ? message.messageId!
                : 'bg_${DateTime.now().millisecondsSinceEpoch}');
      final entry = InAppNotificationData(
        id: id,
        title: title,
        body: body,
        data: data,
        receivedAt: DateTime.now(),
      );

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_inboxPrefsKey);
      final list = <dynamic>[];
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          list.addAll(decoded);
        }
      }
      list.removeWhere(
        (item) => item is Map && item['id']?.toString() == entry.id,
      );
      list.insert(0, entry.toJson());
      if (list.length > 50) {
        list.removeRange(50, list.length);
      }
      await prefs.setString(_inboxPrefsKey, jsonEncode(list));
    } catch (_) {
      // ignore
    }
  }

  // Handle foreground messages
  void _handleForegroundMessage(RemoteMessage message) async {
    if (kDebugMode) {
      print('Handling a foreground message: ${message.messageId}');
    }
    final inAppNotification = _buildInAppNotification(message);
    await _storeAndEmitInAppNotification(inAppNotification);

    final title = inAppNotification.title;
    final body = inAppNotification.body;
    final data = inAppNotification.data;
    if (title.isNotEmpty || body.isNotEmpty) {
      showNotification(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: title,
        body: body,
        payload: data.isEmpty ? '' : data.toString(),
      );
    }
    _emitGpsPingRefreshIfNeeded(message);
  }

  // Handle notification taps
  Future<void> _handleNotificationTap(RemoteMessage message) async {
    if (kDebugMode) {
      print('Notification tapped: ${message.messageId}');
      print('Message data: ${message.data}');
    }
    // Handle navigation based on message data

    // Also store it to the in-app inbox so it appears inside the app.
    final inAppNotification = _buildInAppNotification(message);
    await _storeAndEmitInAppNotification(inAppNotification);
    _emitGpsPingRefreshIfNeeded(message);
  }

  // Get FCM token
  String? get fcmToken => _fcmToken;

  // Get stored FCM token
  Future<String?> getStoredFCMToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('fcm_token');
  }

  Stream<InAppNotificationData> get inAppNotifications =>
      _inAppNotificationController.stream;

  Stream<GpsPingRefreshRequest> get gpsPingRefreshRequests =>
      _gpsPingRefreshController.stream;

  Future<void> hydratePendingGpsPingRefreshRequests() async {
    await _loadPendingGpsPingRefreshRequestsFromPrefs();
  }

  List<GpsPingRefreshRequest> takePendingGpsPingRefreshRequests() {
    final pending = List<GpsPingRefreshRequest>.from(
      _pendingGpsPingRefreshRequests,
    );
    _pendingGpsPingRefreshRequests.clear();
    return pending;
  }

  Stream<List<InAppNotificationData>> get inAppNotificationList =>
      _inAppNotificationListController.stream;

  List<InAppNotificationData> get recentInAppNotifications =>
      List.unmodifiable(_recentInAppNotifications);

  void removeInAppNotification(String id) {
    final before = _recentInAppNotifications.length;
    _recentInAppNotifications.removeWhere((item) => item.id == id);
    if (_recentInAppNotifications.length != before) {
      _emitNotificationState();
      _persistInboxToPrefs();
      unawaited(_syncRemoveWithServer(id));
    }
  }

  void clearInAppNotifications() {
    if (_recentInAppNotifications.isEmpty) {
      return;
    }
    _recentInAppNotifications.clear();
    _emitNotificationState();
    _persistInboxToPrefs();
    unawaited(_syncClearWithServer());
  }

  Future<bool> requestPermissions() async {
    // Skip permission request on web platform
    if (kIsWeb) {
      return true;
    }

    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      return status.isGranted;
    } else if (Platform.isIOS) {
      final status = await Permission.notification.request();
      return status.isGranted;
    }
    return true;
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) await initialize();

    // Skip notification on web platform
    if (kIsWeb) {
      if (kDebugMode) {
        print('Notification (Web): $title - $body');
      }
      return;
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'trip_notifications',
          'Trip Notifications',
          channelDescription: 'Notifications for trip-related events',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          icon: '@mipmap/ic_launcher',
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(id, title, body, details, payload: payload);
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    if (!_isInitialized) await initialize();

    // Skip notification on web platform
    if (kIsWeb) {
      if (kDebugMode) {
        print('Scheduled Notification (Web): $title - $body at $scheduledDate');
      }
      return;
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'trip_reminders',
          'Trip Reminders',
          channelDescription: 'Scheduled reminders for trip-related events',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          icon: '@mipmap/ic_launcher',
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      details,
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancelNotification(int id) async {
    if (kIsWeb) return;
    await _notifications.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    if (kIsWeb) return;
    await _notifications.cancelAll();
  }

  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    if (kIsWeb) return [];
    return await _notifications.pendingNotificationRequests();
  }

  void _onNotificationTapped(NotificationResponse response) {
    if (kDebugMode) {
      print('Notification tapped: ${response.payload}');
    }
    // Handle notification tap
    // You can navigate to specific screens based on the payload
  }

  // Trip-specific notification methods
  Future<void> notifyTripStarted({
    required String vehicleNumber,
    required String startKm,
  }) async {
    await showNotification(
      id: 1,
      title: 'Trip Started',
      body: 'Trip started for vehicle $vehicleNumber at KM $startKm',
      payload: 'trip_started',
    );
  }

  Future<void> notifyTripEnded({
    required String vehicleNumber,
    required String endKm,
    required String runKm,
  }) async {
    await showNotification(
      id: 2,
      title: 'Trip Ended',
      body:
          'Trip ended for vehicle $vehicleNumber. End KM: $endKm, Run KM: $runKm',
      payload: 'trip_ended',
    );
  }

  Future<void> notifyAttendanceMarked({
    required String type,
    required String time,
  }) async {
    await showNotification(
      id: 3,
      title: 'Attendance Marked',
      body: '$type attendance marked at $time',
      payload: 'attendance_marked',
    );
  }

  Future<void> notifySalaryCredited({
    required String amount,
    required String month,
  }) async {
    await showNotification(
      id: 4,
      title: 'Salary Credited',
      body: 'Salary of ₹$amount credited for $month',
      payload: 'salary_credited',
    );
  }

  Future<void> notifyAdvanceRequestStatus({
    required String status,
    required String amount,
  }) async {
    await showNotification(
      id: 5,
      title: 'Advance Request $status',
      body: 'Your advance request of ₹$amount has been $status',
      payload: 'advance_request_$status',
    );
  }
}
