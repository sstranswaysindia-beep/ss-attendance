import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/services/notification_service.dart';
import '../../core/widgets/app_toast.dart';

// ─── Premium Design Tokens ───
const Color _gradientStart = Color(0xFF0A1628);
const Color _gradientEnd = Color(0xFF1B3A5C);
const Color _gradientMid = Color(0xFF0D4F6B);
const Color _accentTeal = Color(0xFF00BFA6);
const Color _accentGold = Color(0xFFD4A843);
const Color _surfaceBg = Color(0xFFF0F4F8);
const Color _surfaceCard = Color(0xFFF8FAFF);
const Color _heroGreen = Color(0xFF7CFFB2);

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen>
    with TickerProviderStateMixin {
  final NotificationService _notificationService = NotificationService();

  bool _tripNotifications = true;
  bool _attendanceNotifications = true;
  bool _salaryNotifications = true;
  bool _advanceNotifications = true;

  bool _isLoading = false;

  late final AnimationController _heroController;
  late final AnimationController _staggerController;
  late final Animation<double> _heroFade;
  late final Animation<double> _heroScale;

  @override
  void initState() {
    super.initState();
    _heroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _heroFade = CurvedAnimation(parent: _heroController, curve: Curves.easeOut);
    _heroScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _heroController, curve: Curves.easeOutBack),
    );

    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _loadSettings();
  }

  @override
  void dispose() {
    _heroController.dispose();
    _staggerController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      try {
        await _notificationService.initialize();
      } catch (e) {
        print('Notification service initialization failed: $e');
      }

      try {
        final hasPermission = await _notificationService.requestPermissions();
        if (!hasPermission && mounted && !kIsWeb) {
          showAppToast(
            context,
            'Notification permissions are required for this feature',
            isError: true,
          );
        }
      } catch (e) {
        print('Permission request failed: $e');
      }
    } catch (e) {
      if (mounted) {
        print('Notification settings load error: $e');
        if (!kIsWeb) {
          showAppToast(
            context,
            'Some notification features may not work properly',
            isError: true,
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _heroController.forward();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _staggerController.forward();
        });
      }
    }
  }

  int get _enabledCount {
    int count = 0;
    if (_tripNotifications) count++;
    if (_attendanceNotifications) count++;
    if (_salaryNotifications) count++;
    if (_advanceNotifications) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _surfaceBg,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_gradientStart, _surfaceBg],
              stops: [0.0, 0.4],
            ),
          ),
          child: const Center(
            child: CircularProgressIndicator(color: _accentTeal),
          ),
        ),
      );
    }

    final notifSettings = <_NotifSettingData>[
      _NotifSettingData(
        title: 'Trip Notifications',
        subtitle: 'Get notified when trips start and end',
        icon: Icons.local_shipping_outlined,
        value: _tripNotifications,
        gradient: const [Color(0xFF3B82F6), Color(0xFF2563EB)],
        onChanged: (v) => setState(() => _tripNotifications = v),
      ),
      _NotifSettingData(
        title: 'Attendance Notifications',
        subtitle: 'Get notified when attendance is marked',
        icon: Icons.fingerprint_rounded,
        value: _attendanceNotifications,
        gradient: const [Color(0xFF10B981), Color(0xFF059669)],
        onChanged: (v) => setState(() => _attendanceNotifications = v),
      ),
      _NotifSettingData(
        title: 'Salary Notifications',
        subtitle: 'Get notified about salary credits',
        icon: Icons.account_balance_wallet_rounded,
        value: _salaryNotifications,
        gradient: const [_accentGold, Color(0xFFB8860B)],
        onChanged: (v) => setState(() => _salaryNotifications = v),
      ),
      _NotifSettingData(
        title: 'Advance Notifications',
        subtitle: 'Get notified about advance request status',
        icon: Icons.request_page_rounded,
        value: _advanceNotifications,
        gradient: const [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
        onChanged: (v) => setState(() => _advanceNotifications = v),
      ),
    ];

    final sections = <Widget>[
      // ─── Settings Card ───
      _buildSettingsCard(notifSettings),
      // ─── Info Card ───
      _buildInfoCard(),
    ];

    return Scaffold(
      backgroundColor: _surfaceBg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ─── Gradient SliverAppBar ───
          SliverAppBar(
            pinned: true,
            expandedHeight: 160,
            backgroundColor: _gradientEnd,
            surfaceTintColor: Colors.transparent,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            leading: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
              ),
            ),
            title: const Text(
              'Notification Settings',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_gradientStart, _gradientEnd, _gradientMid],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
                    child: FadeTransition(
                      opacity: _heroFade,
                      child: ScaleTransition(
                        scale: _heroScale,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _buildHeroCard(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // ─── Body ───
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              child: AnimatedBuilder(
                animation: _staggerController,
                builder: (context, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(sections.length, (index) {
                      final start = (index * 0.25).clamp(0.0, 1.0);
                      final end = (start + 0.5).clamp(0.0, 1.0);
                      final anim = Tween<double>(begin: 0.0, end: 1.0).animate(
                        CurvedAnimation(
                          parent: _staggerController,
                          curve: Interval(start, end, curve: Curves.easeOutCubic),
                        ),
                      );
                      return Transform.translate(
                        offset: Offset(0, 30 * (1 - anim.value)),
                        child: Opacity(
                          opacity: anim.value,
                          child: Padding(
                            padding: EdgeInsets.only(
                              bottom: index < sections.length - 1 ? 16 : 0,
                            ),
                            child: sections[index],
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_accentTeal, _heroGreen],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Stay Updated',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage your notification preferences',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _heroGreen.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _heroGreen.withOpacity(0.4)),
            ),
            child: Text(
              '$_enabledCount/4',
              style: const TextStyle(
                color: _heroGreen,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard(List<_NotifSettingData> settings) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.8)),
        boxShadow: [
          BoxShadow(
            color: _gradientStart.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_gradientStart, _accentTeal],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.tune_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notification Preferences',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF12243A),
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Choose which alerts you want to receive',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6C7A8F),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...settings.map((s) => _buildSettingTile(s)),
        ],
      ),
    );
  }

  Widget _buildSettingTile(_NotifSettingData data) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: data.value
              ? _accentTeal.withOpacity(0.05)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: data.value
                ? _accentTeal.withOpacity(0.15)
                : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: data.value
                      ? data.gradient
                      : [Colors.grey.shade300, Colors.grey.shade400],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(data.icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: data.value
                          ? const Color(0xFF12243A)
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: data.value
                          ? const Color(0xFF6C7A8F)
                          : const Color(0xFFB0B7C3),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              child: Switch.adaptive(
                value: data.value,
                onChanged: data.onChanged,
                activeColor: _accentTeal,
                activeTrackColor: _accentTeal.withOpacity(0.3),
                inactiveThumbColor: Colors.grey.shade400,
                inactiveTrackColor: Colors.grey.shade200,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.8)),
        boxShadow: [
          BoxShadow(
            color: _gradientStart.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_accentGold, Color(0xFFB8860B)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notification Info',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF12243A),
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'How notifications work in the app',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6C7A8F),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (kIsWeb) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.orange.shade100,
                    Colors.orange.shade50,
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Notifications are not supported on web. Use the mobile app for full features.',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          _buildInfoTile(
            Icons.notifications_active_outlined,
            'Stay updated with important events in real-time',
            const [Color(0xFF3B82F6), Color(0xFF2563EB)],
          ),
          const SizedBox(height: 10),
          _buildInfoTile(
            Icons.tune_rounded,
            'Customize which types of notifications to receive',
            const [Color(0xFF10B981), Color(0xFF059669)],
          ),
          const SizedBox(height: 10),
          _buildInfoTile(
            Icons.settings_outlined,
            'Ensure permissions are enabled in device settings',
            const [_accentGold, Color(0xFFB8860B)],
          ),
          const SizedBox(height: 10),
          _buildInfoTile(
            Icons.phonelink_ring_outlined,
            'Notifications work even when the app is in the background',
            const [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String text, List<Color> gradient) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradient),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 14),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF374151),
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NotifSettingData {
  const _NotifSettingData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.gradient,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final List<Color> gradient;
  final ValueChanged<bool> onChanged;
}
