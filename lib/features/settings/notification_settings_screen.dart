import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/services/notification_service.dart';
import '../../core/widgets/app_toast.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final NotificationService _notificationService = NotificationService();

  bool _tripNotifications = true;
  bool _attendanceNotifications = true;
  bool _salaryNotifications = true;
  bool _advanceNotifications = true;
  bool _reminderNotifications = true;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      // Initialize notification service
      await _notificationService.initialize();

      // Request permissions (skipped on web)
      final hasPermission = await _notificationService.requestPermissions();

      if (!hasPermission && mounted && !kIsWeb) {
        showAppToast(
          context,
          'Notification permissions are required for this feature',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppToast(
          context,
          'Failed to load notification settings',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _testNotification() async {
    try {
      await _notificationService.showNotification(
        id: 999,
        title: 'Test Notification',
        body: 'This is a test notification from SS Transways India',
        payload: 'test',
      );

      if (mounted) {
        showAppToast(context, 'Test notification sent successfully');
      }
    } catch (e) {
      if (mounted) {
        showAppToast(
          context,
          'Failed to send test notification',
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notification Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notification Preferences',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Trip Notifications
                  SwitchListTile(
                    title: const Text('Trip Notifications'),
                    subtitle: const Text(
                      'Get notified when trips start and end',
                    ),
                    value: _tripNotifications,
                    onChanged: (value) {
                      setState(() => _tripNotifications = value);
                    },
                  ),

                  // Attendance Notifications
                  SwitchListTile(
                    title: const Text('Attendance Notifications'),
                    subtitle: const Text(
                      'Get notified when attendance is marked',
                    ),
                    value: _attendanceNotifications,
                    onChanged: (value) {
                      setState(() => _attendanceNotifications = value);
                    },
                  ),

                  // Salary Notifications
                  SwitchListTile(
                    title: const Text('Salary Notifications'),
                    subtitle: const Text('Get notified about salary credits'),
                    value: _salaryNotifications,
                    onChanged: (value) {
                      setState(() => _salaryNotifications = value);
                    },
                  ),

                  // Advance Notifications
                  SwitchListTile(
                    title: const Text('Advance Notifications'),
                    subtitle: const Text(
                      'Get notified about advance request status',
                    ),
                    value: _advanceNotifications,
                    onChanged: (value) {
                      setState(() => _advanceNotifications = value);
                    },
                  ),

                  // Reminder Notifications
                  SwitchListTile(
                    title: const Text('Reminder Notifications'),
                    subtitle: const Text(
                      'Get reminder notifications for important tasks',
                    ),
                    value: _reminderNotifications,
                    onChanged: (value) {
                      setState(() => _reminderNotifications = value);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Test Notifications',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Test if notifications are working properly on your device.',
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _testNotification,
                      icon: const Icon(Icons.notifications),
                      label: const Text('Send Test Notification'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notification Info',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (kIsWeb) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: const Text(
                        'Note: Notifications are not supported on web browsers. This feature works on mobile devices (Android/iOS).',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const Text(
                    '• Notifications help you stay updated with important events\n'
                    '• You can customize which types of notifications to receive\n'
                    '• Make sure notification permissions are enabled in your device settings\n'
                    '• Notifications work even when the app is in the background',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}



