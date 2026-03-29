import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/services/notification_service.dart';
import '../../core/services/referral_repository.dart';
import '../../core/widgets/app_toast.dart';

// ─── Colorful Palette ─────────────────────────────────────────────────────────
class _C {
  _C._();
  // Primary lime-green
  static const lime = Color(0xFFD8F999); // ignore: unused_field
  static const limeDark = Color(0xFF8BC34A);
  static const limeDarker = Color(0xFF558B2F);
  static const limeBg = Color(0xFFF2FBDF);
  static const limeSubtle = Color(0xFFEAF7CC);

  // Vivid accents
  static const coral = Color(0xFFFF6B6B);
  static const coralBg = Color(0xFFFFF0F0);
  static const sky = Color(0xFF4ECDC4);
  static const skyBg = Color(0xFFE8FBF9);
  static const purple = Color(0xFF7C4DFF);
  static const purpleBg = Color(0xFFF3EEFF);
  static const amber = Color(0xFFF57F17);
  static const amberBg = Color(0xFFFFF8E1);

  // Surfaces
  static const bg = Colors.white;
  static const cardWhite = Colors.white;

  // Text
  static const textDark = Color(0xFF1B2E0A);
  static const textMedium = Color(0xFF4B5563);
  static const textLight = Color(0xFF9CA3AF);

  // Semantic
  static const green = Color(0xFF2E7D32);
  static const greenBg = Color(0xFFE8F5E9);

  // Gradients
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF558B2F), Color(0xFF8BC34A), Color(0xFFD8F999)],
  );
  static const submitGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF558B2F), Color(0xFF8BC34A)],
  );
}

/// Screen shown after a new referral user registers.
/// They fill in their professional details (name, mobile, Aadhar, DL)
/// and upload document photos before sending for admin verification.
class ReferralProfileScreen extends StatefulWidget {
  const ReferralProfileScreen({
    required this.userId,
    required this.userName,
    this.showBackToLoginOnSuccess = true,
    this.onProfileSubmitted,
    super.key,
  });

  final String userId;
  final String userName;
  final bool showBackToLoginOnSuccess;
  final Future<void> Function()? onProfileSubmitted;

  @override
  State<ReferralProfileScreen> createState() => _ReferralProfileScreenState();
}

