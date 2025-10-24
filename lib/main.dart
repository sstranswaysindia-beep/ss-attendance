import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:firebase_core/firebase_core.dart';

import 'core/models/app_user.dart';
import 'core/services/auth_storage_service.dart';
import 'core/services/notification_service.dart';
import 'firebase_options.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/admin_dashboard_screen.dart';
import 'features/dashboard/driver_dashboard_screen.dart';
import 'features/dashboard/supervisor_dashboard_screen.dart';
import 'core/widgets/in_app_notification_banner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await initializeDateFormatting('en_IN', null);
  Intl.defaultLocale = 'en_IN';

  // Set system UI overlay style globally
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
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

class _SSTranswaysAppState extends State<SSTranswaysApp> {
  AppUser? _currentUser;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedUser();
  }

  Future<void> _loadSavedUser() async {
    try {
      final savedUser = await AuthStorageService.getUser();
      if (mounted) {
        setState(() {
          _currentUser = savedUser;
          _isLoading = false;
        });
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
    await AuthStorageService.saveUser(user);
    if (mounted) {
      setState(() => _currentUser = user);
    }
  }

  void _handleLogout() async {
    await AuthStorageService.clearUser();
    if (mounted) {
      setState(() => _currentUser = null);
    }
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
          final clampedScale = mediaQuery.textScaleFactor.clamp(1.0, 1.1);
          return MediaQuery(
            data: mediaQuery.copyWith(textScaleFactor: clampedScale),
            child: InAppNotificationBannerHost(
              hideBell: child is _LoginRoute,
              child: child,
            ),
          );
        },
        home: _isLoading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
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
