import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:lottie/lottie.dart';

import '../../core/models/app_user.dart';
import '../../core/models/driver_vehicle.dart';
import '../../core/models/attendance_record.dart';
import '../../core/navigation/app_route_observer.dart';
import '../../core/services/assignment_repository.dart';
import '../../core/services/finance_repository.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/services/gps_ping_repository.dart';
import '../../core/services/gps_ping_service.dart';
import '../../core/services/profile_repository.dart';
import '../../core/services/app_update_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/biometric_unlock_service.dart';
import '../../core/services/safety_repository.dart';
import '../../core/services/auth_storage_service.dart';
import '../../core/services/training_flag_service.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/app_loader.dart';
import '../../core/widgets/profile_photo_widget.dart';
import '../../core/widgets/in_app_notification_banner.dart';
import '../../core/widgets/update_available_sheet.dart';
import '../../core/widgets/biometric_enable_sheet.dart';
import '../attendance/attendance_adjust_request_screen.dart';
import '../attendance/attendance_history_screen.dart';
import '../attendance/check_in_out_screen.dart';
import '../finance/salary_advance_screen.dart';
import '../finance/advance_salary_screen.dart';
import '../leave/apply_leave_screen.dart';
import '../documents/personal_documents_sheet.dart';
import '../profile/driver_profile_screen.dart';
import '../settings/notification_settings_screen.dart';
import '../safety/safety_hub_screen.dart';
import '../safety/training/training_screen.dart';
import '../statistics/monthly_statistics_screen.dart';
import '../trips/trip_screen.dart';
import '../trips/trip_sheet_screen.dart';
import '../referral/referral_tracker_screen.dart';
import '../watch_ads/watch_ads_screen.dart';
import 'package:google_fonts/google_fonts.dart';

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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  static const int _driverDocumentWarningDays = 12;
  static const String _driverDocumentsListUrl =
      'https://sstranswaysindia.com/api/mobile/driver_documents_list.php';

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
  final BiometricUnlockService _biometricService = BiometricUnlockService();
  late SafetyRepository _safetyRepository;
  GpsPingService? _gpsPingService;

  AttendanceRecord? _latestShift;
  bool _isLoadingShift = true;
  bool _isUploadingPhoto = false;
  String? _shiftSummary;
  bool _isAttendanceLockedToday = false;
  bool _isCheckingAbsence = false;
  bool _checkingTraining = false;
  bool _biometricEnabled = false;
  bool _biometricSupported = false;
  bool _dashboardBellHiddenByOverlay = false;
  ModalRoute<dynamic>? _observedRoute;

  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;

  List<_NotificationItem> _systemNotifications = [
    const _NotificationItem(message: 'Loading...', type: NotificationType.info),
  ];
  String? _appVersion;

  // ── Bottom navigation ──
  int _selectedTabIndex = 0;

  // ── Current Month Trips state ──
  bool _isLoadingTrips = true;
  List<Map<String, dynamic>> _currentMonthTrips = [];
  String? _tripsError;
  _DriverDocumentAlert? _driverDocumentAlert;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _now = DateTime.now();
    NotificationService().forceShowBell();
    unawaited(NotificationService().bindInboxUser(widget.user.id));
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

    _safetyRepository = SafetyRepository(currentUser: widget.user);
    _loadActiveShift();
    _loadNotifications();
    _loadAppVersion();
    _loadBiometricSetting();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForAppUpdate();
      _checkTrainingRequirement();
      _loadCurrentMonthTrips();
    });
    unawaited(_loadDriverDocumentAlert());

    _startGpsPingService();
  }

  Future<void> _loadBiometricSetting() async {
    final enabled = await _biometricService.isEnabledForUser(widget.user.id);
    final supported = await _biometricService.isSupported();
    if (!mounted) return;
    setState(() {
      _biometricEnabled = enabled;
      _biometricSupported = supported;
    });
  }

  Future<void> _openBiometricSheet() async {
    await BiometricEnableSheet.show(context, userId: widget.user.id);
    // Sync state from the sheet result
    final currentEnabled = await _biometricService.isEnabledForUser(
      widget.user.id,
    );
    if (!mounted) return;
    setState(() => _biometricEnabled = currentEnabled);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == _observedRoute) {
      return;
    }
    if (_observedRoute is PageRoute<dynamic>) {
      appRouteObserver.unsubscribe(this);
    }
    _observedRoute = route;
    if (route is PageRoute<dynamic>) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    if (_dashboardBellHiddenByOverlay) {
      NotificationService().releaseBellHide();
      _dashboardBellHiddenByOverlay = false;
    }
    if (_observedRoute is PageRoute<dynamic>) {
      appRouteObserver.unsubscribe(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _glowController.dispose();
    _gpsPingService?.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _startGpsPingService();
      unawaited(
        NotificationService().syncInboxFromServer(userId: widget.user.id),
      );
      unawaited(_loadDriverDocumentAlert());
      _checkForAppUpdate();
      _checkTrainingRequirement();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _gpsPingService?.stop();
    }
  }

  @override
  void didPush() {
    NotificationService().forceShowBell();
    if (_dashboardBellHiddenByOverlay) {
      NotificationService().releaseBellHide();
      _dashboardBellHiddenByOverlay = false;
    }
  }

  @override
  void didPopNext() {
    NotificationService().forceShowBell();
    if (_dashboardBellHiddenByOverlay) {
      NotificationService().releaseBellHide();
      _dashboardBellHiddenByOverlay = false;
    }
  }

  @override
  void didPushNext() {
    if (_dashboardBellHiddenByOverlay) return;
    NotificationService().requestBellHide();
    _dashboardBellHiddenByOverlay = true;
  }

  void _startGpsPingService() {
    _gpsPingService ??= GpsPingService(
      user: widget.user,
      repository: _gpsPingRepository,
    );
    _gpsPingService?.start(
      showToast: (message, {bool isError = false}) {
        if (mounted) {
          showAppToast(context, message, isError: isError);
        }
      },
    );
  }

  Future<void> _showNotificationDetails(_NotificationItem item) {
    if (item.isPlaceholder) {
      return Future.value();
    }

    final detailMessage = _resolveNotificationMessage(item);
    return showNotificationDetailDialog(
      context,
      title: 'Dashboard Alert',
      message: detailMessage,
    );
  }

  String _resolveNotificationMessage(_NotificationItem item) {
    if (item.message.trim().isNotEmpty) {
      return item.message;
    }
    return 'Notification received.';
  }

  void _handleVehicleUpdated(DriverVehicle vehicle) {
    setState(() {
      _selectedVehicleId = vehicle.id;
      _selectedVehicleNumber = vehicle.vehicleNumber;
    });
  }

  Future<void> _checkForAppUpdate() async {
    final status = await _appUpdateService.checkForUpdate();
    if (!mounted || !status.isUpdateAvailable) {
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

  Future<void> _checkTrainingRequirement() async {
    if (_checkingTraining) return;
    _checkingTraining = true;
    try {
      // Reload latest user and override to catch updated flag without relogin
      final storedUser = await AuthStorageService.getUser();
      final effectiveUser = storedUser ?? widget.user;
      final override = await TrainingFlagService.isTrainingRequiredOverride();
      final trainingRequiredFlag = effectiveUser.trainingRequired || override;
      final shouldRedirect =
          trainingRequiredFlag &&
          (effectiveUser.role == UserRole.driver ||
              effectiveUser.role == UserRole.supervisor);

      if (shouldRedirect && mounted) {
        // use freshest user context for repository
        final repoUser = storedUser ?? widget.user;
        _safetyRepository = SafetyRepository(currentUser: repoUser);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SafetyTrainingScreen(
              user: repoUser,
              repository: _safetyRepository,
            ),
          ),
        );
      }
    } catch (_) {
      // Best-effort; ignore errors to avoid blocking dashboard usage
    } finally {
      _checkingTraining = false;
    }
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
        final checkInLabel = DateFormat('hh:mm a').format(inTime);
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
            message: 'No dashboard alerts right now',
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
      final currentMonthRecords = await _attendanceRepository.fetchHistory(
        driverId: driverId,
        month: DateTime(today.year, today.month),
      );
      final previousMonthRecords = await _attendanceRepository.fetchHistory(
        driverId: driverId,
        month: DateTime(today.year, today.month - 1),
      );
      DateTime? recordTime(AttendanceRecord item) {
        final inTime = _parseDate(item.inTime);
        final outTime = _parseDate(item.outTime);
        if (inTime == null) return outTime;
        if (outTime == null) return inTime;
        return outTime.isAfter(inTime) ? outTime : inTime;
      }

      final candidates = <AttendanceRecord>[
        ...currentMonthRecords,
        ...previousMonthRecords,
      ];
      AttendanceRecord? record;
      for (final item in candidates) {
        final itemTime = recordTime(item);
        final selectedTime = record == null ? null : recordTime(record);
        if (itemTime != null &&
            (selectedTime == null || itemTime.isAfter(selectedTime))) {
          record = item;
        }
      }
      if (!mounted) return;

      final now = DateTime.now();
      bool attendanceLocked = false;
      String? summary;
      if (record != null) {
        final inTime = _parseDate(record.inTime);
        final outTime = _parseDate(record.outTime);
        if (inTime != null && _isMissingTimeValue(record.outTime)) {
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

  bool _isMissingTimeValue(String? raw) {
    if (raw == null) return true;
    final v = raw.trim().toLowerCase();
    return v.isEmpty ||
        v == 'null' ||
        v == 'none' ||
        v == 'na' ||
        v == 'n/a' ||
        v == '0' ||
        v.startsWith('0000-00-00');
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isBeforeToday(DateTime candidate, DateTime reference) {
    final todayStart = DateTime(reference.year, reference.month, reference.day);
    return candidate.isBefore(todayStart);
  }

  bool get _hasOpenShift {
    final record = _latestShift;
    if (record == null) {
      return false;
    }
    final inTime = _parseDate(record.inTime);
    if (inTime == null || !_isSameDay(inTime, DateTime.now())) {
      return false;
    }
    return _isMissingTimeValue(record.outTime);
  }

  bool get _hasPastOpenShift {
    final record = _latestShift;
    if (record == null) {
      return false;
    }
    final inTime = _parseDate(record.inTime);
    if (inTime == null || !_isBeforeToday(inTime, DateTime.now())) {
      return false;
    }
    return _isMissingTimeValue(record.outTime);
  }

  String get _attendanceButtonLabel {
    if (_isLoadingShift) {
      return 'Mark Attendance';
    }
    if (_hasOpenShift) {
      return 'Check-out Pending';
    }
    if (_hasPastOpenShift) {
      return 'Mark Previous Day';
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

  Future<void> _handleAttendanceButtonTap() async {
    if (_isAttendanceLockedToday && !_hasOpenShift && !_hasPastOpenShift) {
      showAppToast(
        context,
        'Attendance already marked for today.',
        isError: false,
      );
      return;
    }
    if (_isCheckingAbsence) {
      return;
    }

    final driverIdValue = (widget.user.driverId ?? widget.user.id)
        .toString()
        .trim();
    final plantIdValue = widget.user.plantId?.trim();

    if (driverIdValue.isEmpty) {
      _openScreen(
        CheckInOutScreen(
          user: widget.user,
          availableVehicles: widget.user.availableVehicles,
          selectedVehicleId: _selectedVehicleId,
          onVehicleAssigned: _handleVehicleUpdated,
        ),
      );
      return;
    }

    setState(() => _isCheckingAbsence = true);
    try {
      final status = await _attendanceRepository.fetchDriverAbsenceStatus(
        driverId: driverIdValue,
        plantId: plantIdValue,
      );
      if (status.isAbsent) {
        showAppToast(
          context,
          'Attendance disabled for today. Please contact your supervisor.',
          isError: true,
        );
        return;
      }
    } on AttendanceFailure catch (error) {
      showAppToast(context, error.message, isError: true);
      return;
    } catch (_) {
      showAppToast(
        context,
        'Unable to verify attendance eligibility. Try again shortly.',
        isError: true,
      );
      return;
    } finally {
      if (mounted) {
        setState(() => _isCheckingAbsence = false);
      }
    }

    _openScreen(
      CheckInOutScreen(
        user: widget.user,
        availableVehicles: widget.user.availableVehicles,
        selectedVehicleId: _selectedVehicleId,
        onVehicleAssigned: _handleVehicleUpdated,
      ),
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

  // ── Load current month trips ──
  Future<void> _loadCurrentMonthTrips() async {
    final driverId = widget.user.driverId;
    if (driverId == null || driverId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoadingTrips = false;
          _currentMonthTrips = [];
          _tripsError = null;
        });
      }
      return;
    }

    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1);
    final to = DateTime(now.year, now.month + 1, 0); // last day of month
    final fromStr = DateFormat('yyyy-MM-dd').format(from);
    final toStr = DateFormat('yyyy-MM-dd').format(to);

    try {
      final response = await http.post(
        Uri.parse(
          'https://sstranswaysindia.com/api/mobile/driver_trip_details_by_date.php',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'driverId': driverId, 'from': fromStr, 'to': toStr}),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'ok') {
          final byDateRaw = data['byDate'];
          final allTrips = <Map<String, dynamic>>[];
          if (byDateRaw is Map) {
            for (final dateEntry in byDateRaw.entries) {
              final trips = dateEntry.value;
              if (trips is List) {
                for (final trip in trips) {
                  if (trip is Map<String, dynamic>) {
                    allTrips.add(trip);
                  }
                }
              }
            }
          }
          // Sort by startDate descending
          allTrips.sort((a, b) {
            final aDate = (a['startDate'] ?? '') as String;
            final bDate = (b['startDate'] ?? '') as String;
            return bDate.compareTo(aDate);
          });
          setState(() {
            _currentMonthTrips = allTrips;
            _isLoadingTrips = false;
            _tripsError = null;
          });
        } else {
          setState(() {
            _isLoadingTrips = false;
            _tripsError = data['error'] as String? ?? 'Failed to load trips';
          });
        }
      } else {
        setState(() {
          _isLoadingTrips = false;
          _tripsError = 'Server error (${response.statusCode})';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingTrips = false;
          _tripsError = 'Unable to load trips: $e';
        });
      }
    }
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

    // ── Brand colors ──
    const navyDark = Color(0xFF0A1628);
    const navyBrand = Color(0xFF153753);
    const goldAccent = Color(0xFFD4A843);
    const surfaceBg = Color(0xFFF4F7FC);
    const cardBg = Color(0xFFFFFFFE);

    final isDriver =
        widget.user.role == 'Driver' || widget.user.role == 'Helper';
    final roleLabel = isHelper ? 'Helper' : 'Driver';

    return Scaffold(
      backgroundColor: surfaceBg,
      drawer: Drawer(
        backgroundColor: Colors.white,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0A1628), Color(0xFF153753)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ProfilePhotoWidget(user: widget.user, radius: 28),
                    const SizedBox(height: 12),
                    Text(
                      widget.user.displayName,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      roleLabel,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: goldAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              _drawerTile(Icons.person_outline, 'Profile', () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DriverProfileScreen(user: widget.user),
                  ),
                );
              }),
              _drawerTile(Icons.bar_chart_rounded, 'Monthly Statistics', () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MonthlyStatisticsScreen(user: widget.user),
                  ),
                );
              }),
              _drawerTile(Icons.notifications_outlined, 'Notifications', () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationSettingsScreen(),
                  ),
                );
              }),
              _drawerTile(
                Icons.folder_shared_outlined,
                'Personal Documents',
                () {
                  Navigator.of(context).pop();
                  showPersonalDocumentsSheet(context, widget.user);
                },
              ),
              _drawerTile(Icons.play_circle_outline, 'Watch Ads & Earn', () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WatchAdsScreen(user: widget.user),
                  ),
                );
              }),
              _drawerTile(Icons.card_giftcard_rounded, 'Referral Program', () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReferralTrackerScreen(user: widget.user),
                  ),
                );
              }),
              _drawerTile(
                Icons.fingerprint,
                _biometricEnabled ? 'Biometric (Enabled)' : 'Biometric Unlock',
                () {
                  Navigator.of(context).pop();
                  _openBiometricSheet();
                },
                iconColor: _biometricEnabled ? Colors.green : null,
              ),
              const Divider(),
              _drawerTile(Icons.logout_rounded, 'Logout', () {
                Navigator.of(context).pop();
                widget.onLogout();
                showAppToast(context, 'Logged out successfully');
              }, iconColor: Colors.red.shade400),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Version ${_appVersion ?? '...'}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: navyBrand.withOpacity(0.4),
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
      body: switch (_selectedTabIndex) {
        0 => _buildHomeTab(
          context,
          theme: theme,
          textTheme: textTheme,
          dateFormatter: dateFormatter,
          timeFormatter: timeFormatter,
          isHelper: isHelper,
          plantDisplay: plantDisplay,
          vehicleDisplay: vehicleDisplay,
          supervisorName: supervisorName,
          tenureSubtitle: tenureSubtitle,
          navyDark: navyDark,
          navyBrand: navyBrand,
          goldAccent: goldAccent,
          surfaceBg: surfaceBg,
          cardBg: cardBg,
        ),
        1 => AdvanceSalaryScreen(user: widget.user),
        2 => SalaryAdvanceScreen(user: widget.user),
        3 => TripScreen(
          user: widget.user,
          onBack: () => setState(() => _selectedTabIndex = 0),
        ),
        _ => const SizedBox.shrink(),
      },
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, child) {
          final statusColor = _hasOpenShift
              ? const Color(0xFFE0BC00)
              : _hasPastOpenShift
              ? const Color(0xFFD8B4FE)
              : _isAttendanceLockedToday
              ? const Color(0xFFB0BEC5)
              : const Color(0xFF00EB5E);
          return Container(
            height: 76,
            width: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withOpacity(
                    0.4 + _glowAnimation.value * 0.3,
                  ),
                  blurRadius: 10 + _glowAnimation.value * 12,
                  spreadRadius: 2 + _glowAnimation.value * 4,
                ),
              ],
            ),
            child: FloatingActionButton.large(
              onPressed: _isCheckingAbsence ? null : _handleAttendanceButtonTap,
              backgroundColor: Colors.transparent,
              elevation: 0,
              shape: CircleBorder(
                side: BorderSide(color: statusColor, width: 3.5),
              ),
              child: ClipOval(
                child: SizedBox.expand(
                  child: Image.asset(
                    'assets/images/attendance_mark.gif',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        elevation: 0,
        height: 58,
        surfaceTintColor: Colors.transparent,
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(
              child: _buildNavItem(0, Icons.home_rounded, 'Home', navyBrand),
            ),
            Expanded(
              child: _buildNavItem(
                1,
                Icons.account_balance_wallet_rounded,
                'Khatabook',
                navyBrand,
              ),
            ),
            const SizedBox(width: 72), // space for FAB
            Expanded(
              child: _buildNavItem(
                2,
                Icons.payments_rounded,
                'Salary',
                navyBrand,
              ),
            ),
            Expanded(
              child: _buildNavItem(
                3,
                Icons.local_shipping_rounded,
                'Trips',
                navyBrand,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData icon,
    String label,
    Color activeColor,
  ) {
    final isActive = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTabIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isActive ? activeColor : Colors.grey.shade400,
            ),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 9,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? activeColor : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerTile(
    IconData icon,
    String title,
    VoidCallback onTap, {
    Color? iconColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? const Color(0xFF153753)),
      title: Text(
        title,
        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      onTap: onTap,
      dense: true,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildHomeTab(
    BuildContext context, {
    required ThemeData theme,
    required TextTheme textTheme,
    required DateFormat dateFormatter,
    required DateFormat timeFormatter,
    required bool isHelper,
    required String plantDisplay,
    required String vehicleDisplay,
    required String? supervisorName,
    required String? tenureSubtitle,
    required Color navyDark,
    required Color navyBrand,
    required Color goldAccent,
    required Color surfaceBg,
    required Color cardBg,
  }) {
    const headerExpandedHeight = 184.0;
    final attendanceAccent = _hasOpenShift
        ? const Color(0xFFE0BC00)
        : _hasPastOpenShift
        ? const Color(0xFFD8B4FE)
        : _isAttendanceLockedToday
        ? const Color(0xFFB0BEC5)
        : const Color(0xFF00EB5E);
    final attendanceChipBackground = _hasOpenShift
        ? const Color(0xFFE0BC00).withOpacity(0.18)
        : _hasPastOpenShift
        ? const Color(0xFFD8B4FE).withOpacity(0.18)
        : _isAttendanceLockedToday
        ? const Color(0xFFB0BEC5).withOpacity(0.18)
        : const Color(0xFF00EB5E).withOpacity(0.16);
    final attendanceChipTextColor = _hasOpenShift
        ? const Color(0xFFFFF6CC)
        : _hasPastOpenShift
        ? const Color(0xFFF5EAFF)
        : _isAttendanceLockedToday
        ? const Color(0xFFF4F7F9)
        : const Color(0xFFEFFFEF);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Pinned header: profile/name stays visible on scroll ──
        SliverAppBar(
          pinned: true,
          floating: false,
          snap: false,
          backgroundColor: navyBrand,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          toolbarHeight: 72,
          expandedHeight: headerExpandedHeight,
          title: _DriverCollapsedHeaderTitle(
            user: widget.user,
            onLogout: () {
              widget.onLogout();
              showAppToast(context, 'You have been logged out');
            },
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: LayoutBuilder(
              builder: (context, constraints) {
                final settings = context
                    .dependOnInheritedWidgetOfExactType<
                      FlexibleSpaceBarSettings
                    >();
                final minExtent = settings?.minExtent ?? kToolbarHeight;
                final maxExtent = settings?.maxExtent ?? headerExpandedHeight;
                final currentExtent = settings?.currentExtent ?? maxExtent;
                final rawT =
                    (currentExtent - minExtent) / (maxExtent - minExtent);
                final t = rawT.clamp(0.0, 1.0);
                final upperSectionVisibility = ((t - 0.26) / 0.24).clamp(
                  0.0,
                  1.0,
                );
                final lowerSectionVisibility = ((t - 0.42) / 0.16).clamp(
                  0.0,
                  1.0,
                );

                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [navyDark, navyBrand],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          ClipRect(
                            child: Align(
                              alignment: Alignment.topCenter,
                              heightFactor: upperSectionVisibility,
                              child: Opacity(
                                opacity: upperSectionVisibility,
                                child: Row(
                                  children: [
                                    Builder(
                                      builder: (ctx) => GestureDetector(
                                        onTap: () =>
                                            Scaffold.of(ctx).openDrawer(),
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(
                                              0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.menu_rounded,
                                            color: Colors.white70,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    ProfilePhotoWithUpload(
                                      user: widget.user,
                                      radius: 22,
                                      onPhotoSelected: _handlePhotoSelected,
                                      isUploading: _isUploadingPhoto,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          ClipRect(
                                            child: Align(
                                              alignment: Alignment.topLeft,
                                              heightFactor:
                                                  upperSectionVisibility,
                                              child: Opacity(
                                                opacity: upperSectionVisibility,
                                                child: Wrap(
                                                  crossAxisAlignment:
                                                      WrapCrossAlignment.center,
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  children: [
                                                    _heroPill(
                                                      icon:
                                                          Icons.badge_outlined,
                                                      text: isHelper
                                                          ? 'Helper'
                                                          : 'Driver',
                                                      color: goldAccent,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          Text(
                                            widget.user.displayName,
                                            style: GoogleFonts.poppins(
                                              fontSize: 20,
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: IconButton(
                                        onPressed: () {
                                          widget.onLogout();
                                          showAppToast(
                                            context,
                                            'You have been logged out',
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.logout_rounded,
                                          color: Colors.white70,
                                          size: 20,
                                        ),
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 40,
                                              height: 40,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                if (tenureSubtitle != null) ...[
                                  _heroPill(
                                    icon: Icons.access_time_rounded,
                                    text: tenureSubtitle,
                                    color: const Color(0xFF9AE630),
                                  ),
                                ],
                                const SizedBox(width: 8),
                                _heroPill(
                                  icon: Icons.calendar_today_rounded,
                                  text: dateFormatter.format(_now),
                                  color: Colors.white70,
                                ),
                                const SizedBox(width: 8),
                                _heroPill(
                                  icon: Icons.schedule_rounded,
                                  text: timeFormatter.format(_now),
                                  color: Colors.white70,
                                ),
                              ],
                            ),
                          ),
                          ClipRect(
                            child: Align(
                              alignment: Alignment.topCenter,
                              heightFactor: lowerSectionVisibility,
                              child: Opacity(
                                opacity: lowerSectionVisibility,
                                child: Transform.translate(
                                  offset: Offset(
                                    0,
                                    10 * (1 - lowerSectionVisibility),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _heroInfoChip(
                                              icon: Icons.factory_outlined,
                                              label: '',
                                              value: plantDisplay,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: _heroInfoChip(
                                              icon:
                                                  Icons.local_shipping_rounded,
                                              label: 'Vehicle',
                                              value: vehicleDisplay,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (supervisorName != null &&
                                          supervisorName.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.person_outline,
                                              size: 14,
                                              color: Colors.white.withOpacity(
                                                0.5,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Supervisor: $supervisorName',
                                              style: GoogleFonts.poppins(
                                                fontSize: 11.5,
                                                color: Colors.white.withOpacity(
                                                  0.6,
                                                ),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      if (_shiftSummary != null) ...[
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: attendanceChipBackground,
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: attendanceAccent
                                                  .withOpacity(0.42),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.info_outline,
                                                size: 11,
                                                color: attendanceAccent,
                                              ),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  _shiftSummary!,
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 9.25,
                                                    color:
                                                        attendanceChipTextColor,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // ── Body Content ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Quick Actions Grid ──
                _buildDashboardSectionHeader(
                  title: 'Quick Actions',
                  icon: Icons.grid_view_rounded,
                  navyBrand: navyBrand,
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 4,
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 6,
                  childAspectRatio: 1.1,
                  children: [
                    _quickActionTile(
                      icon: Icons.history_rounded,
                      label: 'History',
                      gradient: const [Color(0xFF667eea), Color(0xFF764ba2)],
                      onTap: () => _openScreen(
                        AttendanceHistoryScreen(user: widget.user),
                      ),
                    ),
                    _quickActionTile(
                      icon: Icons.beach_access_rounded,
                      label: 'Leave',
                      gradient: const [Color(0xFF11998e), Color(0xFF38ef7d)],
                      onTap: () => showApplyLeaveSheet(context, widget.user),
                    ),
                    _quickActionTile(
                      icon: Icons.account_balance_wallet_rounded,
                      label: 'Khata',
                      gradient: const [Color(0xFFf7971e), Color(0xFFffd200)],
                      onTap: () =>
                          _openScreen(AdvanceSalaryScreen(user: widget.user)),
                    ),
                    _quickActionTile(
                      icon: Icons.safety_check_rounded,
                      label: 'Safety',
                      gradient: const [Color(0xFFe53935), Color(0xFFff7043)],
                      onTap: () =>
                          _openScreen(SafetyHubScreen(user: widget.user)),
                    ),
                    if (!isHelper)
                      _quickActionTile(
                        icon: Icons.local_shipping_rounded,
                        label: 'Trips',
                        gradient: const [Color(0xFF0A1628), Color(0xFF153753)],
                        onTap: () => _openScreen(TripScreen(user: widget.user)),
                      ),
                    _quickActionTile(
                      icon: Icons.description_rounded,
                      label: 'Trip Sheet',
                      gradient: const [Color(0xFF1565C0), Color(0xFF42A5F5)],
                      onTap: () =>
                          _openScreen(TripSheetScreen(user: widget.user)),
                    ),
                    _quickActionTile(
                      icon: Icons.edit_calendar_rounded,
                      label: 'Adjust',
                      gradient: const [Color(0xFF7B1FA2), Color(0xFFBA68C8)],
                      onTap: () => _openScreen(
                        AttendanceAdjustRequestScreen(user: widget.user),
                      ),
                    ),
                    _quickActionTile(
                      icon: Icons.card_giftcard_rounded,
                      label: 'Refer',
                      gradient: const [Color(0xFFE91E63), Color(0xFFF48FB1)],
                      onTap: () =>
                          _openScreen(ReferralTrackerScreen(user: widget.user)),
                    ),
                    _quickActionTile(
                      icon: Icons.swap_horiz_rounded,
                      label: 'Vehicle',
                      gradient: const [Color(0xFF00796B), Color(0xFF4DB6AC)],
                      onTap: _isChangingVehicle ? null : _openVehiclePicker,
                    ),
                  ],
                ),

                if (_driverDocumentAlert != null) ...[
                  const SizedBox(height: 0),
                  Transform.translate(
                    offset: const Offset(0, -16),
                    child: _buildDriverDocumentAlertBanner(),
                  ),
                ],

                const SizedBox(height: 0),

                // ── Current Month Trips Section ──
                Transform.translate(
                  offset: const Offset(0, -12),
                  child: _buildCurrentMonthTripsSection(theme, textTheme),
                ),

                const SizedBox(height: 16),

                // ── Biometric Security Card ──
                _BiometricSecurityCard(
                  isEnabled: _biometricEnabled,
                  isSupported: _biometricSupported,
                  onTap: _openBiometricSheet,
                ),

                // ── Notifications ──
                const SizedBox(height: 16),
                _buildNotificationsCard(navyBrand, cardBg),

                const SizedBox(height: 16),

                // Version
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Version ${_appVersion ?? '...'}',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: navyBrand.withOpacity(0.35),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Hero pill (small tag in header) ──
  Widget _heroPill({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 9.5,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero info chip (plant/vehicle in header) ──
  Widget _heroInfoChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final hasLabel = label.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: Colors.white70),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasLabel)
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      color: Colors.white.withOpacity(0.5),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                if (hasLabel) const SizedBox(height: 1),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick action tile in grid ──
  Widget _quickActionTile({
    required IconData icon,
    required String label,
    required List<Color> gradient,
    VoidCallback? onTap,
    Widget? statusWidget,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: gradient.first.withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          if (statusWidget != null) ...[
            const SizedBox(height: 5),
            statusWidget,
          ] else
            const SizedBox(height: 1),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF153753),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  int? _resolveDriverDocumentDriverId() {
    final driverId = (widget.user.driverId ?? '').trim();
    final userId = widget.user.id.trim();
    return int.tryParse(driverId) ?? int.tryParse(userId);
  }

  Future<void> _loadDriverDocumentAlert() async {
    final driverId = _resolveDriverDocumentDriverId();
    if (driverId == null) {
      if (!mounted) {
        return;
      }
      setState(() => _driverDocumentAlert = null);
      return;
    }

    try {
      final response = await http.post(
        Uri.parse(_driverDocumentsListUrl),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'driverId': driverId}),
      );
      final body = utf8.decode(response.bodyBytes);
      final payload = jsonDecode(body) as Map<String, dynamic>? ?? const {};
      if (response.statusCode != 200 || payload['status'] != 'ok') {
        return;
      }

      final documents = (payload['documents'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      final alert = _buildDriverDocumentAlertFromDocuments(documents);
      if (!mounted) {
        return;
      }
      setState(() => _driverDocumentAlert = alert);
    } catch (_) {
      // Keep the current UI state unchanged on fetch failure.
    }
  }

  String _normalizeAlertDocumentName(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) {
      return 'Document';
    }

    final displayName = widget.user.displayName.trim();
    if (displayName.isNotEmpty) {
      final lowerName = trimmed.toLowerCase();
      final lowerDisplayName = displayName.toLowerCase();
      final dashedPrefix = '$lowerDisplayName - ';
      final colonPrefix = '$lowerDisplayName: ';
      if (lowerName.startsWith(dashedPrefix)) {
        return trimmed.substring(displayName.length + 3).trim();
      }
      if (lowerName.startsWith(colonPrefix)) {
        return trimmed.substring(displayName.length + 2).trim();
      }
    }

    return trimmed;
  }

  _DriverDocumentAlert? _buildDriverDocumentAlertFromDocuments(
    List<Map<String, dynamic>> documents,
  ) {
    if (documents.isEmpty) {
      return null;
    }

    final today = DateUtils.dateOnly(DateTime.now());
    String? expiredDocumentName;
    DateTime? expiredAt;
    String? expiringDocumentName;
    int? expiringDays;
    String? expiringDateLabel;

    for (final document in documents) {
      final rawExpiry = (document['expiry_date'] ?? '').toString().trim();
      if (rawExpiry.isEmpty || rawExpiry == '0000-00-00') {
        continue;
      }
      final expiry = DateTime.tryParse(rawExpiry);
      if (expiry == null) {
        continue;
      }
      final expiryLabel = DateFormat('dd MMM yy').format(expiry);

      final daysUntilExpiry = DateUtils.dateOnly(
        expiry,
      ).difference(today).inDays;
      final documentName =
          (document['document_name'] ?? document['document_type'] ?? 'Document')
              .toString()
              .trim();
      final normalizedDocumentName = _normalizeAlertDocumentName(documentName);
      if (daysUntilExpiry < 0) {
        if (expiredAt == null || expiry.isBefore(expiredAt)) {
          expiredAt = expiry;
          expiredDocumentName = normalizedDocumentName.isEmpty
              ? 'Document'
              : normalizedDocumentName;
        }
        continue;
      }
      if (daysUntilExpiry <= _driverDocumentWarningDays &&
          (expiringDays == null || daysUntilExpiry < expiringDays)) {
        expiringDays = daysUntilExpiry;
        expiringDocumentName = normalizedDocumentName.isEmpty
            ? 'Document'
            : normalizedDocumentName;
        expiringDateLabel = expiryLabel;
      }
    }

    if (expiredDocumentName != null) {
      return _DriverDocumentAlert(
        documentName: expiredDocumentName,
        statusText:
            'Expired (Expired: ${DateFormat('dd MMM yy').format(expiredAt!)})',
        icon: Icons.warning_amber_rounded,
        backgroundColor: const Color(0xFFE53935),
        foregroundColor: Colors.white,
        borderColor: const Color(0xFFFFCDD2),
      );
    }

    if (expiringDocumentName == null || expiringDays == null) {
      return null;
    }

    return _DriverDocumentAlert(
      documentName: expiringDocumentName,
      statusText:
          'Due in $expiringDays ${expiringDays == 1 ? 'day' : 'days'} (Expiring: ${expiringDateLabel ?? ''})',
      icon: Icons.warning_amber_rounded,
      backgroundColor: const Color(0xFFFFC107),
      foregroundColor: const Color(0xFF4E342E),
      borderColor: const Color(0xFFFFECB3),
    );
  }

  Widget _buildDriverDocumentAlertBanner() {
    final alert = _driverDocumentAlert;
    if (alert == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        final pulse = ((_glowAnimation.value - 0.35) / 0.5).clamp(0.0, 1.0);
        final isExpired = alert.statusText.startsWith('Expired');
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: alert.backgroundColor.withOpacity(
              isExpired ? (0.48 + pulse * 0.5) : (0.56 + pulse * 0.34),
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: alert.borderColor.withOpacity(
                isExpired ? (0.65 + pulse * 0.35) : (0.58 + pulse * 0.34),
              ),
              width: isExpired ? 1.2 : 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: alert.backgroundColor.withOpacity(
                  isExpired ? (0.24 + pulse * 0.34) : (0.2 + pulse * 0.28),
                ),
                blurRadius: isExpired ? (12 + pulse * 12) : (10 + pulse * 10),
                spreadRadius: isExpired
                    ? (0.8 + pulse * 2.4)
                    : (0.6 + pulse * 1.8),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(alert.icon, size: 16, color: alert.foregroundColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${alert.documentName}: ${alert.statusText}',
                  style: GoogleFonts.poppins(
                    fontSize: 10.4,
                    fontWeight: FontWeight.w700,
                    color: alert.foregroundColor,
                    letterSpacing: 0.15,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDashboardSectionHeader({
    required String title,
    required IconData icon,
    required Color navyBrand,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [navyBrand, const Color(0xFF1E5A8C)],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 14),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: navyBrand,
          ),
        ),
      ],
    );
  }

  // ── Notifications card ──
  Widget _buildNotificationsCard(Color navyBrand, Color cardBg) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: navyBrand.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: navyBrand.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [navyBrand, const Color(0xFF1E5A8C)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Alerts',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: navyBrand,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ..._systemNotifications.map(
            (notif) => InkWell(
              onTap: () => _showNotificationDetails(notif),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: notif.type.color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        notif.message,
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: navyBrand.withOpacity(0.75),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: navyBrand.withOpacity(0.3),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCurrentMonthTripsSection(ThemeData theme, TextTheme textTheme) {
    final monthLabel = DateFormat('MMMM yyyy').format(DateTime.now());
    final totalTrips = _currentMonthTrips.length;
    int totalKm = 0;
    for (final trip in _currentMonthTrips) {
      final startKm = trip['startKm'] as int?;
      final endKm = trip['endKm'] as int?;
      if (startKm != null && endKm != null && endKm > startKm) {
        totalKm += (endKm - startKm);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.local_shipping, size: 20),
            const SizedBox(width: 6),
            Text('Trips — $monthLabel', style: textTheme.titleMedium),
            const Spacer(),
            if (_isLoadingTrips)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () {
                  setState(() => _isLoadingTrips = true);
                  _loadCurrentMonthTrips();
                },
                tooltip: 'Refresh trips',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isLoadingTrips)
          Card(
            color: Colors.white,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: AppLoader()),
            ),
          )
        else if (_tripsError != null && _currentMonthTrips.isEmpty)
          Card(
            color: Colors.white,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.error,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _tripsError!,
                    style: textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      setState(() => _isLoadingTrips = true);
                      _loadCurrentMonthTrips();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          )
        else if (_currentMonthTrips.isEmpty)
          // No trips — always show for drivers with contact message
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFCC80), width: 1),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Colors.orange.shade700,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  'No Trips Added',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Contact Supervisor',
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )
        else ...[
          // Summary row
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$totalTrips',
                        style: textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Trips',
                        style: textTheme.labelSmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF11998e), Color(0xFF38ef7d)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text(
                        NumberFormat('#,###').format(totalKm),
                        style: textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'KM Run',
                        style: textTheme.labelSmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Individual trip cards (show max 10, most recent first)
          ..._currentMonthTrips.take(10).map((trip) {
            final startDate = trip['startDate'] as String? ?? '';
            final vehicle = trip['vehicleNumber'] as String? ?? '';
            final status = trip['status'] as String? ?? '';
            final startKm = trip['startKm'] as int?;
            final endKm = trip['endKm'] as int?;
            final runKm = (startKm != null && endKm != null && endKm > startKm)
                ? (endKm - startKm)
                : null;
            final customers = trip['customers'] as String? ?? '';
            final isOngoing =
                status.toLowerCase() == 'ongoing' ||
                status.toLowerCase() == 'started';

            String displayDate = startDate;
            try {
              displayDate = DateFormat(
                'dd MMM yyyy',
              ).format(DateTime.parse(startDate));
            } catch (_) {}

            return Card(
              color: Colors.white,
              elevation: 1,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isOngoing
                      ? Colors.amber.shade300
                      : Colors.grey.shade200,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          displayDate,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isOngoing
                                ? Colors.amber.shade50
                                : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isOngoing
                                  ? Colors.amber.shade300
                                  : Colors.green.shade300,
                            ),
                          ),
                          child: Text(
                            isOngoing ? 'Ongoing' : 'Ended',
                            style: textTheme.labelSmall?.copyWith(
                              color: isOngoing
                                  ? Colors.amber.shade800
                                  : Colors.green.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.local_shipping,
                          size: 14,
                          color: Colors.blueGrey,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            vehicle,
                            style: textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (runKm != null)
                          Chip(
                            label: Text(
                              '${NumberFormat('#,###').format(runKm)} km',
                            ),
                            labelStyle: textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.indigo.shade700,
                            ),
                            backgroundColor: Colors.indigo.shade50,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            side: BorderSide(color: Colors.indigo.shade200),
                          ),
                      ],
                    ),
                    if (customers.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.business,
                            size: 14,
                            color: Colors.blueGrey,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              customers,
                              style: textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          if (_currentMonthTrips.length > 10)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(
                child: TextButton(
                  onPressed: () => _openScreen(TripScreen(user: widget.user)),
                  child: Text(
                    'View all ${_currentMonthTrips.length} trips →',
                    style: textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
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
    this.icon = Icons.arrow_right_alt,
    this.iconColor,
    this.textColor,
    this.isLoading = false,
  });

  final Animation<double> animation;
  final VoidCallback onTap;
  final String label;
  final Gradient? gradient;
  final IconData icon;
  final Color? iconColor;
  final Color? textColor;
  final bool isLoading;

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
              colors: [Color(0xFF00EB5E), Color(0xFF00C853)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            );
        return GestureDetector(
          onTap: isLoading ? null : onTap,
          child: Container(
            decoration: BoxDecoration(
              gradient: gradientValue,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.black, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.16 + glow * 0.14),
                  offset: const Offset(0, 2),
                  blurRadius: 10 + glow * 16,
                  spreadRadius: glow * 2.5,
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Transform.scale(
              scale: 1.0 + glow * 0.10,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: iconColor ?? Colors.black, size: 26),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 22,
                      color: textColor ?? Colors.black,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (isLoading) ...[
                    const SizedBox(width: 12),
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
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

class _DriverCollapsedHeaderTitle extends StatelessWidget {
  const _DriverCollapsedHeaderTitle({
    required this.user,
    required this.onLogout,
  });

  final AppUser user;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final minExtent = settings?.minExtent ?? kToolbarHeight;
    final currentExtent = settings?.currentExtent ?? minExtent;
    final isCollapsed = currentExtent <= minExtent + 1;

    if (!isCollapsed) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        Builder(
          builder: (ctx) => GestureDetector(
            onTap: () => Scaffold.of(ctx).openDrawer(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.menu_rounded,
                color: Colors.white70,
                size: 20,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        ProfilePhotoWidget(user: user, radius: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            user.displayName,
            style: GoogleFonts.poppins(
              fontSize: 16,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: IconButton(
            onPressed: onLogout,
            icon: const Icon(
              Icons.logout_rounded,
              color: Colors.white70,
              size: 18,
            ),
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

class _DriverDocumentAlert {
  const _DriverDocumentAlert({
    required this.documentName,
    required this.statusText,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
  });

  final String documentName;
  final String statusText;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
}

class _BiometricSecurityCard extends StatelessWidget {
  const _BiometricSecurityCard({
    required this.isEnabled,
    required this.isSupported,
    required this.onTap,
  });

  final bool isEnabled;
  final bool isSupported;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = isEnabled
        ? const Color(0xFF00C853)
        : const Color(0xFFFF8F00);
    final bgGradient = isEnabled
        ? const LinearGradient(
            colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [Color(0xFF0D1B2A), Color(0xFF1B2838)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: bgGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentColor.withOpacity(0.18),
              ),
              padding: const EdgeInsets.all(12),
              child: Icon(
                Icons.fingerprint_rounded,
                color: accentColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEnabled ? 'Biometric Lock Active' : 'App Security',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isEnabled
                        ? 'Your app is protected'
                        : (isSupported
                              ? 'Tap to enable biometric lock'
                              : 'Not supported on this device'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.65),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                isEnabled ? 'ON' : 'OFF',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: accentColor,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
