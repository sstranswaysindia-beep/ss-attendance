import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/models/driver_vehicle.dart';
import '../../core/models/attendance_record.dart';
import '../../core/services/assignment_repository.dart';
import '../../core/services/finance_repository.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/services/gps_ping_repository.dart';
import '../../core/services/gps_ping_service.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/profile_photo_widget.dart';
import '../attendance/attendance_adjust_request_screen.dart';
import '../attendance/attendance_history_screen.dart';
import '../attendance/check_in_out_screen.dart';
import '../finance/salary_advance_screen.dart';
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
  GpsPingService? _gpsPingService;

  AttendanceRecord? _latestShift;
  bool _isLoadingShift = true;
  String? _shiftSummary;

  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;

  List<_NotificationItem> _notifications = const [
    _NotificationItem(message: 'Loading...', type: NotificationType.info),
  ];

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
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
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
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

  void _handleVehicleUpdated(DriverVehicle vehicle) {
    setState(() {
      _selectedVehicleId = vehicle.id;
      _selectedVehicleNumber = vehicle.vehicleNumber;
    });
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
    final driverId = widget.user.driverId;
    if (driverId == null || driverId.isEmpty) {
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

      if (items.isEmpty) {
        items.add(
          const _NotificationItem(
            message: 'No new notifications',
            type: NotificationType.info,
          ),
        );
      }

      if (mounted) {
        setState(() => _notifications = items);
      }
    } catch (_) {
      if (!mounted) return;
      if (_notifications.isEmpty) {
        setState(
          () => _notifications = const [
            _NotificationItem(
              message: 'Unable to load notifications',
              type: NotificationType.info,
            ),
          ],
        );
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
    return _hasOpenShift ? 'Check-out Pending' : 'Mark Attendance';
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
      parts.add('$years year${years == 1 ? '' : 's'}');
    }
    if (months > 0) {
      parts.add('$months month${months == 1 ? '' : 's'}');
    }
    if (parts.isEmpty) {
      parts.add('Less than a month');
    }
    final label = parts.join(' ');
    return label[0].toUpperCase() + label.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final dateFormatter = DateFormat('dd-MM-yyyy');
    final timeFormatter = DateFormat('HH:mm:ss');

    final textTheme = Theme.of(context).textTheme;
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Driver Dashboard',
          style: textTheme.titleLarge?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
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
                    ProfilePhotoWidget(
                      user: widget.user,
                      radius: 28,
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
                    ProfilePhotoWidget(
                      user: widget.user,
                      radius: 24,
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
                            label: Text(dateFormatter.format(_now)),
                            avatar: const Icon(Icons.calendar_today, size: 16),
                          ),
                          const SizedBox(width: 8),
                          Chip(
                            label: Text(timeFormatter.format(_now)),
                            avatar: const Icon(Icons.access_time, size: 16),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GlowingAttendanceButton(
                  animation: _glowAnimation,
                  onTap: () => _openScreen(
                    CheckInOutScreen(
                      user: widget.user,
                      availableVehicles: widget.user.availableVehicles,
                      selectedVehicleId: _selectedVehicleId,
                      onVehicleAssigned: _handleVehicleUpdated,
                    ),
                  ),
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
                  Text(
                    _shiftSummary!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    'https://sstranswaysindia.com/api/mobile/image/IMG_8026.gif',
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Quick Links',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
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
                        leading: const Icon(Icons.edit_calendar),
                        title: const Text('Request Past Attendance'),
                        onTap: () => _openScreen(
                          AttendanceAdjustRequestScreen(user: widget.user),
                        ),
                      ),
                      const Divider(height: 0),
                      HoverListTile(
                        leading: const Icon(Icons.local_shipping),
                        title: const Text('Trips'),
                        onTap: () => _openScreen(TripScreen(user: widget.user)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Notifications',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ..._notifications.map(
                  (item) => Card(
                    child: ListTile(
                      leading: Icon(item.type.icon, color: item.type.color),
                      title: Text(item.message),
                    ),
                  ),
                ),
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

enum NotificationType { success, info, warning }

class _NotificationItem {
  const _NotificationItem({required this.message, required this.type});

  final String message;
  final NotificationType type;
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
