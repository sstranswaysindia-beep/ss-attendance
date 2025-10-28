import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../calculator/average_calculator_screen.dart';

import '../../core/models/app_user.dart';
import '../../core/models/advance_request.dart';
import '../../core/models/attendance_record.dart';
import '../../core/services/approvals_repository.dart';
import '../../core/services/app_update_service.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/services/gps_ping_repository.dart';
import '../../core/models/supervisor_today_attendance.dart';
import '../../core/services/gps_ping_service.dart';
import '../../core/services/finance_repository.dart';
import '../../core/services/notification_service.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/profile_photo_widget.dart';
import '../../core/models/document_models.dart';
import '../../core/services/documents_repository.dart';
import '../../core/widgets/in_app_notification_banner.dart';
import '../../core/widgets/update_available_sheet.dart';
import '../approvals/approvals_screen.dart';
import '../attendance/attendance_adjust_request_screen.dart';
import '../attendance/attendance_history_screen.dart';
import '../attendance/check_in_out_screen.dart';
import '../finance/salary_advance_screen.dart';
import '../finance/advance_salary_screen.dart';
import '../meter/meter_reading_sheet.dart';
import '../attendance/proxy_attendance_screen.dart';
import '../profile/driver_profile_screen.dart';
import '../profile/supervisor_profile_screen.dart';
import '../settings/notification_settings_screen.dart';
import '../statistics/monthly_statistics_screen.dart';
import '../trips/trip_screen.dart';
import '../documents/documents_hub_screen.dart';
import 'driver_dashboard_screen.dart'
    show GlowingAttendanceButton, HoverListTile, NotificationType;

class SupervisorDashboardScreen extends StatefulWidget {
  const SupervisorDashboardScreen({
    required this.user,
    required this.onLogout,
    super.key,
  });

  final AppUser user;
  final VoidCallback onLogout;

  @override
  State<SupervisorDashboardScreen> createState() =>
      _SupervisorDashboardScreenState();
}

