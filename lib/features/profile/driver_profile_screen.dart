import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/profile_repository.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/profile_photo_widget.dart';

// ─── Premium Design Tokens ───
const Color _gradientStart = Color(0xFF0A1628);
const Color _gradientEnd = Color(0xFF1B3A5C);
const Color _gradientMid = Color(0xFF0D4F6B);
const Color _accentTeal = Color(0xFF00BFA6);
const Color _accentGold = Color(0xFFD4A843);
const Color _surfaceBg = Color(0xFFF0F4F8);
const Color _surfaceCard = Color(0xFFF8FAFF);
const Color _heroGreen = Color(0xFF7CFFB2);
const Color _heroRed = Color(0xFFFF7C7C);

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen>
    with TickerProviderStateMixin {
  bool _isUploadingPhoto = false;
  bool _bellHideRequested = false;
  final ProfileRepository _profileRepository = ProfileRepository();
  late AppUser _user;

  late final AnimationController _heroController;
  late final AnimationController _staggerController;
  late final Animation<double> _heroFade;
  late final Animation<double> _heroScale;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    NotificationService().requestBellHide();
    _bellHideRequested = true;

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

    _heroController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _staggerController.forward();
    });
  }

  @override
  void dispose() {
    _heroController.dispose();
    _staggerController.dispose();
    if (_bellHideRequested) {
      NotificationService().releaseBellHide();
      _bellHideRequested = false;
    }
    super.dispose();
  }

  Future<void> _handlePhotoSelected(File file) async {
    await _uploadProfilePhoto(file);
  }

  Future<void> _uploadProfilePhoto(File file) async {
    final driverId = _user.driverId;
    if (driverId == null || driverId.isEmpty) {
      showAppToast(
        context,
        'Driver mapping missing. Contact admin.',
        isError: true,
      );
      return;
    }

    setState(() => _isUploadingPhoto = true);
    try {
      final url = await _profileRepository.uploadProfilePhoto(
        driverId: driverId,
        file: file,
      );
      if (!mounted) return;

      setState(() {
        _user.profilePhoto = url;
      });
      showAppToast(context, 'Profile photo updated.');
    } on ProfileFailure catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to upload profile photo.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plantLabel = _user.plantName ?? _user.plantId ?? 'Not mapped';
    final isCompactMobile = MediaQuery.of(context).size.width <= 500;
    final isHelper = (_user.driverRole?.toLowerCase().trim() ?? '') == 'helper';
    final theme = Theme.of(context);
    final contactNumber = _user.contactNumber?.trim();
    final roleLabel = isHelper ? 'Helper' : 'Driver';
    final vehicleLabel = _user.vehicleNumber ?? 'Not assigned';
    final joiningLabel = _user.joiningDate != null
        ? DateFormat('dd MMM yyyy').format(_user.joiningDate!)
        : 'Not provided';

    String formatDate(String? raw) {
      if (raw == null || raw.trim().isEmpty) {
        return 'Not provided';
      }
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) {
        return raw;
      }
      return '${parsed.day.toString().padLeft(2, '0')} '
          '${_monthLabel(parsed.month)} ${parsed.year}';
    }

    String licenseStatusLabel(String? validityRaw) {
      if (validityRaw == null || validityRaw.trim().isEmpty) {
        return 'Validity not set';
      }
      final parsed = DateTime.tryParse(validityRaw);
      if (parsed == null) {
        return 'Validity not set';
      }
      final today = DateTime.now();
      final normalizedToday = DateTime(today.year, today.month, today.day);
      if (parsed.isBefore(normalizedToday)) {
        return 'Expired';
      }
      return 'Valid';
    }

    final licenseStatus = licenseStatusLabel(_user.dlValidity);
    final licenseExpired = licenseStatus == 'Expired';

    // Define section data for stagger animation
    final sections = <Widget>[
      _buildKeyInfoSection(plantLabel, vehicleLabel),
      _buildContactSection(contactNumber),
      _buildLicenseSection(formatDate, licenseStatus, licenseExpired, theme),
      _buildNomineeSection(),
      _buildBankSection(),
      _buildTipCard(),
    ];

    return Scaffold(
      backgroundColor: _surfaceBg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ─── Gradient SliverAppBar ───
          SliverAppBar(
            pinned: true,
            expandedHeight: isCompactMobile ? 250 : 254,
            backgroundColor: _gradientEnd,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            title: Text(
              '$roleLabel Profile',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                fontSize: 22,
              ),
            ),
            leading: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 20,
                ),
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
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      isCompactMobile ? 18 : 20,
                      isCompactMobile ? 52 : 56,
                      isCompactMobile ? 18 : 20,
                      0,
                    ),
                    child: FadeTransition(
                      opacity: _heroFade,
                      child: ScaleTransition(
                        scale: _heroScale,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ProfileHeroCard(
                              user: _user,
                              roleLabel: roleLabel,
                              joiningLabel: joiningLabel,
                              isUploading: _isUploadingPhoto,
                              onPhotoSelected: _handlePhotoSelected,
                            ),
                            SizedBox(height: isCompactMobile ? 6 : 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _ProfileHeroMetric(
                                    label: 'License Status',
                                    value: licenseStatus,
                                    icon: Icons.verified_user_outlined,
                                    accentColor: licenseExpired
                                        ? _heroRed
                                        : _heroGreen,
                                  ),
                                ),
                                SizedBox(width: isCompactMobile ? 8 : 10),
                                Expanded(
                                  child: _ProfileHeroMetric(
                                    label: 'Aadhaar',
                                    value: _user.aadhaar ?? 'Not provided',
                                    icon: Icons.badge_outlined,
                                    accentColor: _accentGold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // ─── Section Cards with stagger animation ───
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: AnimatedBuilder(
                animation: _staggerController,
                builder: (context, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(sections.length, (index) {
                      final start = (index * 0.12).clamp(0.0, 1.0);
                      final end = (start + 0.4).clamp(0.0, 1.0);
                      final anim = Tween<double>(begin: 0.0, end: 1.0).animate(
                        CurvedAnimation(
                          parent: _staggerController,
                          curve: Interval(
                            start,
                            end,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                      );
                      return Transform.translate(
                        offset: Offset(0, 30 * (1 - anim.value)),
                        child: Opacity(
                          opacity: anim.value,
                          child: Padding(
                            padding: EdgeInsets.only(
                              bottom: index < sections.length - 1 ? 14 : 0,
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

  Widget _buildKeyInfoSection(String plantLabel, String vehicleLabel) {
    return _GlassProfileSection(
      title: 'Key Information',
      subtitle: 'Core identity and work allocation',
      icon: Icons.badge_outlined,
      iconGradient: const [_gradientStart, _accentTeal],
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ProfileHighlightChip(
                  label: 'Employee ID',
                  value: _user.employeeId ?? 'Not assigned',
                  icon: Icons.perm_identity_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProfileHighlightChip(
                  label: 'Plant',
                  value: plantLabel,
                  icon: Icons.factory_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ProfileHighlightChip(
                  label: 'Vehicle',
                  value: vehicleLabel,
                  icon: Icons.local_shipping_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProfileHighlightChip(
                  label: 'Father\'s Name',
                  value: _user.fatherName ?? 'Not provided',
                  icon: Icons.person_outline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContactSection(String? contactNumber) {
    return _GlassProfileSection(
      title: 'Contact & Address',
      subtitle: 'Primary reachability details',
      icon: Icons.contact_phone_outlined,
      iconGradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
      child: Column(
        children: [
          _ProfileInfoRow(
            label: 'Contact Number',
            value: contactNumber?.isNotEmpty == true
                ? contactNumber!
                : 'Not provided',
            icon: Icons.phone_outlined,
          ),
          _ProfileInfoRow(
            label: 'Address',
            value: _user.address ?? 'Not provided',
            icon: Icons.home_outlined,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildLicenseSection(
    String Function(String?) formatDate,
    String licenseStatus,
    bool licenseExpired,
    ThemeData theme,
  ) {
    return _GlassProfileSection(
      title: 'License Details',
      subtitle: 'Driving compliance and validity status',
      icon: Icons.credit_card_outlined,
      iconGradient: const [Color(0xFFF59E0B), Color(0xFFEF4444)],
      child: Column(
        children: [
          _ProfileInfoRow(
            label: 'DL Number',
            value: _user.dlNumber ?? 'Not provided',
            icon: Icons.credit_card_outlined,
          ),
          _ProfileInfoRow(
            label: 'Issue Date',
            value: formatDate(_user.dlIssueDate),
            icon: Icons.event_note_outlined,
          ),
          _ProfileInfoRow(
            label: 'Validity',
            value: formatDate(_user.dlValidity),
            valueColor: licenseExpired
                ? theme.colorScheme.error
                : Colors.green.shade700,
            icon: Icons.calendar_month_outlined,
            trailing: _StatusPill(
              label: licenseStatus,
              color: licenseExpired
                  ? theme.colorScheme.error
                  : Colors.green.shade700,
            ),
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildNomineeSection() {
    return _GlassProfileSection(
      title: 'Nominee Details',
      subtitle: 'Emergency contact and relationship',
      icon: Icons.group_outlined,
      iconGradient: const [Color(0xFF10B981), Color(0xFF059669)],
      child: Column(
        children: [
          _ProfileInfoRow(
            label: 'Nominee Name',
            value: _user.nomineeName ?? 'Not provided',
            icon: Icons.person_outline,
          ),
          _ProfileInfoRow(
            label: 'Relation',
            value: _user.nomineeRelation ?? 'Not provided',
            icon: Icons.family_restroom_outlined,
          ),
          _ProfileInfoRow(
            label: 'Nominee Contact',
            value: _user.nomineeContact ?? 'Not provided',
            icon: Icons.phone_in_talk_outlined,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildBankSection() {
    return _GlassProfileSection(
      title: 'Bank & Compliance',
      subtitle: 'Payroll and verification records',
      icon: Icons.account_balance_outlined,
      iconGradient: const [_gradientStart, _gradientEnd],
      child: Column(
        children: [
          _ProfileInfoRow(
            label: 'ESI Number',
            value: _user.esiNumber ?? 'Not provided',
            icon: Icons.health_and_safety_outlined,
          ),
          _ProfileInfoRow(
            label: 'UAN Number',
            value: _user.uanNumber ?? 'Not provided',
            icon: Icons.work_outline,
          ),
          _ProfileInfoRow(
            label: 'IFSC Code',
            value: _user.ifscCode != null
                ? _user.ifscVerified == true
                      ? '${_user.ifscCode} (Verified)'
                      : '${_user.ifscCode} (Pending verification)'
                : 'Not provided',
            icon: Icons.verified_outlined,
          ),
          _ProfileInfoRow(
            label: 'Bank Account',
            value: _user.bankAccount ?? 'Not provided',
            icon: Icons.account_balance_wallet_outlined,
          ),
          _ProfileInfoRow(
            label: 'Branch Name',
            value: _user.branchName ?? 'Not provided',
            icon: Icons.location_city_outlined,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildTipCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _accentTeal.withOpacity(0.08),
            _accentGold.withOpacity(0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accentTeal.withOpacity(0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_accentTeal, _accentGold],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.camera_alt_outlined,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Photo Update',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF1A2940),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Use the camera icon on your profile photo to upload a fresher picture.',
                  style: TextStyle(
                    color: const Color(0xFF66768B),
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Utility ───

String _monthLabel(int month) {
  const labels = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final index = (month - 1).clamp(0, 11).toInt();
  return labels[index];
}

// ─── Hero Card ───

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({
    required this.user,
    required this.roleLabel,
    this.plantLabel = '',
    this.vehicleLabel = '',
    required this.joiningLabel,
    required this.isUploading,
    required this.onPhotoSelected,
  });

  final AppUser user;
  final String roleLabel;
  final String plantLabel;
  final String vehicleLabel;
  final String joiningLabel;
  final bool isUploading;
  final Future<void> Function(File file) onPhotoSelected;

  @override
  Widget build(BuildContext context) {
    final isCompactMobile = MediaQuery.of(context).size.width <= 500;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isCompactMobile ? 16 : 18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile photo with animated glow ring
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [_accentTeal, _heroGreen, _accentGold],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: _gradientStart,
                  ),
                  child: ProfilePhotoWithUpload(
                    user: user,
                    radius: isCompactMobile ? 26 : 28,
                    onPhotoSelected: onPhotoSelected,
                    isUploading: isUploading,
                  ),
                ),
              ),
              SizedBox(width: isCompactMobile ? 12 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      style: TextStyle(
                        fontSize: isCompactMobile ? 18.5 : 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: isCompactMobile ? 6 : 8),
                    Wrap(
                      spacing: isCompactMobile ? 5 : 6,
                      runSpacing: isCompactMobile ? 5 : 6,
                      children: [
                        _HeroBadge(
                          text: roleLabel,
                          icon: Icons.badge_outlined,
                          gradient: const [_accentTeal, _heroGreen],
                        ),
                        _HeroBadge(
                          text: 'ID ${user.employeeId ?? 'N/A'}',
                          icon: Icons.perm_identity_rounded,
                        ),
                        _HeroBadge(
                          text: 'Joined $joiningLabel',
                          icon: Icons.calendar_month_outlined,
                        ),
                      ],
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

// ─── Hero Badge ───

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.text, required this.icon, this.gradient});

  final String text;
  final IconData icon;
  final List<Color>? gradient;

  @override
  Widget build(BuildContext context) {
    final isCompactMobile = MediaQuery.of(context).size.width <= 500;
    final hasGradient = gradient != null;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompactMobile ? 8 : 9,
        vertical: isCompactMobile ? 3.5 : 4,
      ),
      decoration: BoxDecoration(
        gradient: hasGradient ? LinearGradient(colors: gradient!) : null,
        color: hasGradient ? null : Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: hasGradient
              ? Colors.transparent
              : Colors.white.withOpacity(0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: isCompactMobile ? 11 : 12, color: Colors.white),
          SizedBox(width: isCompactMobile ? 3 : 4),
          Text(
            text,
            style: TextStyle(
              fontSize: isCompactMobile ? 10 : 10.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Hero Metric ───

class _ProfileHeroMetric extends StatelessWidget {
  const _ProfileHeroMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final isCompactMobile = MediaQuery.of(context).size.width <= 500;
    return Container(
      padding: EdgeInsets.all(isCompactMobile ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isCompactMobile ? 7 : 8),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accentColor.withOpacity(0.3)),
            ),
            child: Icon(
              icon,
              size: isCompactMobile ? 15 : 16,
              color: accentColor,
            ),
          ),
          SizedBox(width: isCompactMobile ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: isCompactMobile ? 9.5 : 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.64),
                  ),
                ),
                SizedBox(height: isCompactMobile ? 1 : 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isCompactMobile ? 12 : 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Glass Profile Section Card ───

class _GlassProfileSection extends StatelessWidget {
  const _GlassProfileSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.iconGradient = const [_gradientStart, _accentTeal],
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final List<Color> iconGradient;

  @override
  Widget build(BuildContext context) {
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: iconGradient),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF12243A),
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
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
          child,
        ],
      ),
    );
  }
}

// ─── Profile Info Row ───

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
    this.trailing,
    this.isLast = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;
  final Widget? trailing;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _gradientStart.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 16, color: _gradientEnd),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7C8799),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: valueColor ?? const Color(0xFF202B3C),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ─── Profile Highlight Chip ───

class _ProfileHighlightChip extends StatelessWidget {
  const _ProfileHighlightChip({
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _gradientStart.withOpacity(0.04),
            _accentTeal.withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gradientStart.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: _accentTeal),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7A8797),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Status Pill ───

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
