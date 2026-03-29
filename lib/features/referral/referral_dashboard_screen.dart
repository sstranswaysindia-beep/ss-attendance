import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/app_user.dart';
import '../../core/models/referral.dart';
import '../../core/services/referral_repository.dart';
import '../../core/widgets/app_loader.dart';
import '../../core/widgets/app_toast.dart';
import 'referral_tracker_screen.dart';

// ─── Lime-Green Premium Palette ───────────────────────────────────────────────
class _P {
  _P._();
  // Surfaces
  static const bg = Colors.white;
  static const cardWhite = Colors.white;

  // Brand — lime-green family
  static const brand = Color(0xFF558B2F);       // Lime-dark
  static const brandLight = Color(0xFF8BC34A);   // Lime-medium
  static const accent = Color(0xFF558B2F);        // Same as brand for consistency
  static const accentLight = Color(0xFFF2FBDF);  // Lime-50

  // Text
  static const textDark = Color(0xFF1B2E0A);     // Deep green-black
  static const textMedium = Color(0xFF4B5563);   // Gray-600
  static const textLight = Color(0xFF9CA3AF);    // Gray-400

  // Semantic
  static const green = Color(0xFF2E7D32);
  static const greenBg = Color(0xFFE8F5E9);
  static const amber = Color(0xFFF57F17);
  static const amberBg = Color(0xFFFFF8E1);
  static const red = Color(0xFFC62828);
  static const redBg = Color(0xFFFFEBEE);

  // Gradients
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF558B2F), Color(0xFF8BC34A), Color(0xFFD8F999)],
  );

}

// ═══════════════════════════════════════════════════════════════════════════════
//  REFERRAL DASHBOARD SCREEN
// ═══════════════════════════════════════════════════════════════════════════════
class ReferralDashboardScreen extends StatefulWidget {
  const ReferralDashboardScreen({
    required this.user,
    required this.onLogout,
    super.key,
  });

  final AppUser user;
  final VoidCallback onLogout;

  @override
  State<ReferralDashboardScreen> createState() =>
      _ReferralDashboardScreenState();
}

