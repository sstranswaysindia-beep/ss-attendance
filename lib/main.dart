import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';

import 'core/models/app_user.dart';
import 'core/navigation/app_route_observer.dart';
import 'core/services/auth_repository.dart';
import 'core/services/auth_storage_service.dart';
import 'core/services/background_location_disclosure_service.dart';
import 'core/services/biometric_unlock_service.dart';
import 'core/services/training_flag_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/session_event_bus.dart';
import 'core/services/gps_ping_repository.dart';
import 'core/services/gps_ping_background_scheduler.dart';
import 'core/services/gps_ping_service.dart';
import 'firebase_options.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/background_location_disclosure_screen.dart';
import 'features/auth/biometric_lock_screen.dart';
import 'features/dashboard/admin_dashboard_screen.dart';
import 'features/dashboard/driver_dashboard_screen.dart';
import 'features/dashboard/supervisor_dashboard_screen.dart';
import 'features/referral/referral_entry_screen.dart';
import 'features/safety/training/training_screen.dart';
import 'core/services/safety_repository.dart';
import 'core/widgets/in_app_notification_banner.dart';
import 'core/widgets/app_loader.dart';
import 'core/widgets/location_permission_sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await initializeDateFormatting('en_IN', null);
  Intl.defaultLocale = 'en_IN';

  if (!kIsWeb) {
    await MobileAds.instance.initialize();
  }

  // Set system UI overlay style globally
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Initialize notification service
  await NotificationService().initialize();
  await GpsPingBackgroundScheduler.initialize();

  runApp(const SSTranswaysApp());
}

class SSTranswaysApp extends StatefulWidget {
  const SSTranswaysApp({super.key});

  @override
  State<SSTranswaysApp> createState() => _SSTranswaysAppState();
}

