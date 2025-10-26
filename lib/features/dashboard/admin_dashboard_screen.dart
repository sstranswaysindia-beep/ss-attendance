import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/widgets/app_toast.dart';
import '../approvals/approvals_screen.dart';
import '../attendance/admin_today_attendance_screen.dart';
import '../attendance/attendance_history_screen.dart';
import '../statistics/admin_attendance_overview_screen.dart';
import '../finance/advance_salary_screen.dart';
import '../master/admin_driver_master_screen.dart';
import '../master/admin_vehicle_master_screen.dart';

const Color _adminPrimaryColor = Color(0xFF00296B);
const Color _adminCardTint = Color(0xFFE3F2FD);

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    required this.user,
    required this.onLogout,
    super.key,
  });

  final AppUser user;
  final VoidCallback onLogout;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final date = DateFormat('dd-MM-yyyy').format(now);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _adminPrimaryColor,
        foregroundColor: Colors.white,
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AdvanceSalaryScreen(user: widget.user),
                ),
              );
            },
            icon: const Icon(Icons.account_balance_wallet),
            tooltip: 'Khata Book',
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
      body: Container(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              _AdminWelcomeHeader(user: widget.user, date: date),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
              children: [
                _AdminCard(
                  title: 'Attendance Overview',
                  icon: Icons.insights,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          AdminAttendanceOverviewScreen(user: widget.user),
                    ),
                  ),
                ),
                _AdminCard(
                  title: 'Today Attendance',
                  icon: Icons.fact_check,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          AdminTodayAttendanceScreen(user: widget.user),
                    ),
                  ),
                ),
                _AdminCard(
                  title: 'Supervisor Approvals',
                  icon: Icons.verified_user,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ApprovalsScreen(
                          user: widget.user,
                          title: 'Supervisor Approvals',
                          endpointOverride: Uri.parse(
                            'https://sstranswaysindia.com/api/mobile/attendance_admin_supervisor_approvals.php',
                          ),
                          userIdParamKey: 'adminUserId',
                        ),
                      ),
                    ),
                  ),
                  _AdminCard(
                    title: 'Driver Master',
                    icon: Icons.person_search,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            AdminDriverMasterScreen(user: widget.user),
                      ),
                    ),
                  ),
                  _AdminCard(
                    title: 'Vehicle Master',
                    icon: Icons.directions_bus,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            AdminVehicleMasterScreen(user: widget.user),
                      ),
                    ),
                  ),
                  _AdminCard(
                    title: 'Reports & Exports',
                    icon: Icons.picture_as_pdf,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            AttendanceHistoryScreen(user: widget.user),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.white, _adminCardTint],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1400296B),
                      blurRadius: 18,
                      offset: Offset(0, 10),
                    ),
                  ],
                  border: Border.all(
                    color: _adminPrimaryColor.withOpacity(0.08),
                  ),
                ),
                child: ListTile(
                  leading: const Icon(
                    Icons.security,
                    color: _adminPrimaryColor,
                  ),
                  title: const Text(
                    'RBAC Summary',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _adminPrimaryColor,
                    ),
                  ),
                  subtitle: const Text(
                    'Drivers limited to own data, supervisors scoped by plant.',
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: _adminPrimaryColor,
                  ),
                  onTap: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _AdminCard extends StatelessWidget {
  const _AdminCard({required this.title, required this.icon, this.onTap});

  final String title;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const gradient = LinearGradient(
      colors: [Colors.white, _adminCardTint],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return SizedBox(
      width: 180,
      height: 120,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Ink(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 32, color: _adminPrimaryColor),
                  const Spacer(),
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminWelcomeHeader extends StatefulWidget {
  const _AdminWelcomeHeader({
    required this.user,
    required this.date,
    super.key,
  });

  final AppUser user;
  final String date;

  @override
  State<_AdminWelcomeHeader> createState() => _AdminWelcomeHeaderState();
}

class _AdminWelcomeHeaderState extends State<_AdminWelcomeHeader> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedTime = DateFormat('HH:mm:ss').format(_now);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, _adminCardTint],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _adminPrimaryColor.withOpacity(0.08)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome HR, ${widget.user.displayName}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _adminPrimaryColor,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_month,
                      size: 18,
                      color: _adminPrimaryColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.date,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _adminPrimaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Icon(
                      Icons.access_time,
                      size: 18,
                      color: _adminPrimaryColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formattedTime,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _adminPrimaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: _adminPrimaryColor.withOpacity(0.1)),
            ),
            child: Container(
              margin: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _adminPrimaryColor,
              ),
              child: const Icon(
                Icons.admin_panel_settings,
                color: Color(0xFFFFBB39),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
