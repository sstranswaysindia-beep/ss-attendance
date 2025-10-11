import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/models/advance_request.dart';
import '../../core/models/attendance_record.dart';
import '../../core/services/approvals_repository.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/services/gps_ping_repository.dart';
import '../../core/services/gps_ping_service.dart';
import '../../core/services/finance_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/profile_photo_widget.dart';
import '../approvals/approvals_screen.dart';
import '../attendance/attendance_adjust_request_screen.dart';
import '../attendance/attendance_history_screen.dart';
import '../attendance/check_in_out_screen.dart';
import '../finance/salary_advance_screen.dart';
import '../profile/driver_profile_screen.dart';
import '../settings/notification_settings_screen.dart';
import '../statistics/monthly_statistics_screen.dart';
import '../trips/trip_screen.dart';
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
  GpsPingService? _gpsPingService;

  late DateTime _now;
  Timer? _ticker;
  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;

  List<_SupervisorNotification> _notifications = const [
    _SupervisorNotification(message: 'Loading...', type: NotificationType.info),
  ];
  AttendanceRecord? _latestShift;
  bool _isLoadingShift = true;
  String? _shiftSummary;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
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
    super.dispose();
  }

  Future<void> _loadNotifications() async {
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
      if (items.isEmpty) {
        items.add(
          const _SupervisorNotification(
            message: 'No pending driver notifications.',
            type: NotificationType.info,
          ),
        );
      }
      if (mounted) {
        setState(() => _notifications = items);
      }
    } catch (_) {
      if (mounted && _notifications.isEmpty) {
        setState(
          () => _notifications = const [
            _SupervisorNotification(
              message: 'Unable to fetch latest notifications.',
              type: NotificationType.info,
            ),
          ],
        );
      }
    }
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

      setState(() {
        _latestShift = record;
        _isLoadingShift = false;
        if (record != null) {
          final inTime = _parseDate(record.inTime);
          final outTime = _parseDate(record.outTime);
          if (inTime != null &&
              (record.outTime == null || record.outTime!.isEmpty)) {
            _shiftSummary =
                'Checked in at ${DateFormat('dd MMM • HH:mm').format(inTime)}';
          } else if (outTime != null) {
            _shiftSummary =
                'Last check-out ${DateFormat('dd MMM • HH:mm').format(outTime)}';
          } else {
            _shiftSummary = null;
          }
        } else {
          _shiftSummary = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingShift = false;
        _latestShift = null;
        _shiftSummary = null;
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

  String get _attendanceButtonLabel =>
      _hasOpenShift ? 'Check-out Pending' : 'Mark Attendance';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final dateFormatter = DateFormat('dd-MM-yyyy');
    final timeFormatter = DateFormat('HH:mm:ss');
    final user = widget.user;

    final plantLabel = user.assignmentPlantName?.isNotEmpty == true
        ? user.assignmentPlantName!
        : (user.plantName?.isNotEmpty == true
              ? user.plantName!
              : (user.plantId?.isNotEmpty == true
                    ? user.plantId!
                    : 'Not mapped'));

    final vehicleLabel = user.assignmentVehicleNumber?.isNotEmpty == true
        ? user.assignmentVehicleNumber!
        : (user.vehicleNumber?.isNotEmpty == true
              ? user.vehicleNumber!
              : 'Not assigned');

    final tenureText = _tenureText();
    final tenureSubtitle = tenureText != null
        ? 'Working for $tenureText'
        : null;
    final supervisorName = user.supervisorName;
    final helperSupervisorText =
        supervisorName != null && supervisorName.isNotEmpty
        ? 'Supervisor: $supervisorName'
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Supervisor Dashboard'),
        actions: [
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
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DriverProfileScreen(user: user),
                    ),
                  );
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
                  'Version 1.0.2',
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
                  onTap: () => Navigator.of(context)
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
                      }),
                  label: _attendanceButtonLabel,
                  gradient: _hasOpenShift
                      ? const LinearGradient(
                          colors: [Color(0xFFE0BC00), Color(0xFFFFE082)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  icon: _hasOpenShift ? Icons.access_time : Icons.check_circle,
                  iconColor: _hasOpenShift
                      ? const Color(0xFF3B2F00)
                      : Colors.white,
                  textColor: _hasOpenShift
                      ? const Color(0xFF3B2F00)
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
                            .then((_) => _loadNotifications()),
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
                            .then((_) => _loadNotifications()),
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
                            .then((_) => _loadNotifications()),
                      ),
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
                            .then((_) => _loadNotifications()),
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
                            .then((_) => _loadNotifications()),
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
                            .then((_) => _loadNotifications()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('Notifications', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                ..._notifications.map(
                  (item) => Card(
                    child: ListTile(
                      leading: Icon(
                        _notificationIcon(item.type),
                        color: _notificationColor(item.type),
                      ),
                      title: Text(item.message),
                    ),
                  ),
                ),
                // Show different sections based on supervisor type
                if (widget.user.driverId != null && widget.user.driverId!.isNotEmpty) ...[
                  // Supervisors with driver_id: Show Plant & Vehicle
                  const SizedBox(height: 16),
                  Text('Plant & Vehicle', style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _SupervisorInfoCard(
                          icon: Icons.factory_outlined,
                          label: 'Plant',
                          value: plantLabel,
                          helperText: helperSupervisorText,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SupervisorInfoCard(
                          icon: Icons.fire_truck,
                          label: 'Vehicle',
                          value: vehicleLabel,
                          helperText: null,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  // Supervisors without driver_id: Show all supervised plants
                  const SizedBox(height: 16),
                  Text('Supervised Plants', style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _SupervisedPlantsCard(user: widget.user),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SupervisorNotification {
  const _SupervisorNotification({required this.message, required this.type});

  final String message;
  final NotificationType type;
}

class _SupervisorInfoCard extends StatelessWidget {
  const _SupervisorInfoCard({
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (helperText != null) ...[
              const SizedBox(height: 4),
              Text(helperText!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _SupervisedPlantsCard extends StatelessWidget {
  const _SupervisedPlantsCard({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (user.supervisedPlants.isEmpty) {
      return Card(
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
                final plantName = plant['plant_name']?.toString() ?? 'Unknown Plant';
                final plantId = plant['id']?.toString() ?? '';
                
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
  }
}