class _SSTranswaysAppState extends State<SSTranswaysApp>
    with WidgetsBindingObserver {
  AppUser? _currentUser;
  bool _isLoading = true;
  final AuthRepository _authRepository = AuthRepository();
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  bool _forcingTrainingNav = false;
  late final StreamSubscription<void> _logoutSub;
  late final StreamSubscription<GpsPingRefreshRequest> _gpsPingRefreshSub;
  final BiometricUnlockService _biometricService = BiometricUnlockService();
  final Set<String> _gpsPingRefreshInFlight = <String>{};
  bool _biometricPromptActive = false;
  bool _accessCheckInFlight = false;
  Timer? _accessCheckTimer;
  DateTime? _lastAccessCheckAt;
  DateTime? _lastBiometricUnlockAt;
  Timer? _startupTimeoutTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startupTimeoutTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    });
    _logoutSub = SessionEventBus.onLogoutRequested.listen((_) {
      _handleLogout();
    });
    _gpsPingRefreshSub = NotificationService().gpsPingRefreshRequests.listen((
      request,
    ) {
      unawaited(_handleGpsPingRefreshRequest(request));
    });
    _loadSavedUser();
    unawaited(_drainPendingGpsPingRefreshRequests());
    _startAccessCheckTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _startupTimeoutTimer?.cancel();
    _accessCheckTimer?.cancel();
    _logoutSub.cancel();
    _gpsPingRefreshSub.cancel();
    super.dispose();
  }

  Future<void> _loadSavedUser() async {
    final savedUser = await _readSavedUserBestEffort();
    if (savedUser == null) {
      if (mounted) {
        setState(() {
          _currentUser = null;
          _isLoading = false;
        });
        _startupTimeoutTimer?.cancel();
      }
      return;
    }

    if (mounted) {
      setState(() {
        _currentUser = savedUser;
        _isLoading = false;
      });
      _startupTimeoutTimer?.cancel();
      _forceTrainingIfRequired();
    }
    unawaited(_verifySavedUserAfterStartup(savedUser));
    unawaited(_runPostLoginSetup(savedUser));
  }

  Future<AppUser?> _readSavedUserBestEffort() async {
    try {
      return await AuthStorageService.getUser().timeout(
        const Duration(seconds: 4),
      );
    } catch (error, stackTrace) {
      debugPrint('SSTranswaysApp: saved user load failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  Future<void> _verifySavedUserAfterStartup(AppUser user) async {
    try {
      final allowed = await _ensureUserStillAllowed(user, force: true);
      if (!allowed) {
        debugPrint('SSTranswaysApp: saved user disabled, session cleared');
      }
    } catch (error, stackTrace) {
      debugPrint('SSTranswaysApp: saved user access check failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _handleLogin(AppUser user) {
    print('SSTranswaysApp: received login for ${user.role} ${user.id}');
    if (mounted) {
      setState(() {
        _currentUser = user;
        _isLoading = false;
      });
      _startupTimeoutTimer?.cancel();
      print('SSTranswaysApp: current user set, showing dashboard');
    }
    _forceTrainingIfRequired();
    unawaited(_saveUserBestEffort(user));
    unawaited(_runPostLoginSetup(user));
  }

  Future<void> _saveUserBestEffort(AppUser user) async {
    try {
      await AuthStorageService.saveUser(user);
    } catch (error, stackTrace) {
      print('SSTranswaysApp: local login save failed: $error');
      print(stackTrace);
    }
  }

  Future<void> _runPostLoginSetup(AppUser user) async {
    var resolvedUser = user;
    try {
      await _authRepository.syncDeviceInfo(user: user, appVariant: 'driver');
      resolvedUser = (await _mergeTrainingFlag(user)) ?? user;
      await _applyBackgroundGpsPolicy(resolvedUser);
    } catch (_) {
      resolvedUser = user;
    }
    await _saveUserBestEffort(resolvedUser);
    if (mounted && _currentUser?.id == resolvedUser.id) {
      setState(() => _currentUser = resolvedUser);
      _forceTrainingIfRequired();
    }
  }

  void _handleLogout() {
    unawaited(_clearSession());
  }

  Future<void> _clearSession() async {
    await AuthStorageService.clearUser();
    await GpsPingBackgroundScheduler.cancel();
    NotificationService().unbindInboxUser();
    if (mounted) {
      setState(() => _currentUser = null);
    }
  }

  void _startAccessCheckTimer() {
    _accessCheckTimer?.cancel();
    _accessCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_checkCurrentUserAccess());
    });
  }

  Future<bool> _ensureUserStillAllowed(
    AppUser user, {
    bool force = false,
  }) async {
    if (_accessCheckInFlight) {
      return true;
    }
    if (!force && _lastAccessCheckAt != null) {
      final elapsed = DateTime.now().difference(_lastAccessCheckAt!);
      if (elapsed < const Duration(seconds: 20)) {
        return true;
      }
    }

    _accessCheckInFlight = true;
    _lastAccessCheckAt = DateTime.now();
    try {
      final access = await _authRepository.checkSessionStatus(user: user);
      if (access.shouldLogout) {
        await _clearSession();
        return false;
      }
      return true;
    } finally {
      _accessCheckInFlight = false;
    }
  }

  Future<bool> _checkCurrentUserAccess({bool force = false}) async {
    final user = _currentUser ?? await AuthStorageService.getUser();
    if (user == null) {
      return true;
    }
    return _ensureUserStillAllowed(user, force: force);
  }

  Future<void> _drainPendingGpsPingRefreshRequests() async {
    final pending = NotificationService().takePendingGpsPingRefreshRequests();
    for (final request in pending) {
      await _handleGpsPingRefreshRequest(request);
    }
  }

  Future<void> _handleGpsPingRefreshRequest(
    GpsPingRefreshRequest request,
  ) async {
    if (_gpsPingRefreshInFlight.contains(request.requestId)) {
      return;
    }

    _gpsPingRefreshInFlight.add(request.requestId);
    try {
      final user = _currentUser ?? await AuthStorageService.getUser();
      if (user == null || !_matchesGpsPingRefreshRequest(user, request)) {
        return;
      }

      final alreadyHandled =
          await NotificationService.hasHandledGpsPingRefreshRequest(
            user.id,
            request.requestId,
          );
      if (alreadyHandled) {
        return;
      }

      final gpsPingService = GpsPingService(
        user: user,
        repository: GpsPingRepository(),
      );
      final sent = await gpsPingService.sendImmediatePing(
        source: 'mobile_fg_push',
        bypassThrottle: true,
      );
      if (sent) {
        await NotificationService.markGpsPingRefreshRequestHandled(
          user.id,
          request.requestId,
        );
      }
    } finally {
      _gpsPingRefreshInFlight.remove(request.requestId);
    }
  }

  bool _matchesGpsPingRefreshRequest(
    AppUser user,
    GpsPingRefreshRequest request,
  ) {
    return NotificationService.matchesGpsPingRefreshRequest(user, request);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      final allowed = await _checkCurrentUserAccess(force: true);
      if (!allowed) return;
      await NotificationService().hydratePendingGpsPingRefreshRequests();
      await _drainPendingGpsPingRefreshRequests();
      await _maybePromptBiometricUnlock();
      await _refreshTrainingRequirement();
      _forceTrainingIfRequired();
    }
  }

  Future<void> _maybePromptBiometricUnlock() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    if (_currentUser == null) return;
    if (BiometricUnlockService.isPromptTemporarilySuppressed) return;
    if (_biometricPromptActive) return;
    if (_lastBiometricUnlockAt != null) {
      final elapsed = DateTime.now().difference(_lastBiometricUnlockAt!);
      if (elapsed < const Duration(seconds: 3)) return;
    }

    final enabled = await _biometricService.isEnabledForUser(_currentUser!.id);
    if (!enabled) return;
    final supported = await _biometricService.isSupported();
    if (!supported) {
      await _biometricService.setEnabledForUser(_currentUser!.id, false);
      return;
    }

    _biometricPromptActive = true;
    final navigator = _navKey.currentState;
    if (navigator == null) {
      _biometricPromptActive = false;
      return;
    }

    final unlocked = await navigator.push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BiometricLockScreen(service: _biometricService),
      ),
    );
    if (unlocked == true) {
      _lastBiometricUnlockAt = DateTime.now();
    }

    _biometricPromptActive = false;
  }

  Future<void> _refreshTrainingRequirement() async {
    if (_currentUser == null) return;
    final merged = await _mergeTrainingFlag(_currentUser);
    if (!mounted) return;
    if (merged != null && merged != _currentUser) {
      setState(() => _currentUser = merged);
    }
  }

  Future<void> _applyBackgroundGpsPolicy(AppUser? user) async {
    final allowed = await _ensureBackgroundLocationConsentAndPermission(user);
    if (allowed) {
      await GpsPingBackgroundScheduler.scheduleForUser(user);
      return;
    }
    await GpsPingBackgroundScheduler.cancel();
  }

  Future<bool> _ensureBackgroundLocationConsentAndPermission(
    AppUser? user,
  ) async {
    if (user == null ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    final driverId = user.driverId;
    if (driverId == null || driverId.isEmpty) {
      return false;
    }

    final alreadyAccepted =
        await BackgroundLocationDisclosureService.isAccepted();
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always && alreadyAccepted) {
      return true;
    }

    if (!alreadyAccepted) {
      final navigator = await _waitForNavigatorState();
      if (!mounted || navigator == null) {
        return false;
      }
      final accepted = await navigator.push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const BackgroundLocationDisclosureScreen(),
        ),
      );
      if (accepted != true) {
        return false;
      }
      await BackgroundLocationDisclosureService.markAccepted();
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.always) {
      return true;
    }

    final navigator = await _waitForNavigatorState();
    if (!mounted || navigator == null) {
      return false;
    }

    // Show the premium bottom-sheet permission prompt
    final granted = await LocationPermissionSheet.show(navigator.context);
    if (granted) {
      return true;
    }

    // Re-check in case the user toggled the permission in settings
    permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always;
  }

  Future<NavigatorState?> _waitForNavigatorState() async {
    for (var i = 0; i < 25; i++) {
      final nav = _navKey.currentState;
      if (nav != null) return nav;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return null;
  }

  Future<AppUser?> _mergeTrainingFlag(AppUser? user) async {
    if (user == null) return null;
    final override = await TrainingFlagService.isTrainingRequiredOverride();
    final serverNeedsTraining = await _fetchTrainingNeedFromServer(user);
    // Effective flag: server flag OR local override.
    final needsTraining = override || serverNeedsTraining;
    if (needsTraining == user.trainingRequired) return user;
    final updated = _cloneWithTrainingRequired(user, needsTraining);
    await AuthStorageService.updateUser(updated);
    return updated;
  }

  void _forceTrainingIfRequired() {
    if (_forcingTrainingNav) return;
    if (_currentUser == null) return;
    if (!_currentUser!.trainingRequired) return;
    final nav = _navKey.currentState;
    if (nav == null) return;
    _forcingTrainingNav = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _forcingTrainingNav = false;
        return;
      }
      // If training no longer required, do nothing (normal flow)
      if (!_currentUser!.trainingRequired) {
        _forcingTrainingNav = false;
        return;
      }
      // Force training when required
      nav.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => SafetyTrainingScreen(
            user: _currentUser!,
            repository: SafetyRepository(currentUser: _currentUser),
          ),
        ),
        (route) => false,
      );
      _forcingTrainingNav = false;
    });
  }

  AppUser _cloneWithTrainingRequired(AppUser user, bool trainingRequired) {
    return AppUser(
      id: user.id,
      displayName: user.displayName,
      role: user.role,
      username: user.username,
      employeeId: user.employeeId,
      driverId: user.driverId,
      plantId: user.plantId,
      plantName: user.plantName,
      defaultPlantId: user.defaultPlantId,
      defaultPlantName: user.defaultPlantName,
      assignmentId: user.assignmentId,
      assignmentPlantId: user.assignmentPlantId,
      assignmentPlantName: user.assignmentPlantName,
      assignmentVehicleId: user.assignmentVehicleId,
      assignmentVehicleNumber: user.assignmentVehicleNumber,
      salary: user.salary,
      profilePhoto: user.profilePhoto,
      aadhaar: user.aadhaar,
      contactNumber: user.contactNumber,
      esiNumber: user.esiNumber,
      uanNumber: user.uanNumber,
      ifscCode: user.ifscCode,
      ifscVerified: user.ifscVerified,
      bankAccount: user.bankAccount,
      branchName: user.branchName,
      fatherName: user.fatherName,
      address: user.address,
      dlNumber: user.dlNumber,
      dlValidity: user.dlValidity,
      dlIssueDate: user.dlIssueDate,
      nomineeName: user.nomineeName,
      nomineeRelation: user.nomineeRelation,
      nomineeContact: user.nomineeContact,
      vehicleNumber: user.vehicleNumber,
      driverRole: user.driverRole,
      availableVehicles: user.availableVehicles,
      joiningDate: user.joiningDate,
      supervisorName: user.supervisorName,
      supervisedPlants: user.supervisedPlants,
      supervisedPlantIds: user.supervisedPlantIds,
      canViewDocuments: user.canViewDocuments,
      geofencingEnabled: user.geofencingEnabled,
      proxyEnabled: user.proxyEnabled,
      trainingRequired: trainingRequired,
      advanceEntryAllowed: user.advanceEntryAllowed,
      employeeRegEnabled: user.employeeRegEnabled,
    );
  }

  Future<bool> _fetchTrainingNeedFromServer(AppUser user) async {
    final serverFlag = await _authRepository.fetchTrainingRequired(
      userId: user.id,
      username: user.username,
    );
    return serverFlag ?? user.trainingRequired;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    final baseTheme = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      snackBarTheme: SnackBarThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    final textTheme = GoogleFonts.josefinSansTextTheme(baseTheme.textTheme);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'SS Transways India',
        navigatorKey: _navKey,
        navigatorObservers: [appRouteObserver],
        theme: baseTheme.copyWith(
          textTheme: textTheme,
          appBarTheme: baseTheme.appBarTheme.copyWith(
            titleTextStyle: textTheme.headlineSmall?.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
            systemOverlayStyle: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
            ),
            elevation: 0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
          ),
        ),
        builder: (context, child) {
          if (child == null) {
            return const SizedBox.shrink();
          }
          final mediaQuery = MediaQuery.of(context);

          // Lock text scaling, bold text, and device pixel ratio so that
          // Android system font-size / display-size / bold-text changes
          // do not affect the app layout at all.
          final fixedData = mediaQuery.copyWith(
            textScaler: const TextScaler.linear(1.0),
            boldText: false,
            devicePixelRatio: mediaQuery.devicePixelRatio.clamp(1.0, 3.5),
          );

          return MediaQuery(
            data: fixedData,
            child: InAppNotificationBannerHost(
              hideBell: _currentUser == null,
              child: child,
            ),
          );
        },
        home: _AuthRoot(
          isLoading: _isLoading,
          user: _currentUser,
          onLogin: _handleLogin,
          onLogout: _handleLogout,
        ),
      ),
    );
  }
}