class _ReferralDashboardScreenState extends State<ReferralDashboardScreen>
    with TickerProviderStateMixin {
  final _repo = ReferralRepository();
  bool _isLoading = true;
  String? _error;
  String _referralCode = '';
  Map<String, dynamic> _profile = const {};
  List<Referral> _referrals = const [];
  String _upiId = '';
  final _upiCtrl = TextEditingController();
  bool _isSavingUpi = false;
  bool _isWithdrawing = false;

  // ── Animations ──────────────────────────────────────────────────────────
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  late AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.15, end: 0.45).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _loadDashboard();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    _pulseCtrl.dispose();
    _shimmerCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.fetchReferralCode(userId: widget.user.id),
        _repo.fetchMyProfileStatus(userId: widget.user.id),
        _repo.fetchReferrals(userId: widget.user.id),
      ]);
      if (!mounted) return;
      setState(() {
        _referralCode = (results[0] as String).trim();
        _profile = results[1] as Map<String, dynamic>;
        _referrals = results[2] as List<Referral>;
        _isLoading = false;
      });
      _fadeCtrl.forward();
      _slideCtrl.forward();

      // Fetch UPI in parallel (non-blocking)
      _repo.fetchUpiId(userId: widget.user.id).then((upi) {
        if (!mounted) return;
        setState(() {
          _upiId = upi;
          _upiCtrl.text = upi;
        });
      }).catchError((_) {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _copyCode() {
    if (_referralCode.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _referralCode));
    HapticFeedback.mediumImpact();
    showAppToast(context, 'Referral code copied');
  }

  void _shareCode() {
    if (_referralCode.isEmpty) return;
    HapticFeedback.lightImpact();
    Share.share(
      'Join SS Transways India! Use my referral code: $_referralCode',
      subject: 'SS Transways Referral',
    );
  }

  Future<void> _saveUpiId() async {
    final upi = _upiCtrl.text.trim();
    if (upi.isEmpty) {
      showAppToast(context, 'Please enter UPI ID / Google Pay number', isError: true);
      return;
    }
    setState(() => _isSavingUpi = true);
    try {
      await _repo.saveUpiId(userId: widget.user.id, upiId: upi);
      if (!mounted) return;
      setState(() => _upiId = upi);
      HapticFeedback.mediumImpact();
      showAppToast(context, 'UPI ID saved successfully');
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isSavingUpi = false);
    }
  }

  Future<void> _requestWithdrawal() async {
    final earnings = _referrals
        .where((r) => r.status == ReferralStatus.verified)
        .fold<double>(0, (sum, item) => sum + item.amount);

    if (earnings < 500) {
      showAppToast(
        context,
        'Minimum ₹500 required to withdraw. Current: ₹${earnings.toStringAsFixed(0)}',
        isError: true,
      );
      return;
    }

    final upi = _upiCtrl.text.trim();
    if (upi.isEmpty) {
      showAppToast(context, 'Please save your UPI ID first', isError: true);
      return;
    }

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Withdrawal'),
        content: Text(
          'Withdraw ₹${earnings.toStringAsFixed(0)} to\n$upi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: _P.brand,
            ),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isWithdrawing = true);
    try {
      await _repo.requestWithdrawal(
        userId: widget.user.id,
        amount: earnings,
        upiId: upi,
      );
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      showAppToast(context, 'Withdrawal request submitted!');
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isWithdrawing = false);
    }
  }

  String _safe(String? value, {String fallback = '-'}) {
    final v = value?.trim() ?? '';
    return v.isEmpty ? fallback : v;
  }

  String _maskAadhar(String? raw) {
    final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length != 12) return '-';
    return 'XXXX XXXX ${digits.substring(8)}';
  }

  String _fmtDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '-';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt.toLocal());
  }

  String _statusLabel(String? status) {
    final v = (status ?? '').trim().toLowerCase();
    if (v == 'verified') return 'Verified';
    if (v == 'rejected') return 'Rejected';
    return 'Pending';
  }

  Color _statusColor(String? status) {
    final v = (status ?? '').trim().toLowerCase();
    if (v == 'verified') return _P.green;
    if (v == 'rejected') return _P.red;
    return _P.amber;
  }

  Color _statusBg(String? status) {
    final v = (status ?? '').trim().toLowerCase();
    if (v == 'verified') return _P.greenBg;
    if (v == 'rejected') return _P.redBg;
    return _P.amberBg;
  }

  IconData _statusIcon(String? status) {
    final v = (status ?? '').trim().toLowerCase();
    if (v == 'verified') return Icons.verified_rounded;
    if (v == 'rejected') return Icons.cancel_rounded;
    return Icons.schedule_rounded;
  }

  // ─── BUILD ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _P.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLoader(),
              const SizedBox(height: 18),
              Text(
                'Loading dashboard…',
                style: TextStyle(
                  color: _P.textLight,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) return _buildErrorView();

    final earnings = _referrals
        .where((r) => r.status == ReferralStatus.verified)
        .fold<double>(0, (sum, item) => sum + item.amount);

    return Scaffold(
      backgroundColor: _P.bg,
      body: Stack(
        children: [
          const _AnimatedBackgroundOrbs(),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(earnings),
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: RefreshIndicator(
                        onRefresh: _loadDashboard,
                        color: _P.brand,
                        backgroundColor: Colors.white,
                        child: ListView(
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                          children: [
                            _buildProfileHeader(),
                            const SizedBox(height: 12),
                            _buildReferralCodeCard(),
                            const SizedBox(height: 12),
                            _buildStatsSection(),
                            const SizedBox(height: 12),
                            _buildUpiWithdrawCard(),
                            const SizedBox(height: 12),
                            _buildHowToEarnCard(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── ERROR ──────────────────────────────────────────────────────────────
  Widget _buildErrorView() {
    return Scaffold(
      backgroundColor: _P.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _SoftCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _P.redBg,
                  ),
                  child: const Icon(Icons.cloud_off_rounded,
                      color: _P.red, size: 36),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Unable to load dashboard',
                  style: TextStyle(
                    color: _P.textDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _P.textLight, fontSize: 13),
                ),
                const SizedBox(height: 22),
                _BrandButton(
                  label: 'Retry',
                  icon: Icons.refresh_rounded,
                  onTap: _loadDashboard,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── APP BAR ────────────────────────────────────────────────────────────
  Widget _buildAppBar(double earnings) {
    final earningsText = '₹${earnings.toStringAsFixed(0)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Gradient title
          ShaderMask(
            shaderCallback: (bounds) =>
                _P.heroGradient.createShader(bounds),
            child: const Text(
              'Referral Dashboard',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const Spacer(),
          // Wallet with earnings badge
          _WalletBadge(amount: earningsText),
          const SizedBox(width: 8),
          _SoftIconBtn(
            icon: Icons.refresh_rounded,
            onTap: _loadDashboard,
          ),
          const SizedBox(width: 8),
          _SoftIconBtn(icon: Icons.logout_rounded, onTap: widget.onLogout),
        ],
      ),
    );
  }

  // ─── PROFILE SHEET ──────────────────────────────────────────────────────
  void _showProfileSheet() {
    final displayName = _safe(
      _profile['referred_name']?.toString(),
      fallback: _safe(widget.user.displayName, fallback: 'Referral User'),
    );
    final mobile = _safe(_profile['referred_mobile']?.toString());
    final typeRaw = _safe(_profile['referred_type']?.toString(), fallback: '');
    final typeLabel = typeRaw.isEmpty || typeRaw == '-'
        ? '-'
        : '${typeRaw[0].toUpperCase()}${typeRaw.substring(1).toLowerCase()}';
    final aadharMasked = _maskAadhar(_profile['aadhar_no']?.toString());
    final dlNo = _safe(_profile['dl_no']?.toString());
    final submittedAt = _fmtDate(_profile['profile_submitted_at']?.toString());
    final status = _profile['referral_status']?.toString();
    final statusText = _statusLabel(status);
    final statusCol = _statusColor(status);
    final statusBgCol = _statusBg(status);
    final statusIcn = _statusIcon(status);

    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: _P.cardWhite,
            borderRadius: BorderRadius.circular(24),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: Colors.grey.shade300,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Avatar + Name
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _P.heroGradient,
                      boxShadow: [
                        BoxShadow(
                          color: _P.brand.withOpacity(0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : 'R',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 26,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: _P.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: statusBgCol,
                      border:
                          Border.all(color: statusCol.withOpacity(0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcn, size: 14, color: statusCol),
                        const SizedBox(width: 5),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusCol,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(height: 1, color: Color(0xFFF0F0F5)),
                  const SizedBox(height: 16),
                  // Detail rows
                  _DetailRow(
                      icon: Icons.phone_rounded,
                      label: 'Mobile',
                      value: mobile),
                  _DetailRow(
                      icon: Icons.badge_rounded,
                      label: 'Type',
                      value: typeLabel),
                  _DetailRow(
                      icon: Icons.credit_card_rounded,
                      label: 'Aadhaar',
                      value: aadharMasked),
                  _DetailRow(
                      icon: Icons.drive_eta_rounded,
                      label: 'DL Number',
                      value: dlNo),
                  _DetailRow(
                      icon: Icons.calendar_today_rounded,
                      label: 'Submitted',
                      value: submittedAt),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── PROFILE HEADER (compact) ───────────────────────────────────────────
  Widget _buildProfileHeader() {
    final displayName = _safe(
      _profile['referred_name']?.toString(),
      fallback: _safe(widget.user.displayName, fallback: 'Referral User'),
    );
    final status = _profile['referral_status']?.toString();
    final statusText = _statusLabel(status);
    final statusCol = _statusColor(status);
    final statusBgCol = _statusBg(status);
    final statusIcn = _statusIcon(status);

    return _SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: _showProfileSheet,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: _P.heroGradient,
                boxShadow: [
                  BoxShadow(
                    color: _P.brand.withOpacity(0.20),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  displayName.isNotEmpty
                      ? displayName[0].toUpperCase()
                      : 'R',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _P.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: statusBgCol,
                    border: Border.all(color: statusCol.withOpacity(0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcn, size: 12, color: statusCol),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusCol,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _showProfileSheet,
            child: const Icon(
              Icons.chevron_right_rounded,
              color: _P.textLight,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  // ─── REFERRAL CODE CARD (compact) ────────────────────────────────────────
  Widget _buildReferralCodeCard() {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: _P.heroGradient,
            boxShadow: [
              BoxShadow(
                color: _P.brand.withOpacity(_pulseAnim.value * 0.30),
                blurRadius: 22,
                spreadRadius: -2,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.15),
                  ),
                  child: const Icon(
                    Icons.card_giftcard_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Your Referral Code',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Code row with inline copy/share icons
            Row(
              children: [
                Expanded(
                  child: _ShimmerCodeDisplay(
                    code: _referralCode.isEmpty ? '---' : _referralCode,
                    controller: _shimmerCtrl,
                  ),
                ),
                const SizedBox(width: 8),
                _InlineIconBtn(
                  icon: Icons.copy_rounded,
                  tooltip: 'Copy',
                  onTap: _copyCode,
                ),
                const SizedBox(width: 6),
                _InlineIconBtn(
                  icon: Icons.share_rounded,
                  tooltip: 'Share',
                  onTap: _shareCode,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── STATS SECTION (compact) ─────────────────────────────────────────────
  Widget _buildStatsSection() {
    final total = _referrals.length;
    final verified =
        _referrals.where((r) => r.status == ReferralStatus.verified).length;
    final pending =
        _referrals.where((r) => r.status == ReferralStatus.pending).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Referral Stats',
              style: TextStyle(
                color: _P.textDark,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ReferralTrackerScreen(user: widget.user),
                  ),
                );
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: _P.accentLight,
                  border: Border.all(color: _P.accent.withOpacity(0.25)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View All',
                      style: TextStyle(
                        color: _P.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 3),
                    Icon(Icons.arrow_forward_ios_rounded,
                        size: 10, color: _P.accent),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _AnimatedStatCard(
                icon: Icons.people_alt_rounded,
                label: 'Total',
                value: '$total',
                color: _P.brand,
                bgColor: _P.accentLight,
                delay: 0,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AnimatedStatCard(
                icon: Icons.check_circle_rounded,
                label: 'Verified',
                value: '$verified',
                color: _P.green,
                bgColor: _P.greenBg,
                delay: 120,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AnimatedStatCard(
                icon: Icons.schedule_rounded,
                label: 'Pending',
                value: '$pending',
                color: _P.amber,
                bgColor: _P.amberBg,
                delay: 240,
              ),
            ),
          ],
        ),
      ],
    );
  }



  // ─── UPI & WITHDRAW CARD ──────────────────────────────────────────────────
  Widget _buildUpiWithdrawCard() {
    final earnings = _referrals
        .where((r) => r.status == ReferralStatus.verified)
        .fold<double>(0, (sum, item) => sum + item.amount);
    final canWithdraw = earnings >= 500;

    return _SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: const Color(0xFFF3EEFF),
                ),
                child: const Icon(Icons.account_balance_wallet_rounded,
                    color: Color(0xFF7C4DFF), size: 16),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Payment & Withdraw',
                  style: TextStyle(
                    color: _P.textDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: canWithdraw ? _P.greenBg : _P.amberBg,
                ),
                child: Text(
                  '₹${earnings.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: canWithdraw ? _P.green : _P.amber,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // UPI Input
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _upiCtrl,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'UPI ID / Google Pay No.',
                    labelStyle:
                        const TextStyle(fontSize: 13, color: _P.textLight),
                    prefixIcon: const Icon(Icons.payment_rounded,
                        color: _P.accent, size: 20),
                    filled: true,
                    fillColor: _P.accentLight.withOpacity(0.3),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: _P.accent.withOpacity(0.2)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: _P.accent.withOpacity(0.2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: _P.accent, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _isSavingUpi ? null : _saveUpiId,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: _P.accent,
                  ),
                  child: _isSavingUpi
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded,
                          color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
          if (_upiId.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: _P.green, size: 14),
                const SizedBox(width: 4),
                Text(
                  'Saved: $_upiId',
                  style: const TextStyle(
                    color: _P.green,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          // Withdraw button
          GestureDetector(
            onTap:
                (canWithdraw && !_isWithdrawing) ? _requestWithdrawal : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: canWithdraw
                    ? const LinearGradient(
                        colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
                      )
                    : null,
                color: canWithdraw ? null : Colors.grey.shade200,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isWithdrawing)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else ...[
                    Icon(
                      Icons.account_balance_rounded,
                      color:
                          canWithdraw ? Colors.white : Colors.grey.shade400,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      canWithdraw
                          ? 'Withdraw ₹${earnings.toStringAsFixed(0)}'
                          : 'Min ₹500 to Withdraw (₹${earnings.toStringAsFixed(0)}/₹500)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: canWithdraw
                            ? Colors.white
                            : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── HOW TO EARN (instruction card) ─────────────────────────────────────
  Widget _buildHowToEarnCard() {
    return _SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: _P.accentLight,
                ),
                child: Icon(Icons.lightbulb_rounded,
                    color: _P.brand, size: 16),
              ),
              const SizedBox(width: 8),
              const Text(
                'How to Earn',
                style: TextStyle(
                  color: _P.textDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InstructionStep(
            step: '1',
            text: 'Share your referral code with new drivers or helpers.',
          ),
          const SizedBox(height: 8),
          _InstructionStep(
            step: '2',
            text: 'They register on the SS Transways India app using your code.',
          ),
          const SizedBox(height: 8),
          _InstructionStep(
            step: '3',
            text: 'Once verified, you earn referral rewards automatically!',
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SOFT CARD  — light elevated card
// ═══════════════════════════════════════════════════════════════════════════════
class _SoftCard extends StatelessWidget {
  const _SoftCard({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _P.cardWhite,
        boxShadow: [
          BoxShadow(
            color: _P.brand.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  INSTRUCTION STEP — numbered step row
// ═══════════════════════════════════════════════════════════════════════════════
class _InstructionStep extends StatelessWidget {
  const _InstructionStep({required this.step, required this.text});
  final String step;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _P.accentLight,
          ),
          child: Center(
            child: Text(
              step,
              style: TextStyle(
                color: _P.brand,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: _P.textMedium,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DETAIL ROW
// ═══════════════════════════════════════════════════════════════════════════════
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _P.textLight),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: _P.textLight, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: _P.textDark,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ANIMATED STAT CARD
// ═══════════════════════════════════════════════════════════════════════════════
class _AnimatedStatCard extends StatefulWidget {
  const _AnimatedStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
    this.delay = 0,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color bgColor;
  final int delay;

  @override
  State<_AnimatedStatCard> createState() => _AnimatedStatCardState();
}

class _AnimatedStatCardState extends State<_AnimatedStatCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0, 0.5, curve: Curves.easeOut),
      ),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.scale(scale: _scale.value, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: _P.cardWhite,
          border: Border.all(color: widget.bgColor),
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(0.07),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.bgColor,
              ),
              child: Icon(widget.icon, color: widget.color, size: 18),
            ),
            const SizedBox(height: 6),
            Text(
              widget.value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: widget.color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 10,
                color: _P.textLight,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SOFT ICON BUTTON — top bar
// ═══════════════════════════════════════════════════════════════════════════════
class _SoftIconBtn extends StatelessWidget {
  const _SoftIconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: _P.cardWhite,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: _P.textMedium, size: 20),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  WALLET BADGE — shows earnings as notification-style badge on wallet icon
// ═══════════════════════════════════════════════════════════════════════════════
class _WalletBadge extends StatelessWidget {
  const _WalletBadge({required this.amount});
  final String amount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Wallet icon container
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: _P.cardWhite,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.account_balance_wallet_rounded,
                color: _P.green,
                size: 20,
              ),
            ),
          ),
          // Earnings badge
          Positioned(
            top: -4,
            right: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: _P.green,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: _P.green.withOpacity(0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                amount,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  INLINE ICON BUTTON — compact frosted-glass icon on dark context
// ═══════════════════════════════════════════════════════════════════════════════
class _InlineIconBtn extends StatelessWidget {
  const _InlineIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.15),
            border: Border.all(color: Colors.white.withOpacity(0.25)),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  BRAND BUTTON — for error-retry context
// ═══════════════════════════════════════════════════════════════════════════════
class _BrandButton extends StatelessWidget {
  const _BrandButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: _P.heroGradient,
          boxShadow: [
            BoxShadow(
              color: _P.brand.withOpacity(0.25),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SHIMMER CODE DISPLAY — sweeps over the referral code
// ═══════════════════════════════════════════════════════════════════════════════
class _ShimmerCodeDisplay extends StatelessWidget {
  const _ShimmerCodeDisplay({
    required this.code,
    required this.controller,
  });
  final String code;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withOpacity(0.1),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment(-1.5 + controller.value * 3, 0),
                end: Alignment(-0.5 + controller.value * 3, 0),
                colors: const [
                  Colors.white70,
                  Color(0xFFFFFFFF),
                  Colors.white70,
                ],
                stops: const [0.0, 0.5, 1.0],
              ).createShader(bounds);
            },
            child: Text(
              code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 5,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ANIMATED BACKGROUND ORBS — soft floating blobs
// ═══════════════════════════════════════════════════════════════════════════════
class _AnimatedBackgroundOrbs extends StatefulWidget {
  const _AnimatedBackgroundOrbs();

  @override
  State<_AnimatedBackgroundOrbs> createState() =>
      _AnimatedBackgroundOrbsState();
}

class _AnimatedBackgroundOrbsState extends State<_AnimatedBackgroundOrbs>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value * 2 * math.pi;
        return IgnorePointer(
          child: Stack(
            children: [
              // Top-right soft indigo orb
              Positioned(
                top: -60 + 20 * math.sin(t),
                right: -40 + 15 * math.cos(t),
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _P.brandLight.withOpacity(0.10),
                        _P.brandLight.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // Bottom-left soft cyan orb
              Positioned(
                bottom: -80 + 18 * math.cos(t + 1.2),
                left: -50 + 15 * math.sin(t + 1.2),
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _P.accent.withOpacity(0.08),
                        _P.accent.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // Center faint blob
              Positioned(
                top: MediaQuery.of(context).size.height * 0.4,
                left: MediaQuery.of(context).size.width * 0.3 +
                    10 * math.sin(t + 2.5),
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _P.brand.withOpacity(0.05),
                        _P.brand.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