class _SupervisorDashboardScreenState extends State<SupervisorDashboardScreen>
    with SingleTickerProviderStateMixin {
  final FinanceRepository _financeRepository = FinanceRepository();
  final ApprovalsRepository _approvalsRepository = ApprovalsRepository();
  final AttendanceRepository _attendanceRepository = AttendanceRepository();
  final GpsPingRepository _gpsPingRepository = GpsPingRepository();
  final DocumentsRepository _documentsRepository = DocumentsRepository();
  final AppUpdateService _appUpdateService = AppUpdateService();
  GpsPingService? _gpsPingService;

  late DateTime _now;
  Timer? _ticker;
  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;

  List<_SupervisorNotification> _systemNotifications = const [
    _SupervisorNotification(message: 'Loading...', type: NotificationType.info),
  ];
  final List<_SupervisorNotification> _pushNotifications = [];
  StreamSubscription<InAppNotificationData>? _pushNotificationSubscription;
  StreamSubscription<List<InAppNotificationData>>?
  _pushNotificationListSubscription;
  AttendanceRecord? _latestShift;
  bool _isLoadingShift = true;
  String? _shiftSummary;
  bool _isAttendanceLockedToday = false;
  String? _appVersion;
  DocumentOverviewData? _documentsOverview;
  bool _isLoadingDocumentsOverview = false;
  String? _documentsOverviewError;
  bool _hasPromptedForUpdate = false;

  bool _isLoadingTodayAttendance = false;
  String? _todayAttendanceError;
  List<SupervisorTodayAttendancePlant> _todayAttendance = const [];

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _initializePushNotifications();
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
    _loadSupervisorTodayAttendance();
    _loadAppVersion();
    if (widget.user.canViewDocuments) {
      _loadDocumentsOverview();
    }
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

  _SupervisorNotification _mapPushNotification(
    InAppNotificationData notification,
  ) {
    final fallbackMessage = notification.body.isNotEmpty
        ? notification.body
        : (notification.data['body']?.toString() ??
              notification.data['message']?.toString() ??
              'Notification received.');
    return _SupervisorNotification(
      title: notification.title,
      message: fallbackMessage,
      type: NotificationType.alert,
      timestamp: notification.receivedAt,
      metadata: notification.data,
      isPush: true,
    );
  }

  Future<void> _showNotificationDetails(_SupervisorNotification item) {
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

  String _resolveNotificationMessage(_SupervisorNotification item) {
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

  Future<void> _loadNotifications() async {
    setState(() {
      _systemNotifications = const [
        _SupervisorNotification(
          message: 'Loading...',
          type: NotificationType.info,
        ),
      ];
    });

    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final driverId = widget.user.driverId;
      final pendingAdvancesFuture = (driverId != null && driverId.isNotEmpty)
          ? _financeRepository.fetchAdvanceRequests(driverId, status: 'Pending')
          : Future<List<AdvanceRequest>>.value(const []);
      final pendingApprovalsFuture = _approvalsRepository.fetchApprovals(
        supervisorUserId: widget.user.id,
        status: 'Pending',
        date: today,
        rangeDays: 3,
      );

      final pendingAdvances = await pendingAdvancesFuture;
      final pendingApprovals = await pendingApprovalsFuture;

      final items = <_SupervisorNotification>[];
      if (pendingAdvances.isNotEmpty) {
        items.add(
          _SupervisorNotification(
            message:
                'You have ${pendingAdvances.length} driver advance request(s).',
            type: NotificationType.warning,
          ),
        );
      }
      final driverRequests = pendingApprovals.approvals
          .where(
            (approval) =>
                (approval.source ?? '').toLowerCase() == 'adjust_request',
          )
          .toList(growable: false);
      final otherRequestsCount =
          pendingApprovals.approvals.length - driverRequests.length;

      if (driverRequests.isNotEmpty) {
        items.add(
          _SupervisorNotification(
            message:
                'Driver attendance requests pending approval: ${driverRequests.length}.',
            type: NotificationType.warning,
          ),
        );
      }

      if (otherRequestsCount > 0) {
        items.add(
          _SupervisorNotification(
            message:
                '$otherRequestsCount attendance record(s) need your review.',
            type: NotificationType.warning,
          ),
        );
      }
      if (items.isEmpty && _pushNotifications.isEmpty) {
        items.add(
          const _SupervisorNotification(
            message: 'No pending driver notifications.',
            type: NotificationType.info,
            isPlaceholder: true,
          ),
        );
      }
      if (mounted) {
        setState(() => _systemNotifications = items);
      }
    } catch (_) {
      if (mounted && _systemNotifications.isEmpty) {
        setState(
          () => _systemNotifications = const [
            _SupervisorNotification(
              message: 'Unable to fetch latest notifications.',
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

  Future<void> _openProxyAttendanceScreen() async {
    if (!widget.user.proxyEnabled) {
      showAppToast(
        context,
        'Proxy attendance is not enabled for your account.',
        isError: true,
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProxyAttendanceScreen(user: widget.user),
      ),
    );

    if (!mounted) {
      return;
    }

    await Future.wait<void>([
      _loadSupervisorTodayAttendance(silent: true),
      _loadActiveShift(),
    ]);
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

  Future<void> _loadSupervisorTodayAttendance({bool silent = false}) async {
    setState(() {
      _isLoadingTodayAttendance = true;
      if (!silent) {
        _todayAttendanceError = null;
      }
    });
    try {
      final response = await _attendanceRepository
          .fetchSupervisorTodayAttendance(
            supervisorUserId: widget.user.id.toString(),
          );
      if (!mounted) return;
      setState(() {
        _todayAttendance = response;
        _todayAttendanceError = null;
      });
    } on AttendanceFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _todayAttendanceError = error.message;
      });
      if (!silent) {
        showAppToast(context, error.message, isError: true);
      }
    } catch (_) {
      if (!mounted) return;
      const fallback = "Unable to load today's attendance.";
      setState(() {
        _todayAttendanceError = fallback;
      });
      if (!silent) {
        showAppToast(context, fallback, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTodayAttendance = false;
        });
      }
    }
  }

  Future<void> _loadDocumentsOverview({bool silent = false}) async {
    if (!widget.user.canViewDocuments) {
      return;
    }
    setState(() {
      _isLoadingDocumentsOverview = true;
      if (!silent) {
        _documentsOverviewError = null;
      }
    });
    try {
      final overview = await _documentsRepository.fetchOverview(
        userId: widget.user.id,
      );
      if (!mounted) return;
      setState(() {
        _documentsOverview = overview;
        _documentsOverviewError = null;
      });
    } on DocumentFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _documentsOverviewError = error.message;
      });
      if (!silent) {
        showAppToast(context, error.message, isError: true);
      }
    } catch (_) {
      if (!mounted) return;
      const fallback = 'Unable to load documents summary.';
      setState(() {
        _documentsOverviewError = fallback;
      });
      if (!silent) {
        showAppToast(context, fallback, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDocumentsOverview = false;
        });
      }
    }
  }

  Future<void> _openDocumentsHub() async {
    if (!widget.user.canViewDocuments) {
      return;
    }
    final result = await Navigator.of(context).push<DocumentOverviewData>(
      MaterialPageRoute(
        builder: (_) => DocumentsHubScreen(
          user: widget.user,
          initialData: _documentsOverview,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _documentsOverview = result;
        _documentsOverviewError = null;
      });
    }
    _loadDocumentsOverview(silent: true);
  }

  String get _documentsTileSubtitle {
    if (_isLoadingDocumentsOverview && _documentsOverview == null) {
      return 'Loading summary…';
    }
    if (_documentsOverview != null) {
      final counts = _documentsOverview!.totalCounts;
      final base =
          'Due Soon: ${_twoDigits(counts.dueSoon)}   Expired: ${_twoDigits(counts.expired)}';
      if (_documentsOverviewError != null) {
        return '$base • Refresh needed';
      }
      return base;
    }
    if (_documentsOverviewError != null) {
      return 'Tap to refresh • ${_documentsOverviewError!}';
    }
    return 'Tap to open documents hub';
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  void _openAverageCalculator() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const AverageCalculatorScreen()),
    );
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

  Future<void> _loadActiveShift() async {
    final driverId = widget.user.driverId;
    if (driverId == null || driverId.isEmpty) {
      setState(() {
        _isLoadingShift = false;
        _latestShift = null;
        _shiftSummary = null;
        _isAttendanceLockedToday = false;
      });
      return;
    }

    setState(() => _isLoadingShift = true);
    try {
      final now = DateTime.now();
      final record = await _attendanceRepository.fetchLatestRecord(
        driverId: driverId,
        month: DateTime(now.year, now.month),
      );
      if (!mounted) return;

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
    if (raw == null || raw.isEmpty) return null;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final dateFormatter = DateFormat('dd-MM-yyyy');
    final timeFormatter = DateFormat('HH:mm:ss');
    final user = widget.user;

    final tenureText = _tenureText();
    final tenureSubtitle = tenureText != null
        ? 'Working for $tenureText'
        : null;
    final notifications = [..._pushNotifications, ..._systemNotifications];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Supervisor Dashboard'),
        actions: [
          if (user.proxyEnabled)
            IconButton(
              tooltip: 'Proxy attendance',
              onPressed: _openProxyAttendanceScreen,
              icon: const Icon(Icons.switch_account),
            ),
          IconButton(
            tooltip: 'Meter reading',
            onPressed: _openMeterReadingSheet,
            icon: const Icon(Icons.speed),
          ),
          IconButton(
            onPressed: () {
              widget.onLogout();
              showAppToast(context, 'Logged out successfully');
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
                    ProfilePhotoWidget(user: user, radius: 28),
                    const SizedBox(height: 12),
                    Text(
                      user.displayName,
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
                  // Use different profile screen based on whether supervisor has driver_id
                  final profileScreen =
                      user.driverId != null && user.driverId!.isNotEmpty
                      ? DriverProfileScreen(user: user)
                      : SupervisorProfileScreen(user: user);

                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => profileScreen));
                },
              ),
              ListTile(
                leading: const Icon(Icons.notifications),
                title: const Text('Notification Settings'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NotificationSettingsScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onLogout();
                  showAppToast(context, 'Logged out successfully');
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
                    ProfilePhotoWidget(user: widget.user, radius: 24),
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
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) => CheckInOutScreen(
                              user: widget.user,
                              availableVehicles: widget.user.availableVehicles,
                            ),
                          ),
                        )
                        .then((_) {
                          _loadActiveShift();
                          _loadNotifications();
                          _loadSupervisorTodayAttendance(silent: true);
                        });
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
                  Text(_shiftSummary!, style: textTheme.bodySmall),
                ],
                const SizedBox(height: 16),
                Text('Quick Links', style: textTheme.titleMedium),
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
                        leading: const Icon(Icons.verified_user),
                        title: const Text('Approvals'),
                        onTap: () => Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ApprovalsScreen(user: widget.user),
                              ),
                            )
                            .then((_) {
                              _loadNotifications();
                              _loadSupervisorTodayAttendance(silent: true);
                            }),
                      ),
                      const Divider(height: 0),
                      HoverListTile(
                        leading: const Icon(Icons.history),
                        title: const Text('Attendance History'),
                        onTap: () => Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    AttendanceHistoryScreen(user: widget.user),
                              ),
                            )
                            .then((_) {
                              _loadNotifications();
                              _loadSupervisorTodayAttendance(silent: true);
                            }),
                      ),
                      const Divider(height: 0),
                      HoverListTile(
                        leading: const Icon(Icons.bar_chart),
                        title: const Text('Monthly Statistics'),
                        onTap: () => Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    MonthlyStatisticsScreen(user: widget.user),
                              ),
                            )
                            .then((_) {
                              _loadNotifications();
                              _loadSupervisorTodayAttendance(silent: true);
                            }),
                      ),
                      if (widget.user.canViewDocuments) ...[
                        const Divider(height: 0),
                        HoverListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: const Text('Documents'),
                          subtitle: Text(
                            _documentsTileSubtitle,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          onTap: () {
                            if (_isLoadingDocumentsOverview &&
                                _documentsOverview == null) {
                              _loadDocumentsOverview();
                              return;
                            }
                            _openDocumentsHub();
                          },
                        ),
                      ],
                      const Divider(height: 0),
                      HoverListTile(
                        leading: const Icon(Icons.payments),
                        title: const Text('Salary & Advances'),
                        onTap: () => Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    SalaryAdvanceScreen(user: widget.user),
                              ),
                            )
                            .then((_) {
                              _loadNotifications();
                              _loadSupervisorTodayAttendance(silent: true);
                            }),
                      ),
                      const Divider(height: 0),
                      HoverListTile(
                        leading: const Icon(Icons.account_balance_wallet),
                        title: const Text('Khata Book'),
                        onTap: () => Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    AdvanceSalaryScreen(user: widget.user),
                              ),
                            )
                            .then((_) {
                              _loadNotifications();
                              _loadSupervisorTodayAttendance(silent: true);
                            }),
                      ),
                      const Divider(height: 0),
                      HoverListTile(
                        leading: const Icon(Icons.edit_calendar),
                        title: const Text('Past Attendance Request'),
                        onTap: () => Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (_) => AttendanceAdjustRequestScreen(
                                  user: widget.user,
                                ),
                              ),
                            )
                            .then((_) {
                              _loadNotifications();
                              _loadSupervisorTodayAttendance(silent: true);
                            }),
                      ),
                      const Divider(height: 0),
                      HoverListTile(
                        leading: const Icon(Icons.local_shipping),
                        title: const Text('Trips'),
                        onTap: () => Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (_) => TripScreen(user: widget.user),
                              ),
                            )
                            .then((_) {
                              _loadNotifications();
                              _loadSupervisorTodayAttendance(silent: true);
                            }),
                      ),
                      // Show Average Calculator for all supervisors
                      const Divider(height: 0),
                      HoverListTile(
                        leading: const Icon(Icons.calculate),
                        title: const Text('Average Calculator'),
                        onTap: () => _openAverageCalculator(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Today Attendance', style: textTheme.titleMedium),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Refresh',
                      icon: const Icon(Icons.refresh),
                      onPressed: _isLoadingTodayAttendance
                          ? null
                          : () => _loadSupervisorTodayAttendance(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildTodayAttendanceSection(theme),
                const SizedBox(height: 16),
                Text('Notifications', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                ...notifications.map((item) {
                  final hasTitle =
                      item.title != null && item.title!.trim().isNotEmpty;
                  final timeLabel = _formatNotificationTime(item.timestamp);
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        _notificationIcon(item.type),
                        color: _notificationColor(item.type),
                      ),
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
                // All supervisors show supervised plants (no vehicles)
                const SizedBox(height: 16),
                Text('Supervised Plants', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                _SupervisedPlantsCard(user: widget.user),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTodayAttendanceSection(ThemeData theme) {
    if (_isLoadingTodayAttendance && _todayAttendance.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_todayAttendanceError != null && _todayAttendance.isEmpty) {
      return Card(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _todayAttendanceError!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _isLoadingTodayAttendance
                    ? null
                    : () => _loadSupervisorTodayAttendance(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final hasDrivers = _todayAttendance.any(
      (plant) => plant.drivers.isNotEmpty,
    );
    final items = <Widget>[];

    if (_todayAttendanceError != null && hasDrivers) {
      items.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _todayAttendanceError!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      );
    }

    if (!hasDrivers) {
      items.add(
        Card(
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No drivers found for your supervised plants today.'),
          ),
        ),
      );
    } else {
      for (final plant in _todayAttendance) {
        items.add(_buildPlantAttendanceCard(theme, plant));
      }
    }

    if (_isLoadingTodayAttendance && _todayAttendance.isNotEmpty) {
      items.insert(
        0,
        const Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items,
    );
  }

  Widget _buildPlantAttendanceCard(
    ThemeData theme,
    SupervisorTodayAttendancePlant plant,
  ) {
    final title = plant.plantName.isEmpty
        ? 'Unassigned Plant'
        : plant.plantName;

    if (plant.drivers.isEmpty) {
      return Card(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.factory_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'No drivers linked to this plant.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.factory_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              children: plant.drivers
                  .map((driver) => _buildDriverAttendanceTile(theme, driver))
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverAttendanceTile(
    ThemeData theme,
    SupervisorTodayAttendanceDriver driver,
  ) {
    final hasCheckIn = driver.hasCheckIn;
    final hasCheckOut = driver.hasCheckOut;
    final hasAny = hasCheckIn || hasCheckOut;
    final isComplete = hasCheckIn && hasCheckOut;
    final isPartial = hasAny && !isComplete;

    final gradientColors = isComplete
        ? const [Color(0xFF00D100), Color(0xFF00AA00)]
        : isPartial
        ? const [Color(0xFFFFCE55), Color(0xFFFFB347)]
        : const [Color(0xFFED1C24), Color(0xFFB3121B)];

    const primaryTextColor = Colors.black87;
    const subtleTextColor = Colors.black54;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _buildDriverAvatar(driver, primaryTextColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  driver.driverName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: primaryTextColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Status: ${hasAny ? 'Done' : 'Not Done'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: primaryTextColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isPartial)
                  Text(
                    'Check-out pending',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: subtleTextColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverAvatar(
    SupervisorTodayAttendanceDriver driver,
    Color textColor,
  ) {
    final badge = driver.roleBadge;
    final photo = driver.profilePhoto?.trim();
    final avatarBackground = Colors.white.withOpacity(0.85);

    Widget baseAvatar;
    if (photo != null && photo.isNotEmpty) {
      baseAvatar = CircleAvatar(
        radius: 26,
        backgroundColor: avatarBackground,
        backgroundImage: NetworkImage(photo),
      );
    } else {
      baseAvatar = CircleAvatar(
        radius: 26,
        backgroundColor: avatarBackground,
        child: Text(
          _driverInitials(driver.driverName),
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        baseAvatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black87.withOpacity(0.8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _driverInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'DR';
    }
    if (parts.length == 1) {
      final word = parts.first;
      if (word.length >= 2) {
        return word.substring(0, 2).toUpperCase();
      }
      return word.substring(0, 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

class _SupervisorNotification {
  const _SupervisorNotification({
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

class _SupervisedPlantsCard extends StatelessWidget {
  const _SupervisedPlantsCard({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (user.supervisedPlants.isEmpty) {
      return Card(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.08)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.factory_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No supervised plants',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Contact admin to assign plants',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

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
            Row(
              children: [
                Icon(Icons.factory_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'Supervised Plants (${user.supervisedPlants.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: user.supervisedPlants.map((plant) {
                final plantName =
                    plant['plant_name']?.toString() ?? 'Unknown Plant';

                return Chip(
                  label: Text(
                    plantName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  backgroundColor: theme.colorScheme.primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _notificationIcon(NotificationType type) {
  switch (type) {
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

Color _notificationColor(NotificationType type) {
  switch (type) {
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