class _ReferralProfileScreenState extends State<ReferralProfileScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _aadharCtrl = TextEditingController();
  final _dlCtrl = TextEditingController();

  String _selectedType = 'driver';
  ReferralUploadFile? _aadharPhoto;
  ReferralUploadFile? _dlPhoto;
  bool _isSubmitting = false;
  bool _submitted = false;
  final _repo = ReferralRepository();
  final _picker = ImagePicker();
  bool _bellHideRequested = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    NotificationService().requestBellHide();
    _bellHideRequested = true;

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    if (_bellHideRequested) {
      NotificationService().releaseBellHide();
      _bellHideRequested = false;
    }
    _fadeCtrl.dispose();
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _aadharCtrl.dispose();
    _dlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isAadhar) async {
    if (kIsWeb) {
      await _pickWebImage(isAadhar: isAadhar);
      return;
    }
    final xFile = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 70,
      maxWidth: 1280,
      maxHeight: 1280,
    );
    if (xFile == null) return;
    await _storePickedFile(xFile, isAadhar: isAadhar);
  }

  Future<void> _pickFromGallery(bool isAadhar) async {
    if (kIsWeb) {
      await _pickWebImage(isAadhar: isAadhar);
      return;
    }
    final xFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1280,
      maxHeight: 1280,
    );
    if (xFile == null) return;
    await _storePickedFile(xFile, isAadhar: isAadhar);
  }

  Future<void> _pickWebImage({required bool isAadhar}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        showAppToast(context, 'Selected file is empty', isError: true);
        return;
      }
      final fallback = isAadhar ? 'aadhar.jpg' : 'dl.jpg';
      final uploadFile = ReferralRepository.fromBytes(
        bytes: bytes,
        filename: (picked.name.isNotEmpty ? picked.name : fallback),
      );
      if (uploadFile == null) {
        if (!mounted) return;
        showAppToast(context, 'Selected file is empty', isError: true);
        return;
      }
      if (!mounted) return;
      setState(() {
        if (isAadhar) {
          _aadharPhoto = uploadFile;
        } else {
          _dlPhoto = uploadFile;
        }
      });
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to select file.', isError: true);
    }
  }

  Future<void> _storePickedFile(XFile xFile, {required bool isAadhar}) async {
    try {
      final bytes = await xFile.readAsBytes();
      final fallback = isAadhar ? 'aadhar.jpg' : 'dl.jpg';
      final uploadFile = ReferralRepository.fromBytes(
        bytes: bytes,
        filename: xFile.name.isNotEmpty ? xFile.name : fallback,
      );
      if (uploadFile == null) {
        if (!mounted) return;
        showAppToast(context, 'Selected file is empty', isError: true);
        return;
      }
      if (!mounted) return;
      setState(() {
        if (isAadhar) {
          _aadharPhoto = uploadFile;
        } else {
          _dlPhoto = uploadFile;
        }
      });
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to read file.', isError: true);
    }
  }

  void _showPickOptions(bool isAadhar) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: _C.bg,
          borderRadius: BorderRadius.circular(22),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
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
                const SizedBox(height: 18),
                Text(
                  isAadhar ? 'Upload Aadhar Photo' : 'Upload Driving License',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: _C.textDark,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _PickOptionBtn(
                        icon: Icons.camera_alt_rounded,
                        label: 'Camera',
                        color: _C.sky,
                        bgColor: _C.skyBg,
                        onTap: () {
                          Navigator.pop(ctx);
                          _pickImage(isAadhar);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PickOptionBtn(
                        icon: Icons.photo_library_rounded,
                        label: 'Gallery',
                        color: _C.purple,
                        bgColor: _C.purpleBg,
                        onTap: () {
                          Navigator.pop(ctx);
                          _pickFromGallery(isAadhar);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    final normalizedAadhar = _aadharCtrl.text.replaceAll(' ', '').trim();

    try {
      await _repo.submitProfile(
        userId: widget.userId,
        name: _nameCtrl.text.trim(),
        mobile: _mobileCtrl.text.trim(),
        type: _selectedType,
        aadharNo: normalizedAadhar.isNotEmpty ? normalizedAadhar : null,
        dlNo: _dlCtrl.text.trim().isNotEmpty ? _dlCtrl.text.trim() : null,
        aadharPhoto: _aadharPhoto,
        dlPhoto: _dlPhoto,
      );

      if (!mounted) return;

      setState(() => _submitted = true);
      await widget.onProfileSubmitted?.call();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── Success screen ──
    if (_submitted) {
      return Scaffold(
        backgroundColor: _C.bg,
        body: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: _ColorfulCard(
                  borderColor: _C.greenBg,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Animated check
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: _C.heroGradient,
                          boxShadow: [
                            BoxShadow(
                              color: _C.limeDark.withOpacity(0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 44,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Sent for Verification!',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: _C.limeDarker,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Your profile has been submitted for verification by our admin team. '
                        'Once verified, referral earnings will be credited.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _C.textMedium,
                          height: 1.5,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Earnings info
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _C.amberBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: _C.amber.withOpacity(0.25)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.schedule_rounded,
                                color: _C.amber, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Referral amount: ₹${_selectedType == 'driver' ? '50' : '30'} (Pending)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _C.amber,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      // Action button
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          if (widget.showBackToLoginOnSuccess) {
                            Navigator.of(context)
                                .popUntil((route) => route.isFirst);
                            return;
                          }
                          Navigator.of(context).maybePop();
                        },
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: _C.submitGradient,
                            boxShadow: [
                              BoxShadow(
                                color: _C.limeDark.withOpacity(0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                widget.showBackToLoginOnSuccess
                                    ? Icons.login_rounded
                                    : Icons.dashboard_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.showBackToLoginOnSuccess
                                    ? 'Go to Login'
                                    : 'Go to Dashboard',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // ── Main profile form ──
    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Header ──
                    _buildHeader(),
                    const SizedBox(height: 14),

                    // ── Type Selection ──
                    _buildTypeSection(),
                    const SizedBox(height: 14),

                    // ── Personal Details ──
                    _buildPersonalDetails(),
                    const SizedBox(height: 14),

                    // ── Document Uploads ──
                    _buildDocuments(),
                    const SizedBox(height: 20),

                    // ── Submit Button ──
                    _buildSubmitButton(),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Header Card ─────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: _C.heroGradient,
        boxShadow: [
          BoxShadow(
            color: _C.limeDark.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.20),
            ),
            child: const Icon(
              Icons.badge_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Complete Your Profile',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Welcome ${widget.userName}! Fill in your details below.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.80),
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ─── Type Selection ──────────────────────────────────────────────────────
  Widget _buildTypeSection() {
    return _ColorfulCard(
      borderColor: _C.limeSubtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(
            icon: Icons.person_search_rounded,
            label: 'I am a',
            color: _C.purple,
            bgColor: _C.purpleBg,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TypeChip(
                  label: 'Driver',
                  icon: Icons.local_shipping_rounded,
                  selected: _selectedType == 'driver',
                  color: _C.limeDarker,
                  onTap: () => setState(() => _selectedType = 'driver'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TypeChip(
                  label: 'Helper',
                  icon: Icons.handshake_rounded,
                  selected: _selectedType == 'helper',
                  color: _C.sky,
                  onTap: () => setState(() => _selectedType = 'helper'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Personal Details ────────────────────────────────────────────────────
  Widget _buildPersonalDetails() {
    return _ColorfulCard(
      borderColor: _C.skyBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(
            icon: Icons.person_rounded,
            label: 'Personal Details',
            color: _C.sky,
            bgColor: _C.skyBg,
          ),
          const SizedBox(height: 14),
          _buildInput(
            controller: _nameCtrl,
            label: 'Full Name',
            icon: Icons.person_rounded,
            capitalization: TextCapitalization.words,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Name is required' : null,
          ),
          const SizedBox(height: 12),
          _buildInput(
            controller: _mobileCtrl,
            label: 'Mobile Number',
            icon: Icons.phone_rounded,
            prefix: '+91 ',
            keyboard: TextInputType.phone,
            formatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Mobile number is required';
              }
              if (v.trim().length != 10) {
                return 'Enter valid 10-digit number';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          _buildInput(
            controller: _aadharCtrl,
            label: 'Aadhar Number',
            icon: Icons.credit_card_rounded,
            keyboard: TextInputType.number,
            formatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(12),
              _AadhaarNumberFormatter(),
            ],
            validator: (v) {
              final digits = (v ?? '').replaceAll(' ', '').trim();
              if (digits.isEmpty) return 'Aadhar number is required';
              if (digits.length != 12) return 'Must be exactly 12 digits';
              return null;
            },
          ),
          if (_selectedType == 'driver') ...[
            const SizedBox(height: 12),
            _buildInput(
              controller: _dlCtrl,
              label: 'Driving License Number',
              icon: Icons.drive_eta_rounded,
              capitalization: TextCapitalization.characters,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? prefix,
    TextInputType? keyboard,
    TextCapitalization capitalization = TextCapitalization.none,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      textCapitalization: capitalization,
      keyboardType: keyboard,
      inputFormatters: formatters,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 14, color: _C.textLight),
        prefixIcon: Icon(icon, color: _C.limeDarker, size: 20),
        prefixText: prefix,
        filled: true,
        fillColor: _C.limeBg.withOpacity(0.4),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _C.limeSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _C.limeSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _C.limeDark, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _C.coral),
        ),
      ),
      validator: validator,
    );
  }

  // ─── Documents ───────────────────────────────────────────────────────────
  Widget _buildDocuments() {
    return _ColorfulCard(
      borderColor: _C.coralBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(
            icon: Icons.upload_file_rounded,
            label: 'Upload Documents',
            color: _C.coral,
            bgColor: _C.coralBg,
          ),
          const SizedBox(height: 6),
          const Text(
            'Upload clear photos of your documents',
            style: TextStyle(color: _C.textLight, fontSize: 12),
          ),
          const SizedBox(height: 14),
          _DocumentUploadTile(
            label: 'Aadhar Card',
            icon: Icons.credit_card_rounded,
            file: _aadharPhoto,
            accentColor: _C.sky,
            onTap: () => _showPickOptions(true),
            onClear: () => setState(() => _aadharPhoto = null),
          ),
          if (_selectedType == 'driver') ...[
            const SizedBox(height: 10),
            _DocumentUploadTile(
              label: 'Driving License',
              icon: Icons.drive_eta_rounded,
              file: _dlPhoto,
              accentColor: _C.purple,
              onTap: () => _showPickOptions(false),
              onClear: () => setState(() => _dlPhoto = null),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Submit Button ───────────────────────────────────────────────────────
  Widget _buildSubmitButton() {
    return GestureDetector(
      onTap: _isSubmitting ? null : _handleSubmit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: _isSubmitting ? null : _C.submitGradient,
          color: _isSubmitting ? Colors.grey.shade300 : null,
          boxShadow: _isSubmitting
              ? null
              : [
                  BoxShadow(
                    color: _C.limeDark.withOpacity(0.30),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
        ),
        child: Center(
          child: _isSubmitting
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Send for Verification',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  COLORFUL CARD — white card with colored left border
// ═══════════════════════════════════════════════════════════════════════════════
class _ColorfulCard extends StatelessWidget {
  const _ColorfulCard({required this.child, this.borderColor});
  final Widget child;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _C.cardWhite,
        border: Border.all(color: borderColor ?? const Color(0xFFF0F0F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SECTION LABEL — icon + text header
// ═══════════════════════════════════════════════════════════════════════════════
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
  });
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: bgColor,
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: _C.textDark,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  TYPE CHIP — colorful selection chip
// ═══════════════════════════════════════════════════════════════════════════════
class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.color,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected ? color : _C.limeBg,
          border: Border.all(
            color: selected ? color : _C.limeSubtle,
            width: 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 26,
              color: selected ? Colors.white : _C.textMedium,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: selected ? Colors.white : _C.textMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  AADHAAR FORMATTER
// ═══════════════════════════════════════════════════════════════════════════════
class _AadhaarNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'\D'), '');
    final digits =
        digitsOnly.length > 12 ? digitsOnly.substring(0, 12) : digitsOnly;

    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if ((i == 3 || i == 7) && i != digits.length - 1) {
        buffer.write(' ');
      }
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PICK OPTION BUTTON — for bottom sheet
// ═══════════════════════════════════════════════════════════════════════════════
class _PickOptionBtn extends StatelessWidget {
  const _PickOptionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: bgColor,
          border: Border.all(color: color.withOpacity(0.20)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DOCUMENT UPLOAD TILE — colorful accent
// ═══════════════════════════════════════════════════════════════════════════════
class _DocumentUploadTile extends StatelessWidget {
  const _DocumentUploadTile({
    required this.label,
    required this.icon,
    required this.file,
    required this.onTap,
    required this.onClear,
    required this.accentColor,
  });

  final String label;
  final IconData icon;
  final ReferralUploadFile? file;
  final VoidCallback onTap;
  final VoidCallback onClear;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final bool hasFile = file != null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasFile ? _C.green : accentColor.withOpacity(0.30),
            width: 1.5,
          ),
          color: hasFile ? _C.greenBg : accentColor.withOpacity(0.05),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasFile
                    ? _C.green.withOpacity(0.15)
                    : accentColor.withOpacity(0.12),
              ),
              child: Icon(
                hasFile ? Icons.check_rounded : icon,
                color: hasFile ? _C.green : accentColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _C.textDark,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasFile ? 'Photo uploaded ✓' : 'Tap to upload',
                    style: TextStyle(
                      fontSize: 12,
                      color: hasFile ? _C.green : _C.textLight,
                    ),
                  ),
                ],
              ),
            ),
            if (hasFile)
              GestureDetector(
                onTap: onClear,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _C.coral.withOpacity(0.10),
                  ),
                  child: const Icon(Icons.close, color: _C.coral, size: 16),
                ),
              )
            else
              Icon(
                Icons.cloud_upload_rounded,
                color: accentColor.withOpacity(0.5),
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}
