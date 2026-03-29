import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/app_user.dart';
import '../../core/models/referral.dart';
import '../../core/services/referral_repository.dart';
import '../../core/widgets/app_toast.dart';

// ─── Lime-green themed palette ────────────────────────────────────────────────
class _C {
  _C._();
  // Primary lime
  static const lime = Color(0xFFD8F999); // ignore: unused_field
  static const limeDark = Color(0xFF8BC34A);
  static const limeDarker = Color(0xFF558B2F);
  static const limeBg = Color(0xFFF2FBDF);
  static const limeSubtle = Color(0xFFEAF7CC);

  // Surfaces
  static const bg = Colors.white;
  static const cardBg = Colors.white;

  // Text
  static const textDark = Color(0xFF1B2E0A);
  static const textMedium = Color(0xFF4B5563); // ignore: unused_field
  static const textLight = Color(0xFF9CA3AF);

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

/// Full-screen referral tracker for existing logged-in users.
/// Shows their unique referral code, summary stats, and a list of
/// all referrals with status (pending / verified / rejected).
class ReferralTrackerScreen extends StatefulWidget {
  const ReferralTrackerScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<ReferralTrackerScreen> createState() => _ReferralTrackerScreenState();
}

class _ReferralTrackerScreenState extends State<ReferralTrackerScreen>
    with TickerProviderStateMixin {
  final _repo = ReferralRepository();
  String? _referralCode;
  List<Referral>? _referrals;
  bool _isLoading = true;
  String? _error;
  String _upiId = '';
  final _upiCtrl = TextEditingController();
  bool _isSavingUpi = false;
  bool _isWithdrawing = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;
  late AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _loadData();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    _shimmerCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _repo.fetchReferralCode(userId: widget.user.id),
        _repo.fetchReferrals(userId: widget.user.id),
      ]);

      if (!mounted) return;
      setState(() {
        _referralCode = results[0] as String;
        _referrals = results[1] as List<Referral>;
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
    if (_referralCode == null || _referralCode!.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _referralCode!));
    HapticFeedback.mediumImpact();
    showAppToast(context, 'Referral code copied!');
  }

  void _shareCode() {
    if (_referralCode == null || _referralCode!.isEmpty) return;
    HapticFeedback.lightImpact();
    Share.share(
      'Join SS Transways India! Use my referral code: $_referralCode to register in the app and earn rewards.',
      subject: 'SS Transways Referral',
    );
  }

  Future<void> _saveUpiId() async {
    final upi = _upiCtrl.text.trim();
    if (upi.isEmpty) {
      showAppToast(context, 'Please enter UPI ID / Google Pay number',
          isError: true);
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
    final referrals = _referrals ?? [];
    final earnings = referrals
        .where((r) => r.status == ReferralStatus.verified)
        .fold<double>(0, (sum, item) => sum + item.amount);

    if (earnings < 500) {
      showAppToast(
        context,
        'Minimum ₹500 required. Current: ₹${earnings.toStringAsFixed(0)}',
        isError: true,
      );
      return;
    }

    final upi = _upiCtrl.text.trim();
    if (upi.isEmpty) {
      showAppToast(context, 'Please save your UPI ID first', isError: true);
      return;
    }

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
            style: FilledButton.styleFrom(backgroundColor: _C.limeDarker),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: _C.textDark,
        title: ShaderMask(
          shaderCallback: (bounds) => _C.heroGradient.createShader(bounds),
          child: const Text(
            'Referral Program',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontSize: 20,
              letterSpacing: -0.3,
            ),
          ),
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: _C.limeDark,
                    strokeWidth: 2.5,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Loading referrals…',
                    style: TextStyle(
                      color: _C.textLight,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          : _error != null
              ? _buildError()
              : FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: RefreshIndicator(
                      onRefresh: _loadData,
                      color: _C.limeDarker,
                      backgroundColor: Colors.white,
                      child: ListView(
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                        children: [
                          _buildReferralCodeCard(),
                          const SizedBox(height: 18),
                          _buildStatsCards(),
                          const SizedBox(height: 14),
                          _buildUpiWithdrawCard(),
                          const SizedBox(height: 22),
                          _buildReferralsList(),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  // ─── Error ──────────────────────────────────────────────────────────────
  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _C.redBg,
              ),
              child: Icon(Icons.cloud_off_rounded, size: 40, color: _C.red),
            ),
            const SizedBox(height: 18),
            const Text(
              'Unable to load referral data',
              style: TextStyle(
                color: _C.textDark,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              style: const TextStyle(color: _C.textLight, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _loadData,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: _C.heroGradient,
                  boxShadow: [
                    BoxShadow(
                      color: _C.limeDark.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Retry',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Referral Code Card (synced with dashboard) ──────────────────────────
  Widget _buildReferralCodeCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: _C.heroGradient,
        boxShadow: [
          BoxShadow(
            color: _C.limeDark.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        children: [
          // Title row
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
                child: _ShimmerCodeBox(
                  code: _referralCode ?? '---',
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
    );
  }

  // ─── Stats Cards ────────────────────────────────────────────────────────
  Widget _buildStatsCards() {
    final referrals = _referrals ?? [];
    final total = referrals.length;
    final verified =
        referrals.where((r) => r.status == ReferralStatus.verified).length;
    final pending =
        referrals.where((r) => r.status == ReferralStatus.pending).length;
    final totalEarned = referrals
        .where((r) => r.status == ReferralStatus.verified)
        .fold<double>(0, (sum, r) => sum + r.amount);
    final pendingEarnings = referrals
        .where((r) => r.status == ReferralStatus.pending)
        .fold<double>(0, (sum, r) => sum + r.amount);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _LimeStatCard(
                icon: Icons.people_alt_rounded,
                label: 'Total',
                value: '$total',
                accentColor: _C.limeDarker,
                bgColor: _C.limeBg,
                delay: 0,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _LimeStatCard(
                icon: Icons.check_circle_rounded,
                label: 'Verified',
                value: '$verified',
                accentColor: _C.green,
                bgColor: _C.greenBg,
                delay: 100,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _LimeStatCard(
                icon: Icons.schedule_rounded,
                label: 'Pending',
                value: '$pending',
                accentColor: _C.amber,
                bgColor: _C.amberBg,
                delay: 200,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _LimeStatCard(
                icon: Icons.account_balance_wallet_rounded,
                label: 'Earned',
                value: '₹${totalEarned.toStringAsFixed(0)}',
                accentColor: _C.green,
                bgColor: _C.greenBg,
                delay: 300,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _LimeStatCard(
                icon: Icons.pending_actions_rounded,
                label: 'Pending Earnings',
                value: '₹${pendingEarnings.toStringAsFixed(0)}',
                accentColor: _C.amber,
                bgColor: _C.amberBg,
                delay: 400,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── UPI & WITHDRAW CARD ──────────────────────────────────────────────────
  Widget _buildUpiWithdrawCard() {
    final referrals = _referrals ?? [];
    final earnings = referrals
        .where((r) => r.status == ReferralStatus.verified)
        .fold<double>(0, (sum, item) => sum + item.amount);
    final canWithdraw = earnings >= 500;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _C.cardBg,
        boxShadow: [
          BoxShadow(
            color: _C.limeDarker.withOpacity(0.05),
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
                    color: _C.textDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: canWithdraw ? _C.greenBg : _C.amberBg,
                ),
                child: Text(
                  '₹${earnings.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: canWithdraw ? _C.green : _C.amber,
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
                        const TextStyle(fontSize: 13, color: _C.textLight),
                    prefixIcon: const Icon(Icons.payment_rounded,
                        color: _C.limeDarker, size: 20),
                    filled: true,
                    fillColor: _C.limeBg.withOpacity(0.3),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: _C.limeDarker.withOpacity(0.2)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: _C.limeDarker.withOpacity(0.2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: _C.limeDarker, width: 1.5),
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
                    color: _C.limeDarker,
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
                    color: _C.green, size: 14),
                const SizedBox(width: 4),
                Text(
                  'Saved: $_upiId',
                  style: const TextStyle(
                    color: _C.green,
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

  // ─── Referrals List ─────────────────────────────────────────────────────
  Widget _buildReferralsList() {
    final referrals = _referrals ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: _C.limeBg,
              ),
              child: Icon(Icons.group_rounded, color: _C.limeDarker, size: 18),
            ),
            const SizedBox(width: 10),
            const Text(
              'Your Referrals',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: _C.textDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (referrals.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: _C.limeBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _C.limeSubtle),
            ),
            child: Column(
              children: [
                Icon(Icons.group_add_rounded, size: 48, color: _C.limeDark),
                const SizedBox(height: 12),
                Text(
                  'No referrals yet',
                  style: TextStyle(
                    color: _C.limeDarker,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Share your referral code to start earning!',
                  style: TextStyle(color: _C.textLight, fontSize: 12),
                ),
              ],
            ),
          )
        else
          ...referrals.map((r) => _LimeReferralCard(referral: r)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SHIMMER CODE BOX
// ═══════════════════════════════════════════════════════════════════════════════
class _ShimmerCodeBox extends StatelessWidget {
  const _ShimmerCodeBox({required this.code, required this.controller});
  final String code;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withOpacity(0.14),
            border: Border.all(color: Colors.white.withOpacity(0.22)),
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
//  LIME STAT CARD — with staggered pop animation
// ═══════════════════════════════════════════════════════════════════════════════
class _LimeStatCard extends StatefulWidget {
  const _LimeStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
    required this.bgColor,
    this.delay = 0,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;
  final Color bgColor;
  final int delay;

  @override
  State<_LimeStatCard> createState() => _LimeStatCardState();
}

class _LimeStatCardState extends State<_LimeStatCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _scale = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0, 0.5, curve: Curves.easeOut)),
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
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: _C.cardBg,
          border: Border.all(color: widget.bgColor),
          boxShadow: [
            BoxShadow(
              color: widget.accentColor.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.bgColor,
              ),
              child: Icon(widget.icon, color: widget.accentColor, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              widget.value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: widget.accentColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 11,
                color: _C.textLight,
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
//  LIME REFERRAL CARD — individual referral
// ═══════════════════════════════════════════════════════════════════════════════
class _LimeReferralCard extends StatelessWidget {
  const _LimeReferralCard({required this.referral});
  final Referral referral;

  @override
  Widget build(BuildContext context) {
    final isVerified = referral.status == ReferralStatus.verified;
    final isPending = referral.status == ReferralStatus.pending;

    final Color statusColor =
        isVerified ? _C.green : (isPending ? _C.amber : _C.red);
    final Color statusBg =
        isVerified ? _C.greenBg : (isPending ? _C.amberBg : _C.redBg);
    final IconData statusIcon = isVerified
        ? Icons.verified_rounded
        : (isPending ? Icons.schedule_rounded : Icons.cancel_rounded);

    final bool isDriver = referral.referredType == ReferralType.driver;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _C.cardBg,
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDriver ? _C.limeBg : const Color(0xFFE0F2F1),
            ),
            child: Icon(
              isDriver ? Icons.local_shipping_rounded : Icons.handshake_rounded,
              color: isDriver ? _C.limeDarker : const Color(0xFF00796B),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  referral.referredName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: _C.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${referral.typeLabel} • ${DateFormat('dd MMM yyyy').format(referral.createdAt)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _C.textLight,
                  ),
                ),
              ],
            ),
          ),
          // Amount + Status
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${referral.amount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: isVerified ? _C.green : _C.textLight,
                ),
              ),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: statusBg,
                  border: Border.all(color: statusColor.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      referral.statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
