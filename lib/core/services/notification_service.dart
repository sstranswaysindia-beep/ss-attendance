import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:http/http.dart' as http;
import 'dart:convert';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

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

      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      _isInitialized = true;
    } catch (e) {
      if (kDebugMode) {
        print('Notification service initialization failed: $e');
      }
      _isInitialized = true; // Mark as initialized to prevent retries
    }
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
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
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

  // Attendance reminder notifications
  Future<void> scheduleCheckInReminder({String? driverId}) async {
    if (kIsWeb) return;

    // Cancel any existing check-in reminder
    await cancelNotification(100);

    // Schedule for 9:00 AM today (if not passed) or tomorrow
    final now = DateTime.now();
    DateTime scheduledTime = DateTime(now.year, now.month, now.day, 9, 0);

    // If 9 AM has already passed today, schedule for tomorrow
    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }

    await scheduleNotification(
      id: 100,
      title: 'Check-In Reminder',
      body: 'Don\'t forget to check in for today! It\'s 9:00 AM.',
      scheduledDate: scheduledTime,
      payload: 'checkin_reminder',
    );
  }

  Future<void> scheduleCheckOutReminder({String? driverId}) async {
    if (kIsWeb) return;

    // Cancel any existing check-out reminder
    await cancelNotification(101);

    // Schedule for 9:00 PM today (if not passed) or tomorrow
    final now = DateTime.now();
    DateTime scheduledTime = DateTime(now.year, now.month, now.day, 21, 0);

    // If 9 PM has already passed today, schedule for tomorrow
    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }

    await scheduleNotification(
      id: 101,
      title: 'Check-Out Reminder',
      body: 'Don\'t forget to check out for today! It\'s 9:00 PM.',
      scheduledDate: scheduledTime,
      payload: 'checkout_reminder',
    );
  }

  Future<void> cancelCheckInReminder() async {
    await cancelNotification(100);
  }

  Future<void> cancelCheckOutReminder() async {
    await cancelNotification(101);
  }

  // Daily recurring reminders
  Future<void> scheduleDailyReminders() async {
    if (kIsWeb) return;

    // Cancel existing reminders
    await cancelCheckInReminder();
    await cancelCheckOutReminder();

    // Schedule check-in reminder for 9:00 AM
    await scheduleCheckInReminder();

    // Schedule check-out reminder for 9:00 PM
    await scheduleCheckOutReminder();
  }

  // Check if check-in is done for today
  Future<bool> isCheckInDoneToday({required String driverId}) async {
    if (kIsWeb) return true; // Skip on web

    try {
      final response = await http.get(
        Uri.parse(
          'https://sstranswaysindia.com/api/mobile/attendance_history.php',
        ),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true && data['data'] != null) {
          final List<dynamic> records = data['data'];
          final today = DateTime.now();
          final todayStr =
              '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

          // Check if there's a check-in record for today
          for (final record in records) {
            if (record['driver_id']?.toString() == driverId &&
                record['date']?.toString().startsWith(todayStr) == true &&
                record['action']?.toString() == 'check_in') {
              return true;
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error checking check-in status: $e');
      }
    }
    return false;
  }

  // Check if check-out is done for today
  Future<bool> isCheckOutDoneToday({required String driverId}) async {
    if (kIsWeb) return true; // Skip on web

    try {
      final response = await http.get(
        Uri.parse(
          'https://sstranswaysindia.com/api/mobile/attendance_history.php',
        ),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true && data['data'] != null) {
          final List<dynamic> records = data['data'];
          final today = DateTime.now();
          final todayStr =
              '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

          // Check if there's a check-out record for today
          for (final record in records) {
            if (record['driver_id']?.toString() == driverId &&
                record['date']?.toString().startsWith(todayStr) == true &&
                record['action']?.toString() == 'check_out') {
              return true;
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error checking check-out status: $e');
      }
    }
    return false;
  }

  // Smart check-in reminder - only sends if check-in is not done
  Future<void> sendCheckInReminderIfNeeded({required String driverId}) async {
    if (kIsWeb) return;

    final isCheckInDone = await isCheckInDoneToday(driverId: driverId);
    if (!isCheckInDone) {
      await showNotification(
        id: 100,
        title: 'Check-In Reminder',
        body: 'You haven\'t checked in today! Please check in now.',
        payload: 'checkin_reminder',
      );
    }
  }

  // Smart check-out reminder - only sends if check-out is not done
  Future<void> sendCheckOutReminderIfNeeded({required String driverId}) async {
    if (kIsWeb) return;

    final isCheckOutDone = await isCheckOutDoneToday(driverId: driverId);
    if (!isCheckOutDone) {
      await showNotification(
        id: 101,
        title: 'Check-Out Reminder',
        body: 'You haven\'t checked out today! Please check out now.',
        payload: 'checkout_reminder',
      );
    }
  }
}
