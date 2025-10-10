import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'core/models/app_user.dart';
// import 'core/services/notification_service.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/admin_dashboard_screen.dart';
import 'features/dashboard/driver_dashboard_screen.dart';
import 'features/dashboard/supervisor_dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en_IN', null);
  Intl.defaultLocale = 'en_IN';

  // Initialize notification service
  // await NotificationService().initialize();

  runApp(const SSTranswaysApp());
}

class SSTranswaysApp extends StatefulWidget {
  const SSTranswaysApp({super.key});

  @override
  State<SSTranswaysApp> createState() => _SSTranswaysAppState();
}

class _SSTranswaysAppState extends State<SSTranswaysApp> {
  AppUser? _currentUser;

  void _handleLogin(AppUser user) {
    setState(() => _currentUser = user);
  }

  void _handleLogout() {
    setState(() => _currentUser = null);
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

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SS Transways Attendance',
      theme: baseTheme.copyWith(
        textTheme: textTheme,
        appBarTheme: baseTheme.appBarTheme.copyWith(
          titleTextStyle: textTheme.headlineSmall?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
      ),
      home: _currentUser == null
          ? LoginScreen(onLogin: _handleLogin)
          : _HomeSwitchboard(user: _currentUser!, onLogout: _handleLogout),
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
