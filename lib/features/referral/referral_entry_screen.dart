import 'package:flutter/material.dart';

import '../../core/models/app_user.dart';
import '../../core/services/referral_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_loader.dart';
import 'referral_dashboard_screen.dart';
import 'referral_profile_screen.dart';

class ReferralEntryScreen extends StatefulWidget {
  const ReferralEntryScreen({
    required this.user,
    required this.onLogout,
    super.key,
  });

  final AppUser user;
  final VoidCallback onLogout;

  @override
  State<ReferralEntryScreen> createState() => _ReferralEntryScreenState();
}

class _ReferralEntryScreenState extends State<ReferralEntryScreen> {
  final _repo = ReferralRepository();
  bool _isLoading = true;
  bool _profileSubmitted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final payload = await _repo.fetchMyProfileStatus(userId: widget.user.id);
      final submitted = payload['profile_submitted'] == true;
      if (!mounted) return;
      setState(() {
        _profileSubmitted = submitted;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: AppLoader()));
    }

    if (_error != null) {
      return Scaffold(
        body: AppGradientBackground(
          useSafeArea: true,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 40),
                  const SizedBox(height: 10),
                  const Text('Unable to load referral account status'),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _loadStatus,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: widget.onLogout,
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!_profileSubmitted) {
      return ReferralProfileScreen(
        userId: widget.user.id,
        userName: widget.user.displayName,
        showBackToLoginOnSuccess: false,
        onProfileSubmitted: _loadStatus,
      );
    }

    return ReferralDashboardScreen(
      user: widget.user,
      onLogout: widget.onLogout,
    );
  }
}
