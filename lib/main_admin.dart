import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:firebase_core/firebase_core.dart';

import 'core/models/app_user.dart';
import 'core/navigation/app_route_observer.dart';
import 'core/services/auth_repository.dart';
import 'core/services/auth_storage_service.dart';
import 'core/services/background_location_disclosure_service.dart';
import 'core/services/notification_service.dart';
import 'firebase_options.dart';
import 'features/auth/background_location_disclosure_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/admin_dashboard_screen.dart';
import 'features/dashboard/supervisor_dashboard_screen.dart';
import 'core/widgets/in_app_notification_banner.dart';
import 'core/widgets/app_loader.dart';
import 'core/widgets/location_permission_sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await initializeDateFormatting('en_IN', null);
  Intl.defaultLocale = 'en_IN';

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  await NotificationService().initialize();

  runApp(const SSAdminApp());
}

class SSAdminApp extends StatefulWidget {
  const SSAdminApp({super.key});

  @override
  State<SSAdminApp> createState() => _SSAdminAppState();
}

class _SSAdminAppState extends State<SSAdminApp> {
  AppUser? _currentUser;
  bool _isLoading = true;
  final AuthRepository _authRepository = AuthRepository();
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  Timer? _startupTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _startupTimeoutTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    });
    _loadSavedUser();
  }

  @override
  void dispose() {
    _startupTimeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSavedUser() async {
    final savedUser = await _readSavedUserBestEffort();
    if (mounted) {
      setState(() {
        _currentUser = savedUser;
        _isLoading = false;
      });
      _startupTimeoutTimer?.cancel();
    }
    if (savedUser == null) {
      return;
    }
    unawaited(_runPostLoginSetup(savedUser));
  }

  Future<AppUser?> _readSavedUserBestEffort() async {
    try {
      return await AuthStorageService.getUser().timeout(
        const Duration(seconds: 4),
      );
    } catch (error, stackTrace) {
      debugPrint('SSAdminApp: saved user load failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  void _handleLogin(AppUser user) {
    print('SSAdminApp: received login for ${user.role} ${user.id}');
    if (mounted) {
      setState(() => _currentUser = user);
      _startupTimeoutTimer?.cancel();
      print('SSAdminApp: current user set, showing dashboard');
    }
    unawaited(_saveUserBestEffort(user));
    unawaited(_runPostLoginSetup(user));
  }

  Future<void> _saveUserBestEffort(AppUser user) async {
    try {
      await AuthStorageService.saveUser(user);
    } catch (error, stackTrace) {
      print('SSAdminApp: local login save failed: $error');
      print(stackTrace);
    }
  }

  Future<void> _runPostLoginSetup(AppUser user) async {
    try {
      await _authRepository.syncDeviceInfo(user: user, appVariant: 'admin');
      await _ensureAdminBackgroundLocationConsent(user);
    } catch (_) {
      // Keep login flow resilient even if server-side sync fails.
    }
    await _saveUserBestEffort(user);
  }

  Future<void> _handleLogout() async {
    await AuthStorageService.clearUser();
    NotificationService().unbindInboxUser();
    if (mounted) {
      setState(() => _currentUser = null);
    }
  }

  Future<void> _ensureAdminBackgroundLocationConsent(AppUser user) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final alreadyAccepted =
        await BackgroundLocationDisclosureService.isAccepted();
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always && alreadyAccepted) {
      return;
    }

    if (!alreadyAccepted) {
      final navigator = await _waitForNavigatorState();
      if (!mounted || navigator == null) {
        return;
      }
      final accepted = await navigator.push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const BackgroundLocationDisclosureScreen(),
        ),
      );
      if (accepted != true) {
        return;
      }
      await BackgroundLocationDisclosureService.markAccepted();
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.always) {
      return;
    }

    final navigator = await _waitForNavigatorState();
    if (!mounted || navigator == null) {
      return;
    }

    final granted = await LocationPermissionSheet.show(navigator.context);
    if (granted) {
      return;
    }
  }

  Future<NavigatorState?> _waitForNavigatorState() async {
    for (var i = 0; i < 25; i++) {
      final nav = _navKey.currentState;
      if (nav != null) return nav;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(seedColor: Colors.deepPurple);
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
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'SS Admin',
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
            data: mediaQuery.copyWith(textScaler: const TextScaler.linear(1.0)),
            child: InAppNotificationBannerHost(
              hideBell: _currentUser == null,
              child: child,
            ),
          );
        },
        home: _AdminAuthRoot(
          isLoading: _isLoading,
          user: _currentUser,
          onLogin: _handleLogin,
          onLogout: _handleLogout,
        ),
      ),
    );
  }
}

class _AdminAuthRoot extends StatelessWidget {
  const _AdminAuthRoot({
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
      return LoginScreen(
        onLogin: onLogin,
        appTitle: 'SS Transways India',
        appSubtitle: 'Manage HR attendance and approvals',
        screenTitle: 'Admin Login',
        appVariant: 'admin',
      );
    }
    return _AdminHomeSwitchboard(user: currentUser, onLogout: onLogout);
  }
}

class _AdminHomeSwitchboard extends StatelessWidget {
  const _AdminHomeSwitchboard({required this.user, required this.onLogout});

  final AppUser user;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    switch (user.role) {
      case UserRole.admin:
        return AdminDashboardScreen(user: user, onLogout: onLogout);
      case UserRole.supervisor:
        return SupervisorDashboardScreen(user: user, onLogout: onLogout);
      case UserRole.driver:
        return _UnauthorizedRoleScreen(onLogout: onLogout);
      case UserRole.referral:
        return _UnauthorizedRoleScreen(onLogout: onLogout);
    }
  }
}

class _UnauthorizedRoleScreen extends StatelessWidget {
  const _UnauthorizedRoleScreen({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 64,
                color: Colors.deepPurple,
              ),
              const SizedBox(height: 24),
              Text(
                'Restricted access',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This app is intended for SS Admin and Supervisor accounts. '
                'Please switch to the primary SS Transways app for driver operations.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
