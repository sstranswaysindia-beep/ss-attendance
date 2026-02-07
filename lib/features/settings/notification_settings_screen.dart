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

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      // Initialize notification service (don't throw on failure)
      try {
        await _notificationService.initialize();
      } catch (e) {
        print('Notification service initialization failed: $e');
        // Continue anyway - user can still test notifications
      }

      // Request permissions (skipped on web)
      try {
        final hasPermission = await _notificationService.requestPermissions();
        if (!hasPermission && mounted && !kIsWeb) {
          showAppToast(
            context,
            'Notification permissions are required for this feature',
            isError: true,
          );
        }
      } catch (e) {
        print('Permission request failed: $e');
        // Continue anyway
      }
    } catch (e) {
      if (mounted) {
        print('Notification settings load error: $e');
        // Only show error if it's not a web platform issue
        if (!kIsWeb) {
          showAppToast(
            context,
            'Some notification features may not work properly',
            isError: true,
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const primaryGreen = Color(0xFF1B8E3E);
    const lightGreen = Color(0xFFE8F7EE);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notification Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Notification Settings',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.white,
            surfaceTintColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: primaryGreen.withOpacity(0.25)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notification Preferences',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: primaryGreen,
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
                    activeColor: primaryGreen,
                    activeTrackColor: lightGreen,
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
                    activeColor: primaryGreen,
                    activeTrackColor: lightGreen,
                  ),

                  // Salary Notifications
                  SwitchListTile(
                    title: const Text('Salary Notifications'),
                    subtitle: const Text('Get notified about salary credits'),
                    value: _salaryNotifications,
                    onChanged: (value) {
                      setState(() => _salaryNotifications = value);
                    },
                    activeColor: primaryGreen,
                    activeTrackColor: lightGreen,
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
                    activeColor: primaryGreen,
                    activeTrackColor: lightGreen,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Card(
            color: Colors.white,
            surfaceTintColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: primaryGreen.withOpacity(0.25)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notification Info',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: primaryGreen,
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
