import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

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
  bool _isInitialized = false;
  String? _fcmToken;
  int _notificationCounter = 0;
  int _bellHideRequests = 0;

  static const _inboxPrefsKey = 'in_app_notification_inbox_v1';

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
    final notificationId = message.messageId?.isNotEmpty == true
        ? message.messageId!
        : 'local_${DateTime.now().millisecondsSinceEpoch}_${_notificationCounter++}';
    return InAppNotificationData(
      id: notificationId,
      title: title,
      body: body,
      data: data,
      receivedAt: DateTime.now(),
    );
  }

  Future<void> _storeAndEmitInAppNotification(
    InAppNotificationData notification,
  ) async {
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

  void _emitNotificationState() {
    if (!_inAppNotificationListController.isClosed) {
      _inAppNotificationListController.add(
        List.unmodifiable(_recentInAppNotifications),
      );
    }
  }

  Stream<bool> get bellVisibilityChanges => _bellVisibilityController.stream;
  bool get isBellHidden => _bellHideRequests > 0;

  void requestBellHide() {
    _bellHideRequests++;
    _emitBellVisibility();
  }

  void releaseBellHide() {
    if (_bellHideRequests == 0) return;
    _bellHideRequests--;
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
      }

      // Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        if (kDebugMode) {
          print('FCM Token refreshed: $newToken');
        }
        // Save new token
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString('fcm_token', newToken);
        });
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
      final title =
          message.notification?.title ??
          data['title']?.toString() ??
          'SS Transways';
      final body =
          message.notification?.body ??
          data['body']?.toString() ??
          data['message']?.toString() ??
          '';
      final id = message.messageId?.isNotEmpty == true
          ? message.messageId!
          : 'bg_${DateTime.now().millisecondsSinceEpoch}';
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
    }
  }

  void clearInAppNotifications() {
    if (_recentInAppNotifications.isEmpty) {
      return;
    }
    _recentInAppNotifications.clear();
    _emitNotificationState();
    _persistInboxToPrefs();
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
