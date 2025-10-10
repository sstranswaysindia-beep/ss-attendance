import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';
import '../approvals/approvals_screen.dart';
import '../attendance/attendance_history_screen.dart';
import '../statistics/monthly_statistics_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({
    required this.user,
    required this.onLogout,
    super.key,
  });

  final AppUser user;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final date = DateFormat('dd-MM-yyyy').format(now);
    final time = DateFormat('HH:mm').format(now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            onPressed: () {
              onLogout();
              showAppToast(context, 'Logged out successfully');
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: AppGradientBackground(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Welcome, ${user.displayName}'),
              subtitle: Text('Date: $date  Time: $time'),
              trailing: const CircleAvatar(child: Icon(Icons.admin_panel_settings)),
            ),
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
                      builder: (_) => MonthlyStatisticsScreen(user: user),
                    ),
                  ),
                ),
                _AdminCard(
                  title: 'Supervisor Approvals',
                  icon: Icons.verified_user,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ApprovalsScreen(
                        user: user,
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
                  onTap: () {},
                ),
                _AdminCard(
                  title: 'Vehicle Master',
                  icon: Icons.directions_bus,
                  onTap: () {},
                ),
                _AdminCard(
                  title: 'Reports & Exports',
                  icon: Icons.picture_as_pdf,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AttendanceHistoryScreen(user: user),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.security),
                title: const Text('RBAC Summary'),
                subtitle: const Text('Drivers limited to own data, supervisors scoped by plant.'),
                trailing: const Icon(Icons.chevron_right),
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
  const _AdminCard({
    required this.title,
    required this.icon,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 120,
      child: Card(
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
                const Spacer(),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
