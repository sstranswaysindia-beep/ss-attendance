import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/models/app_user.dart';
import '../../core/models/driver_vehicle.dart';
import '../../core/models/attendance_record.dart';
import '../../core/services/assignment_repository.dart';
import '../../core/services/finance_repository.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/services/gps_ping_repository.dart';
import '../../core/services/gps_ping_service.dart';
import '../../core/services/profile_repository.dart';
import '../../core/services/app_update_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/profile_photo_widget.dart';
import '../meter/meter_reading_sheet.dart';
import '../../core/widgets/in_app_notification_banner.dart';
import '../../core/widgets/update_available_sheet.dart';
import '../attendance/attendance_adjust_request_screen.dart';
import '../attendance/attendance_history_screen.dart';
import '../attendance/check_in_out_screen.dart';
import '../finance/salary_advance_screen.dart';
import '../finance/advance_salary_screen.dart';
import '../profile/driver_profile_screen.dart';
import '../settings/notification_settings_screen.dart';
import '../statistics/monthly_statistics_screen.dart';
import '../trips/trip_screen.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({
    required this.user,
    required this.onLogout,
    super.key,
  });

  final AppUser user;
  final VoidCallback onLogout;

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen>
    with SingleTickerProviderStateMixin {
  late DateTime _now;
  Timer? _ticker;
  late String? _selectedVehicleId;
  late String? _selectedVehicleNumber;
  bool _isChangingVehicle = false;

  final AssignmentRepository _assignmentRepository = AssignmentRepository();
  final FinanceRepository _financeRepository = FinanceRepository();
  final AttendanceRepository _attendanceRepository = AttendanceRepository();
  final GpsPingRepository _gpsPingRepository = GpsPingRepository();
  final ProfileRepository _profileRepository = ProfileRepository();
  final AppUpdateService _appUpdateService = AppUpdateService();
  GpsPingService? _gpsPingService;

  AttendanceRecord? _latestShift;
  bool _isLoadingShift = true;
  bool _isUploadingPhoto = false;
  String? _shiftSummary;
  bool _isAttendanceLockedToday = false;

  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;

  List<_NotificationItem> _systemNotifications = [
    const _NotificationItem(message: 'Loading...', type: NotificationType.info),
  ];
  final List<_NotificationItem> _pushNotifications = [];
  StreamSubscription<InAppNotificationData>? _pushNotificationSubscription;
  StreamSubscription<List<InAppNotificationData>>?
  _pushNotificationListSubscription;
  String? _appVersion;
  bool _hasPromptedForUpdate = false;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _initializePushNotifications();
    _selectedVehicleNumber = widget.user.vehicleNumber;
    final vehicles = widget.user.availableVehicles;
    if (vehicles.isNotEmpty) {
      DriverVehicle initialVehicle;
      if (_selectedVehicleNumber != null &&
          _selectedVehicleNumber!.isNotEmpty) {
        initialVehicle = vehicles.firstWhere(
          (vehicle) => vehicle.vehicleNumber == _selectedVehicleNumber,
          orElse: () => vehicles.first,
        );
      } else {
        initialVehicle = vehicles.first;
      }
      _selectedVehicleId = initialVehicle.id;
      _selectedVehicleNumber = initialVehicle.vehicleNumber;
    } else {
      _selectedVehicleId = null;
      if (_selectedVehicleNumber != null && _selectedVehicleNumber!.isEmpty) {
        _selectedVehicleNumber = null;
      }
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _loadActiveShift();
    _loadNotifications();
    _loadAppVersion();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForAppUpdate();
    });

    _gpsPingService =
        GpsPingService(user: widget.user, repository: _gpsPingRepository)
          ..start(
            showToast: (message, {bool isError = false}) {
              if (mounted) {
                showAppToast(context, message, isError: isError);
              }
            },
          );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _glowController.dispose();
    _gpsPingService?.stop();
    _pushNotificationSubscription?.cancel();
    _pushNotificationListSubscription?.cancel();
    super.dispose();
  }

  void _initializePushNotifications() {
    final notificationService = NotificationService();
    final recent = notificationService.recentInAppNotifications;
    if (recent.isNotEmpty) {
      _pushNotifications
        ..clear()
        ..addAll(recent.map(_mapPushNotification));
    }

    _pushNotificationSubscription = notificationService.inAppNotifications
        .listen((notification) {
          if (!mounted) return;
          setState(() {
            _pushNotifications.insert(0, _mapPushNotification(notification));
            _systemNotifications = _systemNotifications
                .where((item) => !item.isPlaceholder)
                .toList(growable: false);
          });
        });
    _pushNotificationListSubscription = notificationService
        .inAppNotificationList
        .listen((notifications) {
          if (!mounted) return;
          setState(() {
            _pushNotifications
              ..clear()
              ..addAll(notifications.map(_mapPushNotification));
            _systemNotifications = _systemNotifications
                .where((item) => !item.isPlaceholder)
                .toList(growable: false);
          });
        });
  }

  _NotificationItem _mapPushNotification(InAppNotificationData notification) {
    final fallbackMessage = notification.body.isNotEmpty
        ? notification.body
        : (notification.data['body']?.toString() ??
              notification.data['message']?.toString() ??
              'Notification received.');
    return _NotificationItem(
      title: notification.title,
      message: fallbackMessage,
      type: NotificationType.alert,
      timestamp: notification.receivedAt,
      metadata: notification.data,
      isPush: true,
    );
  }

  Future<void> _showNotificationDetails(_NotificationItem item) {
    if (item.isPlaceholder) {
      return Future.value();
    }

    final detailMessage = _resolveNotificationMessage(item);
    return showNotificationDetailDialog(
      context,
      title: item.title,
      message: detailMessage,
      timestamp: item.timestamp,
    );
  }

  String _resolveNotificationMessage(_NotificationItem item) {
    if (item.message.trim().isNotEmpty) {
      return item.message;
    }
    final metadata = item.metadata;
    if (metadata == null || metadata.isEmpty) {
      return 'Notification received.';
    }
    return metadata['body']?.toString() ??
        metadata['message']?.toString() ??
        metadata.values.map((value) => value?.toString() ?? '').join('\n');
  }

  String? _formatNotificationTime(DateTime? timestamp) {
    if (timestamp == null) return null;
    return DateFormat('hh:mm a').format(timestamp);
  }

  void _handleVehicleUpdated(DriverVehicle vehicle) {
    setState(() {
      _selectedVehicleId = vehicle.id;
      _selectedVehicleNumber = vehicle.vehicleNumber;
    });
  }

  Future<void> _openMeterReadingSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => MeterReadingSheet(user: widget.user),
    );
  }

  Future<void> _checkForAppUpdate() async {
    if (_hasPromptedForUpdate) {
      return;
    }

    final status = await _appUpdateService.checkForUpdate();
    if (!mounted || !status.isUpdateAvailable) {
      return;
    }

    _hasPromptedForUpdate = true;
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: false,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => UpdateAvailableSheet(
        packageName: AppUpdateService.androidPackageName,
        availableVersionCode: status.availableVersionCode,
        onDismissed: () {},
      ),
    );
  }

  Future<void> _openVehiclePicker() async {
    final vehicles = widget.user.availableVehicles;
    if (vehicles.isEmpty) {
      showAppToast(
        context,
        'No vehicles mapped yet. Contact supervisor.',
        isError: true,
      );
      return;
    }

    final selected = await showModalBottomSheet<DriverVehicle>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Select Vehicle',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ...vehicles.map(
                (vehicle) => ListTile(
                  leading: const Icon(Icons.fire_truck),
                  title: Text(vehicle.vehicleNumber),
                  trailing: vehicle.id == _selectedVehicleId
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(context).pop(vehicle),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );

    if (selected == null) {
      return;
    }

    await _assignVehicle(selected);
  }

  Future<void> _assignVehicle(DriverVehicle vehicle) async {
    final driverId = widget.user.driverId;
    final plantId =
        widget.user.assignmentPlantId ??
        widget.user.plantId ??
        widget.user.defaultPlantId;

    if (driverId == null || driverId.isEmpty) {
      showAppToast(
        context,
        'Driver mapping missing. Contact admin.',
        isError: true,
      );
      return;
    }
    if (plantId == null || plantId.isEmpty) {
      showAppToast(
        context,
        'Plant mapping missing. Contact admin.',
        isError: true,
      );
      return;
    }

    setState(() => _isChangingVehicle = true);
    try {
      await _assignmentRepository.assignVehicle(
        driverId: driverId,
        vehicleId: vehicle.id,
        plantId: plantId,
        userId: widget.user.id,
      );
      if (!mounted) return;

      setState(() {
        _selectedVehicleId = vehicle.id;
        _selectedVehicleNumber = vehicle.vehicleNumber;
        _isChangingVehicle = false;
      });
      _handleVehicleUpdated(vehicle);
      showAppToast(context, 'Vehicle updated successfully.');
    } on AssignmentFailure catch (error) {
      if (!mounted) return;
      setState(() => _isChangingVehicle = false);
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isChangingVehicle = false);
      showAppToast(context, 'Unable to update vehicle.', isError: true);
    }
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _systemNotifications = const [
        _NotificationItem(message: 'Loading...', type: NotificationType.info),
      ];
    });

    final driverId = widget.user.driverId;
    if (driverId == null || driverId.isEmpty) {
      setState(() {
        _systemNotifications = const [
          _NotificationItem(
            message: 'Notifications are unavailable for this profile.',
            type: NotificationType.info,
            isPlaceholder: true,
          ),
        ];
      });
      return;
    }

    try {
      final pending = await _financeRepository.fetchAdvanceRequests(
        driverId,
        status: 'Pending',
      );
      final items = <_NotificationItem>[];

      if (pending.isNotEmpty) {
        final latest = pending.first;
        items.add(
          _NotificationItem(
            message: 'Advance requested ₹${latest.amount.toStringAsFixed(0)}',
            type: NotificationType.warning,
          ),
        );
      }

      final now = DateTime.now();
      final latestShift = _latestShift;
      final inTime = _parseDate(latestShift?.inTime);
      final outTime = _parseDate(latestShift?.outTime);
      final hasTodayCheckIn = inTime != null && _isSameDay(inTime, now);
      final hasCheckedOut = outTime != null && _isSameDay(outTime, now);

      if (now.hour >= 11 && !hasTodayCheckIn) {
        items.add(
          const _NotificationItem(
            message: 'No check-in yet. Please mark today’s attendance.',
            type: NotificationType.warning,
          ),
        );
      }

      if (now.hour >= 21 && hasTodayCheckIn && !hasCheckedOut) {
        final checkInLabel = inTime != null
            ? DateFormat('hh:mm a').format(inTime)
            : 'earlier';
        items.add(
          _NotificationItem(
            message:
                'Still checked in since $checkInLabel. Don’t forget to check out.',
            type: NotificationType.warning,
          ),
        );
      }

      final monthsToCheck = <DateTime>[DateTime(now.year, now.month)];
      if (now.day <= 2) {
        monthsToCheck.add(DateTime(now.year, now.month - 1));
      }

      final overdueRecords = <AttendanceRecord>[];
      final seenIds = <String>{};
      for (final month in monthsToCheck) {
        try {
          final records = await _attendanceRepository.fetchHistory(
            driverId: driverId,
            month: month,
            limit: 60,
          );
          for (final record in records) {
            if (record.status != 'Pending') continue;
            final recordDate = _parseDate(record.inTime);
            if (recordDate == null) continue;
            if (now.difference(recordDate).inDays >= 2) {
              if (seenIds.add(record.attendanceId)) {
                overdueRecords.add(record);
              }
            }
          }
        } catch (_) {
          continue;
        }
      }

      if (overdueRecords.isNotEmpty) {
        overdueRecords.sort((a, b) {
          final aDate = _parseDate(a.inTime) ?? DateTime.now();
          final bDate = _parseDate(b.inTime) ?? DateTime.now();
          return aDate.compareTo(bDate);
        });
        final oldest = _parseDate(overdueRecords.first.inTime);
        if (oldest != null) {
          items.add(
            _NotificationItem(
              message:
                  'Attendance pending approval since ${DateFormat('dd MMM').format(oldest)}.',
              type: NotificationType.info,
            ),
          );
        }
      }

      if (items.isEmpty && _pushNotifications.isEmpty) {
        items.add(
          const _NotificationItem(
            message: 'No new notifications',
            type: NotificationType.info,
            isPlaceholder: true,
          ),
        );
      }

      if (mounted) {
        setState(() => _systemNotifications = items);
      }
    } catch (_) {
      if (!mounted) return;
      if (_systemNotifications.isEmpty) {
        setState(
          () => _systemNotifications = const [
            _NotificationItem(
              message: 'Unable to load notifications',
              type: NotificationType.info,
            ),
          ],
        );
      }
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = '${info.version}+${info.buildNumber}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _appVersion = 'Unavailable';
      });
    }
  }

  Future<void> _handlePhotoSelected(File file) async {
    setState(() => _isUploadingPhoto = true);
    try {
      String url;
      final driverId = widget.user.driverId;

      if (driverId != null && driverId.isNotEmpty) {
        // Driver with driverId - use driver-specific upload
        url = await _profileRepository.uploadProfilePhoto(
          driverId: driverId,
          file: file,
        );
      } else {
        // Supervisor or user without driverId - use user-specific upload
        url = await _profileRepository.uploadUserProfilePhoto(
          userId: widget.user.id,
          file: file,
        );
      }

      if (!mounted) return;

      setState(() {
        widget.user.profilePhoto = url;
      });
      showAppToast(context, 'Profile photo updated.');
    } on ProfileFailure catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to upload profile photo.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  Future<void> _loadActiveShift() async {
    final driverId = widget.user.driverId;
    if (driverId == null || driverId.isEmpty) {
      setState(() {
        _isLoadingShift = false;
        _latestShift = null;
        _shiftSummary = null;
      });
      return;
    }

    setState(() => _isLoadingShift = true);
    try {
      final today = DateTime.now();
      final record = await _attendanceRepository.fetchLatestRecord(
        driverId: driverId,
        month: DateTime(today.year, today.month),
      );
      if (!mounted) return;

      final now = DateTime.now();
      bool attendanceLocked = false;
      String? summary;
      if (record != null) {
        final inTime = _parseDate(record.inTime);
        final outTime = _parseDate(record.outTime);
        if (inTime != null &&
            (record.outTime == null || record.outTime!.isEmpty)) {
          summary =
              'Checked in at ${DateFormat('dd MMM • HH:mm').format(inTime)}';
        } else if (outTime != null) {
          summary =
              'Last check-out ${DateFormat('dd MMM • HH:mm').format(outTime)}';
        }
        if (inTime != null && _isSameDay(inTime, now)) {
          attendanceLocked = outTime != null;
        }
      }

      setState(() {
        _latestShift = record;
        _isLoadingShift = false;
        _shiftSummary = summary;
        _isAttendanceLockedToday = attendanceLocked;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingShift = false;
        _latestShift = null;
        _shiftSummary = null;
        _isAttendanceLockedToday = false;
      });
    }
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool get _hasOpenShift {
    final record = _latestShift;
    if (record == null) {
      return false;
    }
    final inTime = _parseDate(record.inTime);
    if (inTime == null || !_isSameDay(inTime, DateTime.now())) {
      return false;
    }
    final outTimeRaw = record.outTime;
    return outTimeRaw == null || outTimeRaw.isEmpty;
  }

  String get _attendanceButtonLabel {
    if (_isLoadingShift) {
      return 'Mark Attendance';
    }
    if (_hasOpenShift) {
      return 'Check-out Pending';
    }
    if (_isAttendanceLockedToday) {
      return 'Attendance Completed';
    }
    return 'Mark Attendance';
  }

  void _openScreen(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)).then((
      _,
    ) {
      _loadActiveShift();
      _loadNotifications();
    });
  }

  String? _tenureText() {
    final joiningDate = widget.user.joiningDate;
    if (joiningDate == null) {
      return null;
    }
    final now = DateTime.now();
    var years = now.year - joiningDate.year;
    var months = now.month - joiningDate.month;
    if (now.day < joiningDate.day) {
      months -= 1;
    }
    if (months < 0) {
      years -= 1;
      months += 12;
    }
    if (years < 0) {
      years = 0;
      months = 0;
    }
    final parts = <String>[];
    if (years > 0) {
      parts.add('${years}Y');
    }
    if (months > 0) {
      parts.add('${months}M');
    }
    if (parts.isEmpty) {
      parts.add('<1M');
    }
    return parts.join(' & ');
  }

  @override
  Widget build(BuildContext context) {
    final dateFormatter = DateFormat('dd-MM-yyyy');
    final timeFormatter = DateFormat('HH:mm:ss');

    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isHelper = (widget.user.driverRole?.toLowerCase().trim() == 'helper');
    final plantLabel =
        (widget.user.plantName != null && widget.user.plantName!.isNotEmpty)
        ? widget.user.plantName!
        : (widget.user.plantId ?? 'Not mapped');
    final supervisorName = widget.user.supervisorName;
    final plantDisplay = plantLabel;
    final selectedVehicleNumber = _selectedVehicleNumber ?? 'Not assigned';
    final vehicleDisplay = selectedVehicleNumber;
    final tenureText = _tenureText();
    final tenureSubtitle = tenureText != null
        ? 'Working for $tenureText'
        : null;
    final notifications = [..._pushNotifications, ..._systemNotifications];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isHelper ? 'Helper Dashboard' : 'Driver Dashboard',
          style: textTheme.titleLarge?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Meter reading',
            onPressed: _openMeterReadingSheet,
            icon: const Icon(Icons.speed),
          ),
          IconButton(
            onPressed: () {
              widget.onLogout();
              showAppToast(context, 'You have been logged out');
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(
                  gradient: AppGradientBackground.primaryLinearGradient,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ProfilePhotoWithUpload(
                      user: widget.user,
                      radius: 28,
                      onPhotoSelected: _handlePhotoSelected,
                      isUploading: _isUploadingPhoto,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.user.displayName,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Profile'),
                onTap: () {
                  Navigator.of(context).pop();
                  _openScreen(DriverProfileScreen(user: widget.user));
                },
              ),
              ListTile(
                leading: const Icon(Icons.notifications),
                title: const Text('Notification Settings'),
                onTap: () {
                  Navigator.of(context).pop();
                  _openScreen(const NotificationSettingsScreen());
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onLogout();
                  showAppToast(context, 'You have been logged out');
                },
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Version ${_appVersion ?? '...'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.blue[600],
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
      body: AppGradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                // First line: Profile photo + Welcome, Name
                Row(
                  children: [
                    ProfilePhotoWithUpload(
                      user: widget.user,
                      radius: 24,
                      onPhotoSelected: _handlePhotoSelected,
                      isUploading: _isUploadingPhoto,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Welcome, ${widget.user.displayName}',
                        style: textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Second line: Working for X years + Date & Time
                Row(
                  children: [
                    if (tenureSubtitle != null) ...[
                      Chip(
                        label: Text(tenureSubtitle),
                        labelStyle: textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.12),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Row(
                        children: [
                          Chip(
                            label: Text(
                              dateFormatter.format(_now),
                              style: textTheme.labelSmall?.copyWith(
                                fontSize: 11,
                              ),
                            ),
                            avatar: const Icon(Icons.calendar_today, size: 14),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 8),
                          Chip(
                            label: Text(
                              timeFormatter.format(_now),
                              style: textTheme.labelSmall?.copyWith(
                                fontSize: 11,
                              ),
                            ),
                            avatar: const Icon(Icons.access_time, size: 14),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GlowingAttendanceButton(
                  animation: _glowAnimation,
                  onTap: () {
                    if (_isAttendanceLockedToday && !_hasOpenShift) {
                      showAppToast(
                        context,
                        'Attendance already marked for today.',
                        isError: false,
                      );
                      return;
                    }
                    _openScreen(
                      CheckInOutScreen(
                        user: widget.user,
                        availableVehicles: widget.user.availableVehicles,
                        selectedVehicleId: _selectedVehicleId,
                        onVehicleAssigned: _handleVehicleUpdated,
                      ),
                    );
                  },
                  label: _attendanceButtonLabel,
                  gradient: _hasOpenShift
                      ? const LinearGradient(
                          colors: [Color(0xFFE0BC00), Color(0xFFFFE082)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : _isAttendanceLockedToday
                      ? const LinearGradient(
                          colors: [Color(0xFFB0BEC5), Color(0xFFECEFF1)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  icon: _hasOpenShift
                      ? Icons.access_time
                      : _isAttendanceLockedToday
                      ? Icons.verified
                      : Icons.check_circle,
                  iconColor: _hasOpenShift
                      ? const Color(0xFF3B2F00)
                      : _isAttendanceLockedToday
                      ? const Color(0xFF37474F)
                      : Colors.white,
                  textColor: _hasOpenShift
                      ? const Color(0xFF3B2F00)
                      : _isAttendanceLockedToday
                      ? const Color(0xFF37474F)
                      : const Color(0xFF003300),
                ),
                if (_shiftSummary != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _shiftSummary!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Quick Links',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      HoverListTile(
                        leading: const Icon(Icons.history),
                        title: const Text('Attendance History'),
                        onTap: () => _openScreen(
                          AttendanceHistoryScreen(user: widget.user),
                        ),
                      ),
                      const Divider(height: 0),
                      HoverListTile(
                        leading: const Icon(Icons.bar_chart),
                        title: const Text('Monthly Statistics'),
                        onTap: () => _openScreen(
                          MonthlyStatisticsScreen(user: widget.user),
                        ),
                      ),
                      const Divider(height: 0),
                      HoverListTile(
                        leading: const Icon(Icons.payments),
                        title: const Text('Salary / Advance'),
                        onTap: () =>
                            _openScreen(SalaryAdvanceScreen(user: widget.user)),
                      ),
                      const Divider(height: 0),
                      HoverListTile(
                        leading: const Icon(Icons.account_balance_wallet),
                        title: const Text('Khata Book'),
                        onTap: () =>
                            _openScreen(AdvanceSalaryScreen(user: widget.user)),
                      ),
                      const Divider(height: 0),
                      HoverListTile(
                        leading: const Icon(Icons.edit_calendar),
                        title: const Text('Request Past Attendance'),
                        onTap: () => _openScreen(
                          AttendanceAdjustRequestScreen(user: widget.user),
                        ),
                      ),
                      if (!isHelper) ...[
                        const Divider(height: 0),
                        HoverListTile(
                          leading: const Icon(Icons.local_shipping),
                          title: const Text('Trips'),
                          onTap: () =>
                              _openScreen(TripScreen(user: widget.user)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Notifications',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...notifications.map((item) {
                  final hasTitle =
                      item.title != null && item.title!.trim().isNotEmpty;
                  final timeLabel = _formatNotificationTime(item.timestamp);
                  return Card(
                    child: ListTile(
                      leading: Icon(item.type.icon, color: item.type.color),
                      title: Text(hasTitle ? item.title!.trim() : item.message),
                      subtitle: hasTitle ? Text(item.message) : null,
                      trailing: timeLabel != null
                          ? Text(
                              timeLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            )
                          : null,
                      onTap: item.isPlaceholder
                          ? null
                          : () => _showNotificationDetails(item),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                Text(
                  'Plant & Vehicle',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _InfoCard(
                        icon: Icons.factory_outlined,
                        label: 'Plant',
                        value: plantDisplay,
                        helperText:
                            supervisorName != null && supervisorName.isNotEmpty
                            ? 'Supervisor: $supervisorName'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _InfoCard(
                        icon: Icons.fire_truck,
                        label: 'Vehicle',
                        value: vehicleDisplay,
                        helperText: null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _isChangingVehicle ? null : _openVehiclePicker,
                    icon: _isChangingVehicle
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.swap_horiz),
                    label: Text(
                      _isChangingVehicle ? 'Updating...' : 'Change Vehicle',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum NotificationType { success, info, warning, alert }

class _NotificationItem {
  const _NotificationItem({
    required this.message,
    required this.type,
    this.title,
    this.timestamp,
    this.metadata,
    this.isPush = false,
    this.isPlaceholder = false,
  });

  final String? title;
  final String message;
  final DateTime? timestamp;
  final Map<String, dynamic>? metadata;
  final NotificationType type;
  final bool isPush;
  final bool isPlaceholder;
}

extension on NotificationType {
  Color get color {
    switch (this) {
      case NotificationType.success:
        return Colors.green;
      case NotificationType.info:
        return Colors.blueGrey;
      case NotificationType.warning:
        return Colors.orange;
      case NotificationType.alert:
        return Colors.redAccent;
    }
  }

  IconData get icon {
    switch (this) {
      case NotificationType.success:
        return Icons.check_circle;
      case NotificationType.info:
        return Icons.info;
      case NotificationType.warning:
        return Icons.warning;
      case NotificationType.alert:
        return Icons.notification_important;
    }
  }
}

class GlowingAttendanceButton extends StatelessWidget {
  const GlowingAttendanceButton({
    required this.animation,
    required this.onTap,
    this.label = 'Mark Attendance',
    this.gradient,
    this.icon = Icons.check_circle,
    this.iconColor,
    this.textColor,
  });

  final Animation<double> animation;
  final VoidCallback onTap;
  final String label;
  final Gradient? gradient;
  final IconData icon;
  final Color? iconColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final glow = animation.value;
        final gradientValue =
            gradient ??
            const LinearGradient(
              colors: [Color(0xFF00C853), Color(0xFF64DD17)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            );
        final baseColor = gradientValue.colors.first;
        return GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              gradient: gradientValue,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: baseColor.withOpacity(0.35 + glow * 0.25),
                  blurRadius: 22 + glow * 14,
                  spreadRadius: 2 + glow * 3,
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: iconColor ?? Colors.white, size: 26),
                const SizedBox(width: 12),
                Transform.scale(
                  scale: 0.94 + glow * 0.12,
                  child: Text(
                    label,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: textColor ?? const Color(0xFF003300),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class HoverListTile extends StatefulWidget {
  const HoverListTile({
    required this.leading,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final VoidCallback onTap;

  @override
  State<HoverListTile> createState() => _HoverListTileState();
}

class _HoverListTileState extends State<HoverListTile> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = Colors.blue.shade50;
    final hoverColor = Colors.blue.shade100;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        color: _isHovering ? hoverColor : Colors.transparent,
        child: ListTile(
          leading: widget.leading,
          title: widget.title,
          subtitle: widget.subtitle,
          onTap: widget.onTap,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    this.helperText,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(10),
              child: Icon(icon, color: theme.colorScheme.primary, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (helperText != null) ...[
              const SizedBox(height: 6),
              Text(
                helperText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.65),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
