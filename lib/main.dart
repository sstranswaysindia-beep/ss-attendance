import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:async';

import 'core/models/app_user.dart';
import 'core/services/auth_repository.dart';
import 'core/services/auth_storage_service.dart';
import 'core/services/biometric_unlock_service.dart';
import 'core/services/training_flag_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/session_event_bus.dart';
import 'firebase_options.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/biometric_lock_screen.dart';
import 'features/dashboard/admin_dashboard_screen.dart';
import 'features/dashboard/driver_dashboard_screen.dart';
import 'features/dashboard/supervisor_dashboard_screen.dart';
import 'features/safety/training/training_screen.dart';
import 'core/services/safety_repository.dart';
import 'core/widgets/in_app_notification_banner.dart';
import 'core/widgets/app_loader.dart';

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
  final BiometricUnlockService _biometricService = BiometricUnlockService();
  bool _biometricPromptActive = false;
  DateTime? _lastBiometricUnlockAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _logoutSub = SessionEventBus.onLogoutRequested.listen((_) {
      _handleLogout();
    });
    _loadSavedUser();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _logoutSub.cancel();
    super.dispose();
  }

  Future<void> _loadSavedUser() async {
    try {
      final savedUser = await AuthStorageService.getUser();
      if (savedUser != null) {
        await _authRepository.syncDeviceInfo(
          user: savedUser,
          appVariant: 'driver',
        );
      }
      final mergedUser = await _mergeTrainingFlag(savedUser);
      if (mounted) {
        setState(() {
          _currentUser = mergedUser;
          _isLoading = false;
        });
        _forceTrainingIfRequired();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentUser = null;
          _isLoading = false;
        });
      }
    }
  }

  void _handleLogin(AppUser user) async {
    await _authRepository.syncDeviceInfo(user: user, appVariant: 'driver');
    final mergedUser = (await _mergeTrainingFlag(user)) ?? user;
    await AuthStorageService.saveUser(mergedUser);
    if (mounted) {
      setState(() => _currentUser = mergedUser);
    }
    _forceTrainingIfRequired();
  }

  void _handleLogout() async {
    await AuthStorageService.clearUser();
    if (mounted) {
      setState(() => _currentUser = null);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
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
    final context = _navKey.currentContext;
    if (context == null) {
      _biometricPromptActive = false;
      return;
    }

    final unlocked = await Navigator.of(context).push<bool>(
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

          return MediaQuery(
            // Lock text scaling across all platforms so system display/font size
            // changes do not inflate UI text sizes.
            data: mediaQuery.copyWith(
              textScaler: const TextScaler.linear(1.0),
            ),
            child: InAppNotificationBannerHost(
              hideBell: child is _LoginRoute,
              child: child,
            ),
          );
        },
        home: _isLoading
            ? const Scaffold(body: Center(child: AppLoader()))
            : _currentUser == null
            ? _LoginRoute(
                child: LoginScreen(onLogin: _handleLogin, screenTitle: 'Login'),
              )
            : _HomeSwitchboard(user: _currentUser!, onLogout: _handleLogout),
      ),
    );
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
    }
  }
}

class _LoginRoute extends StatelessWidget {
  const _LoginRoute({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
