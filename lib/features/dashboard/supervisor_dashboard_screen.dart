import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import '../calculator/average_calculator_extra_screen.dart';

import '../../core/models/app_user.dart';
import '../../core/models/advance_request.dart';
import '../../core/models/attendance_record.dart';
import '../../core/services/approvals_repository.dart';
import '../../core/services/app_update_service.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/app_loader.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/services/gps_ping_repository.dart';
import '../../core/models/supervisor_today_attendance.dart';
import '../../core/services/gps_ping_service.dart';
import '../../core/services/finance_repository.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/safety_repository.dart';
import '../../core/services/auth_storage_service.dart';
import '../../core/services/training_flag_service.dart';
import '../../core/services/biometric_unlock_service.dart';
import '../../core/widgets/profile_photo_widget.dart';
import '../../core/models/document_models.dart';
import '../../core/services/documents_repository.dart';
import '../../core/widgets/in_app_notification_banner.dart';
import '../../core/widgets/update_available_sheet.dart';
import '../../core/widgets/biometric_enable_sheet.dart';
import '../approvals/approvals_screen.dart';
import '../attendance/attendance_adjust_request_screen.dart';
import '../attendance/attendance_history_screen.dart';
import '../attendance/check_in_out_screen.dart';
import '../attendance/employee_attendance_calendar_screen.dart';
import '../finance/salary_advance_screen.dart';
import '../finance/advance_salary_screen.dart';
import '../leave/apply_leave_screen.dart';
import '../documents/personal_documents_sheet.dart';
import '../attendance/proxy_attendance_screen.dart';
import '../profile/driver_profile_screen.dart';
import '../profile/supervisor_profile_screen.dart';
import '../safety/training/training_screen.dart';
import '../settings/notification_settings_screen.dart';
import '../statistics/monthly_statistics_screen.dart';
import '../trips/trip_screen.dart';
import '../trips/trip_sheet_screen.dart';
import '../referral/referral_tracker_screen.dart';
import '../watch_ads/watch_ads_screen.dart';
import '../documents/documents_hub_screen.dart';
import '../safety/safety_hub_screen.dart';
import '../tasks/tasks_screen.dart';
import '../master/new_joining_screen.dart';
import 'driver_dashboard_screen.dart' show NotificationType;

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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const int _supervisorDocumentWarningDays = 30;
  static const String _driverDocumentsListUrl =
      'https://sstranswaysindia.com/api/mobile/driver_documents_list.php';
  static const String _getDriversUrl =
      'https://sstranswaysindia.com/api/mobile/get_drivers.php';
  final FinanceRepository _financeRepository = FinanceRepository();
  final ApprovalsRepository _approvalsRepository = ApprovalsRepository();
  final AttendanceRepository _attendanceRepository = AttendanceRepository();
  final GpsPingRepository _gpsPingRepository = GpsPingRepository();
  final DocumentsRepository _documentsRepository = DocumentsRepository();
  final AppUpdateService _appUpdateService = AppUpdateService();
  final BiometricUnlockService _biometricService = BiometricUnlockService();
  late SafetyRepository _safetyRepository;
  GpsPingService? _gpsPingService;

  late DateTime _now;
  Timer? _ticker;
  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;
  bool _checkingTraining = false;

  List<_SupervisorNotification> _systemNotifications = const [
    _SupervisorNotification(message: 'Loading...', type: NotificationType.info),
  ];
  AttendanceRecord? _latestShift;
  bool _isLoadingShift = true;
  String? _shiftSummary;
  bool _isAttendanceLockedToday = false;
  String? _appVersion;
  DocumentOverviewData? _documentsOverview;
  bool _isLoadingDocumentsOverview = false;
  String? _documentsOverviewError;
  bool _biometricEnabled = false;
  bool _biometricSupported = false;

  bool _isLoadingTodayAttendance = false;
  String? _todayAttendanceError;
  List<SupervisorTodayAttendancePlant> _todayAttendance = const [];
  final Set<int> _absenceUpdatingDriverIds = <int>{};
  bool _isLoadingMaintenanceDue = false;
  String? _maintenanceDueError;
  List<_MaintenancePlant> _maintenanceDuePlants = const [];
  int _taskCount = 0;
  bool _isLoadingTasks = false;
  bool _taskSnackShown = false;
  int _selectedTabIndex = 0;

  // ── Current Month Trips state ──
  bool _isLoadingSupervisorTrips = true;
  List<Map<String, dynamic>> _supervisorCurrentMonthTrips = [];
  List<_SupervisorDocumentAlert> _supervisorDocumentAlerts = const [];

  // ── Today Trip Status for each driver ──
  Map<int, bool> _driverTodayTripStatus = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _now = DateTime.now();
    unawaited(NotificationService().bindInboxUser(widget.user.id));
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
    _loadSupervisorTodayAttendance();
    _loadMaintenanceDue();
    _loadTaskCount();
    _loadAppVersion();
    _loadBiometricSetting();
    if (widget.user.canViewDocuments) {
      _loadDocumentsOverview();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForAppUpdate();
      _checkTrainingRequirement();
      _loadSupervisorCurrentMonthTrips();
    });

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

  Future<void> _loadTaskCount() async {
    final userId = int.tryParse(widget.user.id);
    if (userId == null) {
      setState(() => _taskCount = 0);
      return;
    }

    setState(() => _isLoadingTasks = true);
    try {
      final response = await http.post(
        Uri.parse('https://sstranswaysindia.com/api/mobile/tasks_list.php'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'limit': 20}),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final ok = response.statusCode == 200 && data['status'] == 'ok';
      if (ok) {
        final count = int.tryParse(data['count']?.toString() ?? '') ?? 0;
        if (mounted) {
          setState(() => _taskCount = count);
          if (count > 0) {
            _showPendingTasksSnack();
          } else {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          }
        }
      } else if (mounted) {
        setState(() => _taskCount = 0);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _taskCount = 0);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingTasks = false);
      }
    }
  }

  Future<void> _loadMaintenanceDue({bool silent = false}) async {
    final plantIds = _resolveMaintenancePlantIds();
    if (plantIds.isEmpty) {
      if (!mounted) return;
      setState(() {
        _maintenanceDuePlants = const [];
        _maintenanceDueError = null;
        _isLoadingMaintenanceDue = false;
      });
      return;
    }

    if (!silent) {
      setState(() {
        _isLoadingMaintenanceDue = true;
        _maintenanceDueError = null;
      });
    }

    try {
      final responses = await Future.wait(
        plantIds.map(_fetchMaintenanceDueForPlant),
      );
      final merged = <_MaintenancePlant>[];
      for (final plants in responses) {
        merged.addAll(plants);
      }
      merged.sort(
        (a, b) =>
            a.plantName.toLowerCase().compareTo(b.plantName.toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _maintenanceDuePlants = merged;
        _maintenanceDueError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _maintenanceDueError =
            'Unable to load maintenance due details. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingMaintenanceDue = false);
      }
    }
  }

  Future<List<_MaintenancePlant>> _fetchMaintenanceDueForPlant(
    int plantId,
  ) async {
    final uri =
        Uri.parse(
          'https://sstranswaysindia.com/api/mobile/maintenance_due.php',
        ).replace(
          queryParameters: {
            'supervisorUserId': widget.user.id,
            'plant_id': plantId.toString(),
            'scope': 'due',
          },
        );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Maintenance due fetch failed.');
    }
    final payload =
        jsonDecode(response.body) as Map<String, dynamic>? ?? const {};
    final isOk = payload['ok'] == true || payload['status'] == 'ok';
    if (!isOk) {
      throw Exception(payload['error']?.toString() ?? 'Request failed.');
    }
    final plants = payload['plants'] as List<dynamic>? ?? const [];
    return plants
        .whereType<Map<String, dynamic>>()
        .map(_MaintenancePlant.fromJson)
        .toList(growable: false);
  }

  Set<int> _resolveMaintenancePlantIds() {
    final ids = <int>{};
    for (final plant in widget.user.supervisedPlants) {
      final rawId = plant['id'] ?? plant['plantId'] ?? plant['plant_id'];
      final id = int.tryParse(rawId?.toString() ?? '');
      if (id != null && id > 0) {
        ids.add(id);
      }
    }
    for (final rawId in widget.user.supervisedPlantIds) {
      if (rawId == null) continue;
      final id = int.tryParse(rawId.toString());
      if (id != null && id > 0) {
        ids.add(id);
      }
    }
    if (ids.isEmpty) {
      final fallbackCandidates = <String?>[
        widget.user.assignmentPlantId,
        widget.user.plantId,
        widget.user.defaultPlantId,
      ];
      for (final candidate in fallbackCandidates) {
        final id = int.tryParse(candidate ?? '');
        if (id != null && id > 0) {
          ids.add(id);
          break;
        }
      }
    }
    return ids;
  }

  void _showPendingTasksSnack() {
    if (!mounted) return;
    if (_taskSnackShown) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _taskSnackShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) => TasksScreen(user: widget.user),
                    ),
                  )
                  .then((_) => _loadTaskCount());
            },
            child: Row(
              children: [
                const Icon(Icons.task_alt, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You have $_taskCount pending tasks. Tap to open.',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
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
  void dispose() {
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
      unawaited(_loadSupervisorDocumentAlertForPlants(_todayAttendance));
      _checkForAppUpdate();
      _checkTrainingRequirement();
      _taskSnackShown = false;
      _loadTaskCount();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _gpsPingService?.stop();
    }
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

  Future<void> _showNotificationDetails(_SupervisorNotification item) {
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

  String _resolveNotificationMessage(_SupervisorNotification item) {
    if (item.message.trim().isNotEmpty) {
      return item.message;
    }
    return 'Notification received.';
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
      if (items.isEmpty) {
        items.add(
          const _SupervisorNotification(
            message: 'No dashboard alerts right now.',
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

  Future<void> _openEmployeeCalendar(
    SupervisorTodayAttendanceDriver driver,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmployeeAttendanceCalendarScreen(
          driverId: driver.driverId.toString(),
          driverName: driver.driverName,
        ),
      ),
    );
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
      final filtered = _filterTodayAttendance(response);
      if (!mounted) return;
      setState(() {
        _todayAttendance = filtered;
        _todayAttendanceError = null;
        _absenceUpdatingDriverIds.clear();
      });
      unawaited(_loadSupervisorDocumentAlertForPlants(filtered));
      // Load today's trip status for all drivers
      _loadDriversTodayTripStatus(filtered);
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

  // ── Load today's trip status for all drivers in attendance ──
  Future<void> _loadDriversTodayTripStatus(
    List<SupervisorTodayAttendancePlant> plants,
  ) async {
    // Collect all driver IDs
    final allDriverIds = <int>[];
    for (final plant in plants) {
      for (final driver in plant.drivers) {
        if (!allDriverIds.contains(driver.driverId)) {
          allDriverIds.add(driver.driverId);
        }
      }
    }
    if (allDriverIds.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse(
          'https://sstranswaysindia.com/api/mobile/drivers_today_trip_status.php',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'driverIds': allDriverIds}),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'ok') {
          final tripStatusRaw = data['tripStatus'];
          final statusMap = <int, bool>{};
          if (tripStatusRaw is Map) {
            for (final entry in tripStatusRaw.entries) {
              final id = int.tryParse(entry.key.toString());
              if (id != null) {
                statusMap[id] = entry.value == true;
              }
            }
          }
          setState(() {
            _driverTodayTripStatus = statusMap;
          });
        }
      }
    } catch (_) {
      // Silently fail — trip status is non-critical
    }
  }

  Future<void> _loadSupervisorDocumentAlertForPlants(
    List<SupervisorTodayAttendancePlant> plants,
  ) async {
    final driverRefs = await _resolveSupervisorDriverRefs(plants);

    if (driverRefs.isEmpty) {
      if (!mounted) return;
      setState(() => _supervisorDocumentAlerts = const []);
      return;
    }

    try {
      final candidateLists = await Future.wait(
        driverRefs.values.map((ref) async {
          final response = await http.post(
            Uri.parse(_driverDocumentsListUrl),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'driverId': ref.driverId}),
          );
          final body = utf8.decode(response.bodyBytes);
          final payload = jsonDecode(body) as Map<String, dynamic>? ?? const {};
          if (response.statusCode != 200 || payload['status'] != 'ok') {
            return const <_SupervisorDriverDocumentCandidate>[];
          }
          final documents = (payload['documents'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
          final candidates = <_SupervisorDriverDocumentCandidate>[];
          for (final document in documents) {
            final rawExpiry = (document['expiry_date'] ?? '').toString().trim();
            if (rawExpiry.isEmpty || rawExpiry == '0000-00-00') {
              continue;
            }
            final expiry = DateTime.tryParse(rawExpiry);
            if (expiry == null) {
              continue;
            }
            final documentName =
                (document['document_name'] ??
                        document['document_type'] ??
                        'Document')
                    .toString()
                    .trim();
            candidates.add(
              _SupervisorDriverDocumentCandidate(
                driverId: ref.driverId,
                driverName: ref.driverName,
                plantName: ref.plantName,
                documentName: _normalizeSupervisorAlertDocumentName(
                  documentName,
                  ref.driverName,
                ),
                expiryDate: expiry,
              ),
            );
          }
          return candidates;
        }),
      );

      final alerts = _buildSupervisorDocumentAlertsFromCandidates(
        candidateLists.expand((items) => items).toList(growable: false),
      );
      if (!mounted) return;
      setState(() => _supervisorDocumentAlerts = alerts);
    } catch (_) {
      // Best-effort only; keep the current UI unchanged on fetch failure.
    }
  }

  Future<Map<int, _SupervisorDriverRef>> _resolveSupervisorDriverRefs(
    List<SupervisorTodayAttendancePlant> plants,
  ) async {
    final driverRefs = <int, _SupervisorDriverRef>{};

    for (final plant in plants) {
      for (final driver in plant.drivers) {
        if (driver.driverId <= 0) continue;
        driverRefs.putIfAbsent(
          driver.driverId,
          () => _SupervisorDriverRef(
            driverId: driver.driverId,
            driverName: driver.driverName,
            plantName: plant.plantName,
          ),
        );
      }
    }

    final supervisedPlantNames = widget.user.supervisedPlants
        .map(
          (plant) => _normalizeSupervisorPlantName(
            plant['plant_name']?.toString() ??
                plant['plantName']?.toString() ??
                plant['name']?.toString() ??
                plant['plant']?.toString() ??
                '',
          ),
        )
        .where((name) => name.isNotEmpty)
        .toSet();

    if (supervisedPlantNames.isEmpty) {
      return driverRefs;
    }

    try {
      final response = await http.get(Uri.parse(_getDriversUrl));
      final body = utf8.decode(response.bodyBytes);
      final payload = jsonDecode(body) as Map<String, dynamic>? ?? const {};
      if (response.statusCode != 200 || payload['status'] != 'ok') {
        return driverRefs;
      }

      final drivers = (payload['drivers'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>();
      for (final driver in drivers) {
        final driverId = int.tryParse(driver['id']?.toString() ?? '');
        if (driverId == null || driverId <= 0) {
          continue;
        }
        final plantName = (driver['plant'] ?? '').toString().trim();
        if (!supervisedPlantNames.contains(
          _normalizeSupervisorPlantName(plantName),
        )) {
          continue;
        }
        final driverName = (driver['name'] ?? '').toString().trim();
        if (driverName.isEmpty) {
          continue;
        }
        driverRefs.putIfAbsent(
          driverId,
          () => _SupervisorDriverRef(
            driverId: driverId,
            driverName: driverName,
            plantName: plantName,
          ),
        );
      }
    } catch (_) {
      // Keep attendance-based fallback data if the broader driver list fails.
    }

    return driverRefs;
  }

  String _normalizeSupervisorPlantName(String rawName) {
    return rawName.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeSupervisorAlertDocumentName(
    String rawName,
    String driverName,
  ) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) {
      return 'Document';
    }

    final normalizedDriverName = driverName.trim();
    if (normalizedDriverName.isEmpty) {
      return trimmed;
    }

    final lowerName = trimmed.toLowerCase();
    final lowerDriverName = normalizedDriverName.toLowerCase();
    final dashedPrefix = '$lowerDriverName - ';
    final colonPrefix = '$lowerDriverName: ';
    if (lowerName.startsWith(dashedPrefix)) {
      return trimmed.substring(normalizedDriverName.length + 3).trim();
    }
    if (lowerName.startsWith(colonPrefix)) {
      return trimmed.substring(normalizedDriverName.length + 2).trim();
    }
    return trimmed;
  }

  List<_SupervisorDocumentAlert> _buildSupervisorDocumentAlertsFromCandidates(
    List<_SupervisorDriverDocumentCandidate> candidates,
  ) {
    if (candidates.isEmpty) {
      return const [];
    }

    final today = DateUtils.dateOnly(DateTime.now());
    final relevantCandidates = <_SupervisorDriverDocumentCandidate>[];
    final seenKeys = <String>{};

    for (final candidate in candidates) {
      final daysUntilExpiry = DateUtils.dateOnly(
        candidate.expiryDate,
      ).difference(today).inDays;
      if (daysUntilExpiry > _supervisorDocumentWarningDays) {
        continue;
      }
      final dedupeKey = [
        candidate.driverId,
        candidate.documentName.toLowerCase(),
        candidate.expiryDate.toIso8601String(),
      ].join('|');
      if (seenKeys.add(dedupeKey)) {
        relevantCandidates.add(candidate);
      }
    }

    relevantCandidates.sort((a, b) {
      final aDays = DateUtils.dateOnly(a.expiryDate).difference(today).inDays;
      final bDays = DateUtils.dateOnly(b.expiryDate).difference(today).inDays;
      final expiredCompare = (aDays < 0 ? 0 : 1).compareTo(bDays < 0 ? 0 : 1);
      if (expiredCompare != 0) {
        return expiredCompare;
      }
      final dayCompare = aDays.compareTo(bDays);
      if (dayCompare != 0) {
        return dayCompare;
      }
      final driverCompare = a.driverName.toLowerCase().compareTo(
        b.driverName.toLowerCase(),
      );
      if (driverCompare != 0) {
        return driverCompare;
      }
      return a.documentName.toLowerCase().compareTo(b.documentName.toLowerCase());
    });

    return relevantCandidates.map((candidate) {
      final daysUntilExpiry = DateUtils.dateOnly(
        candidate.expiryDate,
      ).difference(today).inDays;
      final isExpired = daysUntilExpiry < 0;
      return _SupervisorDocumentAlert(
        title: '${candidate.driverName} - ${candidate.documentName}',
        statusText: isExpired
            ? 'Expired (Expired: ${DateFormat('dd MMM yy').format(candidate.expiryDate)})'
            : 'Due in $daysUntilExpiry ${daysUntilExpiry == 1 ? 'day' : 'days'} (Exp.: ${DateFormat('dd MMM yy').format(candidate.expiryDate)})',
        icon: Icons.warning_amber_rounded,
        backgroundColor: isExpired
            ? const Color(0xFFE53935)
            : const Color(0xFFFFC107),
        foregroundColor: isExpired
            ? Colors.white
            : const Color(0xFF4E342E),
        borderColor: isExpired
            ? const Color(0xFFFFCDD2)
            : const Color(0xFFFFECB3),
      );
    }).toList(growable: false);
  }

  Widget _buildSupervisorDocumentAlertBanners() {
    final alerts = _supervisorDocumentAlerts;
    if (alerts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        for (var i = 0; i < alerts.length; i++) ...[
          _buildSupervisorDocumentAlertBanner(alerts[i]),
          if (i != alerts.length - 1) const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _buildSupervisorDocumentAlertBanner(_SupervisorDocumentAlert alert) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        final pulse = ((_glowAnimation.value - 0.35) / 0.5).clamp(0.0, 1.0);
        final isExpired = alert.statusText.startsWith('Expired');
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: alert.backgroundColor.withValues(
              alpha: isExpired ? (0.48 + pulse * 0.5) : (0.56 + pulse * 0.34),
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: alert.borderColor.withValues(
                alpha: isExpired
                    ? (0.65 + pulse * 0.35)
                    : (0.58 + pulse * 0.34),
              ),
              width: isExpired ? 1.2 : 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: alert.backgroundColor.withValues(
                  alpha: isExpired
                      ? (0.24 + pulse * 0.34)
                      : (0.2 + pulse * 0.28),
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
              Icon(alert.icon, size: 14, color: alert.foregroundColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${alert.title}: ${alert.statusText}',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
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

  List<SupervisorTodayAttendancePlant> _filterTodayAttendance(
    List<SupervisorTodayAttendancePlant> source,
  ) {
    final selfDriverId = int.tryParse(widget.user.driverId ?? '');
    final filteredPlants = <SupervisorTodayAttendancePlant>[];
    for (final plant in source) {
      final isOfficePlant = plant.plantName.toLowerCase().contains('office');
      if (isOfficePlant) {
        continue;
      }
      final drivers = plant.drivers
          .where((driver) {
            if (selfDriverId != null &&
                selfDriverId > 0 &&
                driver.driverId == selfDriverId) {
              return false;
            }
            return true;
          })
          .toList(growable: false);
      if (drivers.isNotEmpty) {
        filteredPlants.add(plant.copyWith(drivers: drivers));
      }
    }
    return filteredPlants;
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

  List<SupervisorTodayAttendancePlant> _updateDriverAbsenceState({
    required int plantId,
    required int driverId,
    required bool isAbsent,
  }) {
    return _todayAttendance
        .map(
          (plant) => plant.plantId != plantId
              ? plant
              : plant.copyWith(
                  drivers: plant.drivers
                      .map(
                        (driver) => driver.driverId == driverId
                            ? driver.copyWith(isAbsent: isAbsent)
                            : driver,
                      )
                      .toList(growable: false),
                ),
        )
        .toList(growable: false);
  }

  Future<void> _toggleDriverAbsence({
    required SupervisorTodayAttendancePlant plant,
    required SupervisorTodayAttendanceDriver driver,
    required bool markAbsent,
  }) async {
    final driverId = driver.driverId;
    setState(() {
      _absenceUpdatingDriverIds.add(driverId);
      _todayAttendance = _updateDriverAbsenceState(
        plantId: plant.plantId,
        driverId: driverId,
        isAbsent: markAbsent,
      );
    });

    try {
      final confirmed = await _attendanceRepository.updateSupervisorAbsent(
        supervisorUserId: widget.user.id,
        driverId: driverId,
        plantId: plant.plantId,
        isAbsent: markAbsent,
      );
      if (!mounted) return;
      setState(() {
        _todayAttendance = _updateDriverAbsenceState(
          plantId: plant.plantId,
          driverId: driverId,
          isAbsent: confirmed,
        );
      });
      showAppToast(
        context,
        confirmed
            ? 'Marked ${driver.driverName} absent for today.'
            : 'Cleared absence for ${driver.driverName}.',
      );
    } on AttendanceFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _todayAttendance = _updateDriverAbsenceState(
          plantId: plant.plantId,
          driverId: driverId,
          isAbsent: !markAbsent,
        );
      });
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _todayAttendance = _updateDriverAbsenceState(
          plantId: plant.plantId,
          driverId: driverId,
          isAbsent: !markAbsent,
        );
      });
      showAppToast(
        context,
        'Unable to update absence status. Please try again.',
        isError: true,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _absenceUpdatingDriverIds.remove(driverId);
      });
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

  void _openAverageCalculatorExtra() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AverageCalculatorExtraScreen(),
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
      final currentMonthRecords = await _attendanceRepository.fetchHistory(
        driverId: driverId,
        month: DateTime(now.year, now.month),
      );
      final previousMonthRecords = await _attendanceRepository.fetchHistory(
        driverId: driverId,
        month: DateTime(now.year, now.month - 1),
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
    if (raw == null || raw.isEmpty) return null;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final dateFormatter = DateFormat('dd-MM-yyyy');
    final timeFormatter = DateFormat('HH:mm:ss');
    final user = widget.user;
    const navyDark = Color(0xFF0A1628);
    const navyBrand = Color(0xFF153753);
    const goldAccent = Color(0xFFD4A843);
    const surfaceBg = Color(0xFFF4F7FC);
    const cardBg = Color(0xFFFFFFFE);

    final tenureText = _tenureText();
    final tenureSubtitle = tenureText != null
        ? 'Working for $tenureText'
        : null;

    return Scaffold(
      backgroundColor: surfaceBg,
      extendBody: true,
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
                    colors: [navyDark, navyBrand],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ProfilePhotoWidget(user: user, radius: 28),
                    const SizedBox(height: 12),
                    Text(
                      user.displayName,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Supervisor',
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
                _openProfileScreen();
              }),
              _drawerTile(Icons.verified_user_outlined, 'Approvals', () {
                Navigator.of(context).pop();
                Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => ApprovalsScreen(user: widget.user),
                      ),
                    )
                    .then((_) {
                      _loadNotifications();
                      _loadSupervisorTodayAttendance(silent: true);
                    });
              }),
              _drawerTile(
                Icons.notifications_outlined,
                'Notification Settings',
                () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NotificationSettingsScreen(),
                    ),
                  );
                },
              ),
              _drawerTile(
                Icons.folder_shared_outlined,
                'Personal Documents',
                () {
                  Navigator.of(context).pop();
                  showPersonalDocumentsSheet(context, widget.user);
                },
              ),
              _drawerTile(Icons.task_alt_outlined, 'Tasks', () {
                Navigator.of(context).pop();
                Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => TasksScreen(user: widget.user),
                      ),
                    )
                    .then((_) => _loadTaskCount());
              }),
              _drawerTile(Icons.play_circle_outline, 'Watch Ads & Earn', () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => WatchAdsScreen(user: user)),
                );
              }),
              _drawerTile(Icons.card_giftcard_rounded, 'Referral Program', () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReferralTrackerScreen(user: user),
                  ),
                );
              }),
              _drawerTile(
                Icons.fingerprint_rounded,
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
                    color: navyBrand.withValues(alpha: 0.4),
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
        0 => _buildSupervisorHomeTab(
          context,
          theme: theme,
          textTheme: textTheme,
          dateFormatter: dateFormatter,
          timeFormatter: timeFormatter,
          tenureSubtitle: tenureSubtitle,
          navyDark: navyDark,
          navyBrand: navyBrand,
          goldAccent: goldAccent,
          surfaceBg: surfaceBg,
          cardBg: cardBg,
        ),
        1 => ApprovalsScreen(user: widget.user),
        2 => AdvanceSalaryScreen(user: widget.user),
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
                  color: statusColor.withValues(
                    alpha: 0.4 + _glowAnimation.value * 0.3,
                  ),
                  blurRadius: 10 + _glowAnimation.value * 12,
                  spreadRadius: 2 + _glowAnimation.value * 4,
                ),
              ],
            ),
            child: FloatingActionButton.large(
              tooltip: _attendanceButtonLabel,
              onPressed: () {
                if (_isAttendanceLockedToday &&
                    !_hasOpenShift &&
                    !_hasPastOpenShift) {
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
                Icons.verified_user_rounded,
                'Approvals',
                navyBrand,
              ),
            ),
            const SizedBox(width: 72),
            Expanded(
              child: _buildNavItem(
                2,
                Icons.account_balance_wallet_rounded,
                'Khatabook',
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

  Widget _buildSupervisorHomeTab(
    BuildContext context, {
    required ThemeData theme,
    required TextTheme textTheme,
    required DateFormat dateFormatter,
    required DateFormat timeFormatter,
    required String? tenureSubtitle,
    required Color navyDark,
    required Color navyBrand,
    required Color goldAccent,
    required Color surfaceBg,
    required Color cardBg,
  }) {
    const headerExpandedHeight = 170.0;
    final attendanceAccent = _hasOpenShift
        ? const Color(0xFFE0BC00)
        : _hasPastOpenShift
        ? const Color(0xFFD8B4FE)
        : _isAttendanceLockedToday
        ? const Color(0xFFB0BEC5)
        : const Color(0xFF00EB5E);
    final attendanceChipBackground = _hasOpenShift
        ? const Color(0xFFE0BC00).withValues(alpha: 0.18)
        : _hasPastOpenShift
        ? const Color(0xFFD8B4FE).withValues(alpha: 0.18)
        : _isAttendanceLockedToday
        ? const Color(0xFFB0BEC5).withValues(alpha: 0.18)
        : const Color(0xFF00EB5E).withValues(alpha: 0.16);
    final attendanceChipTextColor = _hasOpenShift
        ? const Color(0xFFFFF6CC)
        : _hasPastOpenShift
        ? const Color(0xFFF5EAFF)
        : _isAttendanceLockedToday
        ? const Color(0xFFF4F7F9)
        : const Color(0xFFEFFFEF);

    return Stack(
      children: [
        Container(color: surfaceBg),
        CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              floating: false,
              snap: false,
              backgroundColor: navyBrand,
              surfaceTintColor: Colors.transparent,
              automaticallyImplyLeading: false,
              toolbarHeight: 62,
              expandedHeight: headerExpandedHeight,
              title: _SupervisorCollapsedHeaderTitle(
                user: widget.user,
                onLogout: () {
                  widget.onLogout();
                  showAppToast(context, 'Logged out successfully');
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
                    final maxExtent =
                        settings?.maxExtent ?? headerExpandedHeight;
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
                        top: true,
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Builder(
                                          builder: (ctx) => GestureDetector(
                                            onTap: () =>
                                                Scaffold.of(ctx).openDrawer(),
                                            child: Container(
                                              padding: const EdgeInsets.all(7),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: const Icon(
                                                Icons.menu_rounded,
                                                color: Colors.white70,
                                                size: 18,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        ProfilePhotoWidget(
                                          user: widget.user,
                                          radius: 22,
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
                                                    opacity:
                                                        upperSectionVisibility,
                                                    child: Wrap(
                                                      crossAxisAlignment:
                                                          WrapCrossAlignment
                                                              .center,
                                                      spacing: 6,
                                                      runSpacing: 4,
                                                      children: [
                                                        _heroPill(
                                                          icon: Icons
                                                              .badge_outlined,
                                                          text: 'Supervisor',
                                                          color: goldAccent,
                                                          verticalPadding: 1.5,
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
                                              const SizedBox(height: 3),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: _heroActionButton(
                                            icon: Icons.badge_outlined,
                                            onPressed: _openProfileScreen,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: _heroActionButton(
                                            icon: Icons.logout_rounded,
                                            onPressed: () {
                                              widget.onLogout();
                                              showAppToast(
                                                context,
                                                'Logged out successfully',
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
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
                              const SizedBox(height: 6),
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
                                          const SizedBox(height: 0),
                                          _buildSupervisorPlantsPanel(),
                                          if (_shiftSummary != null) ...[
                                            const SizedBox(height: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: attendanceChipBackground,
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                border: Border.all(
                                                  color: attendanceAccent
                                                      .withValues(alpha: 0.42),
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
                                                        fontWeight:
                                                            FontWeight.w500,
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
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDashboardSectionHeader(
                      title: 'Quick Actions',
                      icon: Icons.grid_view_rounded,
                      navyBrand: navyBrand,
                    ),
                    const SizedBox(height: 8),
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
                          gradient: const [
                            Color(0xFF6B6FEA),
                            Color(0xFF6A45B8),
                          ],
                          onTap: () => Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) => AttendanceHistoryScreen(
                                    user: widget.user,
                                  ),
                                ),
                              )
                              .then((_) {
                                _loadNotifications();
                                _loadSupervisorTodayAttendance(silent: true);
                              }),
                        ),
                        _quickActionTile(
                          icon: Icons.bar_chart_rounded,
                          label: 'Stats',
                          gradient: const [
                            Color(0xFF14B38A),
                            Color(0xFF37E07D),
                          ],
                          onTap: () => Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) => MonthlyStatisticsScreen(
                                    user: widget.user,
                                  ),
                                ),
                              )
                              .then((_) {
                                _loadNotifications();
                                _loadSupervisorTodayAttendance(silent: true);
                              }),
                        ),
                        _quickActionTile(
                          icon: Icons.beach_access_rounded,
                          label: 'Leave',
                          gradient: const [
                            Color(0xFFFF9800),
                            Color(0xFFFFC107),
                          ],
                          onTap: () => showApplyLeaveSheet(context, widget.user)
                              .then((_) {
                                _loadNotifications();
                                _loadSupervisorTodayAttendance(silent: true);
                              }),
                        ),
                        _quickActionTile(
                          icon: Icons.payments_rounded,
                          label: 'Salary',
                          gradient: const [
                            Color(0xFF2E7D32),
                            Color(0xFF4CAF50),
                          ],
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
                        _quickActionTile(
                          icon: Icons.account_balance_wallet_rounded,
                          label: 'Khata',
                          gradient: const [
                            Color(0xFF091B31),
                            Color(0xFF16395D),
                          ],
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
                        _quickActionTile(
                          icon: Icons.local_shipping_rounded,
                          label: 'Trips',
                          gradient: const [
                            Color(0xFF9337CF),
                            Color(0xFFB25DDD),
                          ],
                          onTap: () => Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) => TripScreen(user: widget.user),
                                ),
                              )
                              .then((_) {
                                _loadNotifications();
                                _loadSupervisorTodayAttendance(silent: true);
                                _loadSupervisorCurrentMonthTrips();
                              }),
                        ),
                        _quickActionTile(
                          icon: Icons.description_rounded,
                          label: 'Trip Sheet',
                          gradient: const [
                            Color(0xFF1976D2),
                            Color(0xFF42A5F5),
                          ],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  TripSheetScreen(user: widget.user),
                            ),
                          ),
                        ),
                        _quickActionTile(
                          icon: Icons.security_rounded,
                          label: 'Safety',
                          gradient: const [
                            Color(0xFFFF5032),
                            Color(0xFFFF6D48),
                          ],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  SafetyHubScreen(user: widget.user),
                            ),
                          ),
                        ),
                        if (_isLoadingTasks || _taskCount > 0)
                          _quickActionTile(
                            icon: Icons.task_alt_rounded,
                            label: 'Tasks',
                            gradient: const [
                              Color(0xFF8E2CD1),
                              Color(0xFFB23FE1),
                            ],
                            statusWidget: _isLoadingTasks
                                ? Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    padding: const EdgeInsets.all(5),
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 1.8,
                                    ),
                                  )
                                : Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF1F2),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFFFD4D8),
                                      ),
                                    ),
                                    child: Text(
                                      _taskCount.toString(),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFFD62839),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                            onTap: () => Navigator.of(context)
                                .push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        TasksScreen(user: widget.user),
                                  ),
                                )
                                .then((_) => _loadTaskCount()),
                          ),
                        if (widget.user.canViewDocuments)
                          _quickActionTile(
                            icon: Icons.description_outlined,
                            label: 'Docs',
                            gradient: const [
                              Color(0xFF13938D),
                              Color(0xFF37B8A7),
                            ],
                            onTap: () {
                              if (_isLoadingDocumentsOverview &&
                                  _documentsOverview == null) {
                                _loadDocumentsOverview();
                                return;
                              }
                              _openDocumentsHub();
                            },
                          ),
                        _quickActionTile(
                          icon: Icons.edit_calendar_rounded,
                          label: 'Adjust',
                          gradient: const [
                            Color(0xFFFF4F9B),
                            Color(0xFFF06292),
                          ],
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
                        _quickActionTile(
                          icon: Icons.card_giftcard_rounded,
                          label: 'Refer',
                          gradient: const [
                            Color(0xFF1976D2),
                            Color(0xFF3C8CE7),
                          ],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ReferralTrackerScreen(user: widget.user),
                            ),
                          ),
                        ),
                        _quickActionTile(
                          icon: Icons.calculate_rounded,
                          label: 'Calc',
                          gradient: const [
                            Color(0xFF6B8390),
                            Color(0xFF8CA0A9),
                          ],
                          onTap: _openAverageCalculatorExtra,
                        ),
                        _quickActionTile(
                          icon: Icons.person_add_alt_1_rounded,
                          label: 'New Joining',
                          gradient: const [
                            Color(0xFF2C73E8),
                            Color(0xFF5C99FF),
                          ],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  NewJoiningScreen(user: widget.user),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_supervisorDocumentAlerts.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Transform.translate(
                        offset: const Offset(0, -8),
                        child: _buildSupervisorDocumentAlertBanners(),
                      ),
                    ],
                    if (_shouldShowMaintenanceDueSection) ...[
                      const SizedBox(height: 8),
                      _buildSectionHeaderRow(
                        title: 'Maintenance Due',
                        icon: Icons.build_circle_rounded,
                        navyBrand: navyBrand,
                        action: IconButton(
                          tooltip: 'Refresh',
                          icon: const Icon(Icons.refresh_rounded, size: 22),
                          color: navyBrand.withValues(alpha: 0.55),
                          onPressed: _isLoadingMaintenanceDue
                              ? null
                              : () => _loadMaintenanceDue(),
                        ),
                      ),
                      const SizedBox(height: 1),
                      _buildMaintenanceDueSection(theme),
                      const SizedBox(height: 8),
                    ],
                    _buildSectionHeaderRow(
                      title: 'Today Attendance',
                      icon: Icons.groups_rounded,
                      navyBrand: navyBrand,
                      action: IconButton(
                        tooltip: 'Refresh',
                        icon: const Icon(Icons.refresh_rounded, size: 22),
                        color: navyBrand.withValues(alpha: 0.55),
                        onPressed: _isLoadingTodayAttendance
                            ? null
                            : () => _loadSupervisorTodayAttendance(),
                      ),
                    ),
                    const SizedBox(height: 1),
                    _buildTodayAttendanceSection(theme),
                    const SizedBox(height: 18),
                    _buildNotificationsCard(navyBrand, cardBg),
                    const SizedBox(height: 18),
                    _buildSupervisorTripsSection(theme, textTheme),
                    const SizedBox(height: 18),
                    _buildDashboardSectionHeader(
                      title: 'Supervised Plants',
                      icon: Icons.factory_outlined,
                      navyBrand: navyBrand,
                    ),
                    const SizedBox(height: 10),
                    _SupervisedPlantsCard(user: widget.user),
                    const SizedBox(height: 18),
                    _SupervisorBiometricCard(
                      isEnabled: _biometricEnabled,
                      isSupported: _biometricSupported,
                      onTap: _openBiometricSheet,
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: Text(
                        'Version ${_appVersion ?? '...'}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: navyBrand.withValues(alpha: 0.35),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
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

  void _openProfileScreen() {
    final profileScreen =
        widget.user.driverId != null && widget.user.driverId!.isNotEmpty
        ? DriverProfileScreen(user: widget.user)
        : SupervisorProfileScreen(user: widget.user);
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => profileScreen));
  }

  List<String> _supervisedPlantLabels() {
    final labels = <String>{};
    for (final plant in widget.user.supervisedPlants) {
      final name =
          plant['plant_name']?.toString() ??
          plant['plantName']?.toString() ??
          plant['name']?.toString();
      final normalized = name?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        labels.add(normalized.toUpperCase());
      }
    }

    final fallbackNames = <String?>[
      widget.user.assignmentPlantName,
      widget.user.plantName,
      widget.user.defaultPlantName,
    ];
    for (final fallback in fallbackNames) {
      final normalized = fallback?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        labels.add(normalized.toUpperCase());
      }
    }

    return labels.toList(growable: false);
  }

  Widget _buildAlertsFab(Color navyBrand) {
    final alertCount = _systemNotifications
        .where((item) => !item.isPlaceholder)
        .length;
    final firstActionableNotification = _systemNotifications
        .cast<_SupervisorNotification?>()
        .firstWhere(
          (item) => item != null && !item.isPlaceholder,
          orElse: () => _systemNotifications.isNotEmpty
              ? _systemNotifications.first
              : null,
        );

    return GestureDetector(
      onTap: () {
        if (firstActionableNotification != null) {
          _showNotificationDetails(firstActionableNotification);
        }
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: navyBrand.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              color: navyBrand,
              size: 28,
            ),
          ),
          if (alertCount > 0)
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xFFD62839),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  alertCount > 9 ? '9+' : '$alertCount',
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
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

  Widget _heroActionButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    final buttonSize = kIsWeb ? 34.0 : 28.0;
    final iconSize = kIsWeb ? 18.0 : 14.0;
    final radius = kIsWeb ? 12.0 : 10.0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white70, size: iconSize),
        constraints: BoxConstraints.tightFor(
          width: buttonSize,
          height: buttonSize,
        ),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildSupervisorPlantsPanel() {
    final plantLabels = _supervisedPlantLabels();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.factory_outlined,
              size: 14,
              color: Colors.white70,
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: plantLabels.isEmpty
                  ? [
                      _buildPlantChip(
                        label: 'UNASSIGNED',
                        background: Colors.white.withValues(alpha: 0.1),
                      ),
                    ]
                  : plantLabels
                        .map(
                          (label) => _buildPlantChip(
                            label: label,
                            background: Colors.white.withValues(alpha: 0.1),
                          ),
                        )
                        .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlantChip({required String label, required Color background}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: 0.2,
          height: 1,
        ),
      ),
    );
  }

  Widget _heroPill({
    required IconData icon,
    required String text,
    required Color color,
    double verticalPadding = 3,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7, vertical: verticalPadding),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionTile({
    required IconData icon,
    required String label,
    required List<Color> gradient,
    VoidCallback? onTap,
    Widget? statusWidget,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 3,
                    top: 3,
                    child: Container(
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
                            color: gradient.first.withValues(alpha: 0.26),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(icon, color: Colors.white, size: 32),
                    ),
                  ),
                  if (statusWidget != null)
                    Positioned(top: 0, right: 0, child: statusWidget),
                ],
              ),
            ),
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
      ),
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

  Widget _buildSectionHeaderRow({
    required String title,
    required IconData icon,
    required Color navyBrand,
    Widget? action,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildDashboardSectionHeader(
            title: title,
            icon: icon,
            navyBrand: navyBrand,
          ),
        ),
        if (action != null) action,
      ],
    );
  }

  Widget _buildNotificationsCard(Color navyBrand, Color cardBg) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: navyBrand.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: navyBrand.withValues(alpha: 0.04),
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
                        color: _notificationColor(notif.type),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        notif.message,
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: navyBrand.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: navyBrand.withValues(alpha: 0.3),
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

  Widget _buildDriversOnTripSection(ThemeData theme, TextTheme textTheme) {
    // Collect drivers who have trips this month
    final driversOnTrip = <({String name, String plant, String role})>[];
    for (final plant in _todayAttendance) {
      for (final driver in plant.drivers) {
        if (_driverTodayTripStatus[driver.driverId] == true) {
          driversOnTrip.add((
            name: driver.driverName,
            plant: plant.plantName,
            role: driver.roleBadge,
          ));
        }
      }
    }

    // Don't show section if no drivers have trips or data hasn't loaded
    if (driversOnTrip.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.local_shipping, size: 20, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Text(
              'Drivers on Trip (${driversOnTrip.length})',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                for (int i = 0; i < driversOnTrip.length; i++) ...[
                  if (i > 0) const Divider(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Icon(
                          Icons.local_shipping,
                          size: 18,
                          color: Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              driversOnTrip[i].name,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              driversOnTrip[i].plant,
                              style: textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Text(
                          driversOnTrip[i].role == 'D'
                              ? 'Driver'
                              : driversOnTrip[i].role == 'H'
                              ? 'Helper'
                              : 'Supervisor',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTodayAttendanceSection(ThemeData theme) {
    if (_isLoadingTodayAttendance && _todayAttendance.isEmpty) {
      return const Center(child: AppLoader());
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
          child: SizedBox(height: 18, width: 18, child: AppLoader(size: 18)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items,
    );
  }

  Widget _buildMaintenanceDueSection(ThemeData theme) {
    if (_isLoadingMaintenanceDue && _maintenanceDuePlants.isEmpty) {
      return const Center(child: AppLoader());
    }

    if (_maintenanceDueError != null && _maintenanceDuePlants.isEmpty) {
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
                _maintenanceDueError!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _isLoadingMaintenanceDue
                    ? null
                    : () => _loadMaintenanceDue(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final vehiclesCount = _maintenanceDuePlants.fold<int>(
      0,
      (sum, plant) => sum + plant.vehicles.length,
    );

    if (vehiclesCount == 0) {
      return const SizedBox.shrink();
    }

    final cards = <Widget>[];
    for (final plant in _maintenanceDuePlants) {
      if (plant.vehicles.isEmpty) {
        continue;
      }
      cards.add(_buildMaintenancePlantCard(theme, plant));
    }

    if (_isLoadingMaintenanceDue && _maintenanceDuePlants.isNotEmpty) {
      cards.insert(
        0,
        const Align(
          alignment: Alignment.centerRight,
          child: SizedBox(height: 18, width: 18, child: AppLoader(size: 18)),
        ),
      );
    }

    return Column(children: cards);
  }

  bool get _shouldShowMaintenanceDueSection {
    if (_isLoadingMaintenanceDue) {
      return true;
    }
    if (_maintenanceDueError != null) {
      return true;
    }
    return _maintenanceDuePlants.any((plant) => plant.vehicles.isNotEmpty);
  }

  Widget _buildMaintenancePlantCard(ThemeData theme, _MaintenancePlant plant) {
    return Card(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.build_circle, color: Colors.black, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${plant.plantName} (${plant.vehicles.length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            if (plant.location.isNotEmpty) ...[
              const SizedBox(height: 1),
              Text(
                plant.location,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontSize: 11,
                ),
              ),
            ],
            const SizedBox(height: 6),
            ...plant.vehicles.map(
              (vehicle) => _buildMaintenanceVehicleTile(theme, vehicle),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaintenanceVehicleTile(
    ThemeData theme,
    _MaintenanceVehicle vehicle,
  ) {
    final severityColor = _maintenanceSeverityColor(
      theme,
      vehicle.overallSeverity,
    );
    final isExpiredVehicle =
        vehicle.overallSeverity.toLowerCase() == 'overdue' ||
        vehicle.overallLabel.toLowerCase() == 'expired';
    final isDueSoonVehicle =
        !isExpiredVehicle &&
        (vehicle.overallSeverity.toLowerCase() == 'due_soon' ||
            vehicle.overallLabel.toLowerCase() == 'due soon');
    final dueItems = vehicle.dueItems;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: severityColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: severityColor.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  vehicle.currentKm != null
                      ? '${vehicle.vehicleNo} • C.KM ${_formatKm(vehicle.currentKm!)}'
                      : vehicle.vehicleNo,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1,
                  ),
                ),
              ),
              if (isExpiredVehicle || isDueSoonVehicle)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: OverflowBox(
                      alignment: Alignment.centerRight,
                      minWidth: 0,
                      minHeight: 0,
                      maxWidth: 44,
                      maxHeight: 44,
                      child: Image.asset(
                        isExpiredVehicle
                            ? 'assets/images/maintenance_expired.gif'
                            : 'assets/images/maintenance_due.gif',
                        width: 44,
                        height: 44,
                        filterQuality: FilterQuality.none,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                )
              else
                _MaintenanceSeverityChip(
                  label: vehicle.overallLabel,
                  color: severityColor,
                ),
            ],
          ),
          if (dueItems.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...dueItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: _buildMaintenanceItemRow(theme, item),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMaintenanceItemRow(ThemeData theme, _MaintenanceDueItem item) {
    final severityColor = _maintenanceSeverityColor(theme, item.severity);
    final kmLabel = item.kmLabel?.trim();
    final dateLabel = item.dateLabel?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 1),
        Wrap(
          spacing: 6,
          runSpacing: 3,
          children: [
            if (kmLabel != null && kmLabel.isNotEmpty && kmLabel != '—')
              _MaintenanceMetaChip(label: 'KM: $kmLabel', color: severityColor),
            if (dateLabel != null && dateLabel.isNotEmpty && dateLabel != '—')
              _MaintenanceMetaChip(
                label: 'Date: $dateLabel',
                color: severityColor,
              ),
          ],
        ),
      ],
    );
  }

  Color _maintenanceSeverityColor(ThemeData theme, String severity) {
    switch (severity.toLowerCase()) {
      case 'overdue':
        return Colors.redAccent;
      case 'due_soon':
        return Colors.orange.shade700;
      case 'ok':
        return Colors.green.shade700;
      default:
        return theme.colorScheme.outline;
    }
  }

  String _formatKm(double value) {
    final formatter = NumberFormat.decimalPattern('en_IN');
    return formatter.format(value.round());
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
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.factory_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Column(
              children: plant.drivers
                  .map(
                    (driver) =>
                        _buildDriverAttendanceTile(theme, plant, driver),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverAttendanceTile(
    ThemeData theme,
    SupervisorTodayAttendancePlant plant,
    SupervisorTodayAttendanceDriver driver,
  ) {
    final hasCheckIn = driver.hasCheckIn;
    final hasCheckOut = driver.hasCheckOut;
    final hasAny = hasCheckIn || hasCheckOut;
    final isComplete = hasCheckIn && hasCheckOut;
    final isPartial = hasAny && !isComplete;
    final isAbsent = driver.isAbsent;

    final gradientColors = isAbsent
        ? const [Color(0xFF9E9E9E), Color(0xFF757575)]
        : isComplete
        ? const [Color(0xFF00D100), Color(0xFF00AA00)]
        : isPartial
        ? const [Color(0xFFFFCE55), Color(0xFFFFB347)]
        : const [Color(0xFFED1C24), Color(0xFFB3121B)];

    const primaryTextColor = Colors.black87;
    const subtleTextColor = Colors.black54;
    final isBusy = _absenceUpdatingDriverIds.contains(driver.driverId);
    final hasTripToday = _driverTodayTripStatus[driver.driverId];

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
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
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _openEmployeeCalendar(driver),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 1,
                        horizontal: 2,
                      ),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              driver.driverName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: primaryTextColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(
                            Icons.calendar_month,
                            size: 14,
                            color: primaryTextColor,
                          ),
                          if (hasTripToday != null) ...[
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: hasTripToday
                                    ? Colors.white.withOpacity(0.9)
                                    : Colors.red.shade50.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: hasTripToday
                                      ? Colors.green.shade400
                                      : Colors.red.shade300,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    hasTripToday
                                        ? Icons.local_shipping
                                        : Icons.local_shipping_outlined,
                                    size: 10,
                                    color: hasTripToday
                                        ? Colors.green.shade700
                                        : Colors.red.shade600,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    hasTripToday ? 'Trip' : 'No Trip',
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w700,
                                      color: hasTripToday
                                          ? Colors.green.shade700
                                          : Colors.red.shade600,
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
                const SizedBox(height: 2),
                Text(
                  'Status: ${isAbsent
                      ? 'Absent'
                      : hasAny
                      ? 'Done'
                      : 'Not Done'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: primaryTextColor,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                if (!isAbsent && isPartial)
                  Text(
                    'Check-out pending',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: subtleTextColor,
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                    ),
                  ),
                if (isAbsent)
                  Text(
                    'Marked absent by supervisor',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: subtleTextColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            children: [
              Switch.adaptive(
                value: isAbsent,
                onChanged: isBusy
                    ? null
                    : (value) => _toggleDriverAbsence(
                        plant: plant,
                        driver: driver,
                        markAbsent: value,
                      ),
                activeColor: const Color(0xFF1ABC9C),
                activeTrackColor: const Color(0xFF8DE3C5),
              ),
              if (isBusy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: AppLoader(size: 16),
                ),
            ],
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
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(0, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
  }

  // ── Load supervisor current month trips ──
  Future<void> _loadSupervisorCurrentMonthTrips() async {
    final driverId = widget.user.driverId;
    final userId = widget.user.id;
    if (userId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoadingSupervisorTrips = false;
          _supervisorCurrentMonthTrips = [];
        });
      }
      return;
    }

    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1);
    final to = DateTime(now.year, now.month + 1, 0);
    final fromStr = DateFormat('yyyy-MM-dd').format(from);
    final toStr = DateFormat('yyyy-MM-dd').format(to);

    try {
      final response = await http.post(
        Uri.parse(
          'https://sstranswaysindia.com/api/mobile/driver_trip_details_by_date.php',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'role': 'supervisor',
          'userId': userId,
          if (driverId != null && driverId.isNotEmpty) 'driverId': driverId,
          'from': fromStr,
          'to': toStr,
        }),
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
          allTrips.sort((a, b) {
            final aDate = (a['startDate'] ?? '') as String;
            final bDate = (b['startDate'] ?? '') as String;
            return bDate.compareTo(aDate);
          });
          setState(() {
            _supervisorCurrentMonthTrips = allTrips;
            _isLoadingSupervisorTrips = false;
          });
        } else {
          setState(() {
            _isLoadingSupervisorTrips = false;
            _supervisorCurrentMonthTrips = [];
          });
        }
      } else {
        setState(() {
          _isLoadingSupervisorTrips = false;
          _supervisorCurrentMonthTrips = [];
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingSupervisorTrips = false;
          _supervisorCurrentMonthTrips = [];
        });
      }
    }
  }

  Widget _buildSupervisorTripsSection(ThemeData theme, TextTheme textTheme) {
    final monthLabel = DateFormat('MMMM yyyy').format(DateTime.now());
    final totalTrips = _supervisorCurrentMonthTrips.length;
    int totalKm = 0;
    for (final trip in _supervisorCurrentMonthTrips) {
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
            Text(
              'Current Month Trips — $monthLabel',
              style: textTheme.titleMedium,
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () {
                setState(() => _isLoadingSupervisorTrips = true);
                _loadSupervisorCurrentMonthTrips();
              },
              tooltip: 'Refresh trips',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isLoadingSupervisorTrips)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_supervisorCurrentMonthTrips.isEmpty)
          Card(
            color: Colors.white,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.local_shipping_outlined,
                      size: 40,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No Trips Added',
                      style: textTheme.titleSmall?.copyWith(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Contact admin if you are assigned a trip',
                      style: textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
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
          // Individual trip cards (show max 10)
          ..._supervisorCurrentMonthTrips.take(10).map((trip) {
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
          if (_supervisorCurrentMonthTrips.length > 10)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TripScreen(user: widget.user),
                    ),
                  ),
                  child: Text(
                    'View all ${_supervisorCurrentMonthTrips.length} trips →',
                    style: textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ], // end of else (trips exist)
      ],
    );
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

class _MaintenancePlant {
  _MaintenancePlant({
    required this.plantId,
    required this.plantName,
    required this.location,
    required this.vehicles,
  });

  factory _MaintenancePlant.fromJson(Map<String, dynamic> json) {
    final vehicles = (json['vehicles'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_MaintenanceVehicle.fromJson)
        .toList(growable: false);
    return _MaintenancePlant(
      plantId: int.tryParse(json['plant_id']?.toString() ?? '') ?? 0,
      plantName: json['plant_name']?.toString() ?? 'Unknown Plant',
      location: json['location']?.toString() ?? '',
      vehicles: vehicles,
    );
  }

  final int plantId;
  final String plantName;
  final String location;
  final List<_MaintenanceVehicle> vehicles;
}

class _MaintenanceVehicle {
  _MaintenanceVehicle({
    required this.vehicleId,
    required this.vehicleNo,
    required this.currentKm,
    required this.overallLabel,
    required this.overallSeverity,
    required this.dueItems,
  });

  factory _MaintenanceVehicle.fromJson(Map<String, dynamic> json) {
    final overall = json['overall'] as Map<String, dynamic>? ?? const {};
    final dueItems = (json['due_items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_MaintenanceDueItem.fromJson)
        .toList(growable: false);
    return _MaintenanceVehicle(
      vehicleId: int.tryParse(json['vehicle_id']?.toString() ?? '') ?? 0,
      vehicleNo: json['vehicle_no']?.toString() ?? 'Vehicle',
      currentKm: double.tryParse(json['current_km']?.toString() ?? ''),
      overallLabel: overall['label']?.toString() ?? 'Due',
      overallSeverity: overall['severity']?.toString() ?? 'due_soon',
      dueItems: dueItems,
    );
  }

  final int vehicleId;
  final String vehicleNo;
  final double? currentKm;
  final String overallLabel;
  final String overallSeverity;
  final List<_MaintenanceDueItem> dueItems;
}

class _MaintenanceDueItem {
  _MaintenanceDueItem({
    required this.label,
    required this.severity,
    required this.kmLabel,
    required this.dateLabel,
  });

  factory _MaintenanceDueItem.fromJson(Map<String, dynamic> json) {
    final byKm = json['by_km'] as Map<String, dynamic>? ?? const {};
    final byDate = json['by_date'] as Map<String, dynamic>? ?? const {};
    return _MaintenanceDueItem(
      label: json['label']?.toString() ?? 'Service',
      severity: json['severity']?.toString() ?? 'due_soon',
      kmLabel: byKm['label']?.toString(),
      dateLabel: byDate['label']?.toString(),
    );
  }

  final String label;
  final String severity;
  final String? kmLabel;
  final String? dateLabel;
}

class _MaintenanceSeverityChip extends StatelessWidget {
  const _MaintenanceSeverityChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 10.5,
        ),
      ),
    );
  }
}

class _MaintenanceMetaChip extends StatelessWidget {
  const _MaintenanceMetaChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 10,
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
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  backgroundColor: const Color(0xFFA530EE),
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

class _SupervisorDriverRef {
  const _SupervisorDriverRef({
    required this.driverId,
    required this.driverName,
    required this.plantName,
  });

  final int driverId;
  final String driverName;
  final String plantName;
}

class _SupervisorDriverDocumentCandidate {
  const _SupervisorDriverDocumentCandidate({
    required this.driverId,
    required this.driverName,
    required this.plantName,
    required this.documentName,
    required this.expiryDate,
  });

  final int driverId;
  final String driverName;
  final String plantName;
  final String documentName;
  final DateTime expiryDate;
}

class _SupervisorDocumentAlert {
  const _SupervisorDocumentAlert({
    required this.title,
    required this.statusText,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
  });

  final String title;
  final String statusText;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
}

class _SupervisorCollapsedHeaderTitle extends StatelessWidget {
  const _SupervisorCollapsedHeaderTitle({
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
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.menu_rounded,
                color: Colors.white70,
                size: 18,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        ProfilePhotoWidget(user: user, radius: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            user.displayName,
            style: GoogleFonts.poppins(
              fontSize: 19,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: IconButton(
            onPressed: onLogout,
            icon: const Icon(
              Icons.logout_rounded,
              color: Colors.white70,
              size: 16,
            ),
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

class _SupervisorBiometricCard extends StatelessWidget {
  const _SupervisorBiometricCard({
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