class _AuthRoot extends StatelessWidget {
  const _AuthRoot({
    required this.isLoading,
    required this.user,
    required this.onLogin,
    required this.onLogout,
  });

  final bool isLoading;
  final AppUser? user;
  final void Function(AppUser user) onLogin;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: AppStartupLoader());
    }
    final currentUser = user;
    if (currentUser == null) {
      return LoginScreen(onLogin: onLogin, screenTitle: 'Login');
    }
    return _HomeSwitchboard(user: currentUser, onLogout: onLogout);
  }
}

class _HomeSwitchboard extends StatelessWidget {
  const _HomeSwitchboard({required this.user, required this.onLogout});

  final AppUser user;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    // If training is required, route user directly to the training screen
    if (user.trainingRequired) {
      return SafetyTrainingScreen(
        user: user,
        repository: SafetyRepository(currentUser: user),
      );
    }

    switch (user.role) {
      case UserRole.driver:
        return DriverDashboardScreen(user: user, onLogout: onLogout);
      case UserRole.supervisor:
        return SupervisorDashboardScreen(user: user, onLogout: onLogout);
      case UserRole.admin:
        return AdminDashboardScreen(user: user, onLogout: onLogout);
      case UserRole.referral:
        return ReferralEntryScreen(user: user, onLogout: onLogout);
    }
  }
}
