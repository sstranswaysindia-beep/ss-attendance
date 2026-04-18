import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/assets.dart';
import '../../core/models/app_user.dart';
import '../../core/services/auth_repository.dart';
import '../../core/widgets/app_loader.dart';
import '../../core/widgets/app_toast.dart';
import '../referral/referral_register_screen.dart';

// ── Brand Colors (Light Theme) ───────────────────────────────────────────────
class _BrandColors {
  const _BrandColors._();
  static const navy = Color(0xFF0A1628);
  static const navyMedium = Color(0xFF1E3A6E);
  static const gold = Color(0xFFD4B465);
  static const goldDark = Color(0xFFB8963E);
  static const cardBg = Colors.white;
  static const textPrimary = Color(0xFF0F1C32);
  static const textSecondary = Color(0xFF5A6A85);
  static const textHint = Color(0xFF8B9BB5);
  static const inputBg = Color(0xFFF0F3F9);
  static const inputBorder = Color(0xFFD8DFE9);
  static const inputFocusBorder = Color(0xFF1E3A6E);
  static const divider = Color(0xFFE2E8F0);
}

// ═══════════════════════════════════════════════════════════════════════════════
// LOGIN SCREEN
// ═══════════════════════════════════════════════════════════════════════════════
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.onLogin,
    this.appTitle = 'SS Transways India',
    this.appSubtitle = 'Your Reliable Logistic Partner',
    this.screenTitle = 'Login',
    this.appVariant = 'driver',
    super.key,
  });

  final void Function(AppUser user) onLogin;
  final String appTitle;
  final String appSubtitle;
  final String screenTitle;
  final String appVariant;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  // ── Form ──
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  bool _isLoading = false;
  late final AuthRepository _authRepository;

  // ── Animation controllers ──
  late final AnimationController _logoController;
  late final AnimationController _glowController;
  late final AnimationController _titleController;
  late final AnimationController _cardController;
  late final AnimationController _field1Controller;
  late final AnimationController _field2Controller;
  late final AnimationController _buttonController;
  late final AnimationController _particleController;

  // ── Animations ──
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _glowPulse;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _cardSlide;
  late final Animation<double> _cardFade;
  late final Animation<double> _field1Fade;
  late final Animation<Offset> _field1Slide;
  late final Animation<double> _field2Fade;
  late final Animation<Offset> _field2Slide;
  late final Animation<double> _buttonScale;
  late final Animation<double> _buttonFade;

  @override
  void initState() {
    super.initState();
    _authRepository = AuthRepository();
    _setupAnimations();
    _startAnimationSequence();
  }

  void _setupAnimations() {
    // Logo entrance (scale + fade with elastic ease)
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _logoScale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    // Logo glow pulse (repeating)
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _glowPulse = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // Title slide-up
    _titleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _titleController, curve: Curves.easeOutCubic),
        );
    _titleFade = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _titleController, curve: Curves.easeOut));

    // Card slide-up
    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _cardSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _cardController, curve: Curves.easeOutCubic),
        );
    _cardFade = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _cardController, curve: Curves.easeOut));

    // Field 1 (username)
    _field1Controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _field1Fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _field1Controller, curve: Curves.easeOut),
    );
    _field1Slide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _field1Controller,
            curve: Curves.easeOutCubic,
          ),
        );

    // Field 2 (password)
    _field2Controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _field2Fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _field2Controller, curve: Curves.easeOut),
    );
    _field2Slide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _field2Controller,
            curve: Curves.easeOutCubic,
          ),
        );

    // Button entrance
    _buttonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _buttonScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _buttonController, curve: Curves.elasticOut),
    );
    _buttonFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _buttonController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    // Background particles
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25),
    );
  }

  void _startAnimationSequence() {
    _particleController.repeat();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _logoController.forward();
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _glowController.repeat(reverse: true);
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _titleController.forward();
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _cardController.forward();
    });
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _field1Controller.forward();
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) _field2Controller.forward();
    });
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) _buttonController.forward();
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _logoController.dispose();
    _glowController.dispose();
    _titleController.dispose();
    _cardController.dispose();
    _field1Controller.dispose();
    _field2Controller.dispose();
    _buttonController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    print('LoginScreen: sign in tapped');
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final username = _usernameController.text.trim().toLowerCase();

    try {
      final user = await _authRepository.login(
        username: username,
        password: _passwordController.text,
        appVariant: widget.appVariant,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);
      print('LoginScreen: login parsed successfully, handing off to app');
      widget.onLogin(user);
    } on AuthFailure catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showAppToast(context, error.message, isError: true);
    } catch (error, stackTrace) {
      print('LoginScreen: unexpected login error: $error');
      print(stackTrace);
      if (!mounted) return;
      setState(() => _isLoading = false);
      showAppToast(
        context,
        'Unable to login. Please try again later.',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFFE8EDF6),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: Stack(
          children: [
            // ── Light gradient background ──
            const _LightGradientBackground(),

            // ── Floating particles ──
            AnimatedBuilder(
              animation: _particleController,
              builder: (context, _) => CustomPaint(
                size: MediaQuery.sizeOf(context),
                painter: _ParticlePainter(progress: _particleController.value),
              ),
            ),

            // ── Main content ──
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 360,
                    ), // Reduced from 420
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildLogoSection(),
                        const SizedBox(height: 16),
                        _buildFormCard(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Logo + Title Section ──────────────────────────────────────────────────
  Widget _buildLogoSection() {
    return Column(
      children: [
        // Logo with glow
        AnimatedBuilder(
          animation: Listenable.merge([_logoController, _glowController]),
          builder: (context, child) {
            return FadeTransition(
              opacity: _logoFade,
              child: ScaleTransition(
                scale: _logoScale,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Subtle glow behind logo
                    Container(
                      width: 78,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.rectangle,
                        borderRadius: BorderRadius.circular(35),
                        boxShadow: [
                          BoxShadow(
                            color: _BrandColors.navy.withValues(
                              alpha: 0.06 * _glowPulse.value,
                            ),
                            blurRadius: 40 * _glowPulse.value,
                            spreadRadius: 10 * _glowPulse.value,
                          ),
                          BoxShadow(
                            color: _BrandColors.gold.withValues(
                              alpha: 0.10 * _glowPulse.value,
                            ),
                            blurRadius: 55 * _glowPulse.value,
                            spreadRadius: 18 * _glowPulse.value,
                          ),
                        ],
                      ),
                    ),
                    // Logo image (transparent PNG, no container)
                    SizedBox(
                      width: 68,
                      // height removed so it hugs the image aspect ratio
                      child: Image.asset(
                        AppAssets.logoNew,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.local_shipping_rounded,
                          size: 40,
                          color: _BrandColors.navy.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 0), // Reduced gap between logo and company name
        SlideTransition(
          position: _titleSlide,
          child: FadeTransition(
            opacity: _titleFade,
            child: Column(
              children: [
                Text(
                  widget.appTitle,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF153753), // Specific color requested
                    letterSpacing: 0.1,
                  ),
                ),
                if (widget.appSubtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: _BrandColors.navy.withValues(alpha: 0.06),
                    ),
                    child: Text(
                      widget.appSubtitle,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: _BrandColors.goldDark,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Form Card ─────────────────────────────────────────────────────────────
  Widget _buildFormCard(BuildContext context) {
    return SlideTransition(
      position: _cardSlide,
      child: FadeTransition(
        opacity: _cardFade,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: _BrandColors.cardBg,
            border: Border.all(
              color: _BrandColors.divider.withValues(alpha: 0.6),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _BrandColors.navy.withValues(alpha: 0.06),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: _BrandColors.navy.withValues(alpha: 0.03),
                blurRadius: 60,
                offset: const Offset(0, 24),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Section title
                Text(
                  widget.screenTitle,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _BrandColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sign in to continue',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: _BrandColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),

                // ── Username field ──
                SlideTransition(
                  position: _field1Slide,
                  child: FadeTransition(
                    opacity: _field1Fade,
                    child: _buildTextField(
                      controller: _usernameController,
                      label: 'Username or Email',
                      icon: Icons.person_outline_rounded,
                      inputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                        _LowercaseFormatter(),
                      ],
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a username or email';
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Password field ──
                SlideTransition(
                  position: _field2Slide,
                  child: FadeTransition(
                    opacity: _field2Fade,
                    child: _buildTextField(
                      controller: _passwordController,
                      label: 'Password',
                      icon: Icons.lock_outline_rounded,
                      isPassword: true,
                      inputAction: TextInputAction.done,
                      onSubmitted: _isLoading ? null : _handleLogin,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Enter password';
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // ── Forgot Password ──
                FadeTransition(
                  opacity: _field2Fade,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        showAppToast(
                          context,
                          'Redirect to password reset flow',
                        );
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: _BrandColors.navyMedium,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                      ),
                      child: Text(
                        'Forgot Password?',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // ── Login Button ──
                FadeTransition(
                  opacity: _buttonFade,
                  child: ScaleTransition(
                    scale: _buttonScale,
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF153753),
                          disabledBackgroundColor: _BrandColors.inputBg,
                          foregroundColor: Colors.white,
                          elevation: _isLoading ? 0 : 8,
                          shadowColor: _BrandColors.navy.withValues(
                            alpha: 0.25,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: AppLoader(size: 22),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Sign In',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Divider ──
                FadeTransition(
                  opacity: _buttonFade,
                  child: Row(
                    children: [
                      const Expanded(
                        child: Divider(color: _BrandColors.divider),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          'OR',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _BrandColors.textHint,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const Expanded(
                        child: Divider(color: _BrandColors.divider),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Join Now ──
                FadeTransition(
                  opacity: _buttonFade,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ReferralRegisterScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: Text(
                      'Not Registered? Join Now',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: BorderSide(
                        color: _BrandColors.navy.withValues(alpha: 0.2),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      foregroundColor: _BrandColors.navyMedium,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Themed TextField ──────────────────────────────────────────────────────
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputAction? inputAction,
    VoidCallback? onSubmitted,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword && !_showPassword,
      textInputAction: inputAction,
      onFieldSubmitted: (_) => onSubmitted?.call(),
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.none,
      inputFormatters: inputFormatters,
      style: GoogleFonts.poppins(
        color: _BrandColors.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      cursorColor: _BrandColors.navyMedium,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(
          color: _BrandColors.textHint,
          fontSize: 13.5,
          fontWeight: FontWeight.w400,
        ),
        floatingLabelStyle: GoogleFonts.poppins(
          color: _BrandColors.navyMedium,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(icon, color: _BrandColors.textSecondary, size: 20),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: _BrandColors.textSecondary,
                  size: 20,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              )
            : null,
        filled: true,
        fillColor: _BrandColors.inputBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _BrandColors.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _BrandColors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: _BrandColors.inputFocusBorder,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade400),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
        ),
        errorStyle: GoogleFonts.poppins(
          fontSize: 11,
          color: Colors.red.shade600,
        ),
      ),
      validator: validator,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ANIMATED BACKGROUND WITH FLOATING GRADIENT BLOBS
// ═══════════════════════════════════════════════════════════════════════════════
class _LightGradientBackground extends StatelessWidget {
  const _LightGradientBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF0F4FB),
            Color(0xFFE8EDF6),
            Color(0xFFF5F0EB),
            Color(0xFFEBEFF8),
          ],
          stops: [0.0, 0.4, 0.7, 1.0],
        ),
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.progress});

  final double progress;

  static final List<_Blob> _blobs = [
    _Blob(
      baseX: 0.15,
      baseY: 0.12,
      radius: 120,
      color1: Color(0xFF1E3A6E),
      color2: Color(0xFF00B4D8),
      speedX: 0.8,
      speedY: 0.6,
      driftRange: 0.08,
      opacity: 0.07,
    ),
    _Blob(
      baseX: 0.85,
      baseY: 0.25,
      radius: 100,
      color1: Color(0xFFD4B465),
      color2: Color(0xFFE8D5A0),
      speedX: 0.6,
      speedY: 0.9,
      driftRange: 0.06,
      opacity: 0.08,
    ),
    _Blob(
      baseX: 0.5,
      baseY: 0.55,
      radius: 150,
      color1: Color(0xFF6366F1),
      color2: Color(0xFF818CF8),
      speedX: 0.4,
      speedY: 0.5,
      driftRange: 0.10,
      opacity: 0.05,
    ),
    _Blob(
      baseX: 0.2,
      baseY: 0.82,
      radius: 90,
      color1: Color(0xFF00B4D8),
      color2: Color(0xFF38BDF8),
      speedX: 0.7,
      speedY: 0.4,
      driftRange: 0.07,
      opacity: 0.06,
    ),
    _Blob(
      baseX: 0.78,
      baseY: 0.75,
      radius: 110,
      color1: Color(0xFFD4B465),
      color2: Color(0xFF1E3A6E),
      speedX: 0.5,
      speedY: 0.7,
      driftRange: 0.09,
      opacity: 0.06,
    ),
  ];

  // Small sparkle dots
  static final List<_Particle> _sparkles = List.generate(18, (i) {
    final rng = math.Random(i * 37);
    return _Particle(
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      size: 1.5 + rng.nextDouble() * 2.5,
      speed: 0.12 + rng.nextDouble() * 0.4,
      opacity: 0.06 + rng.nextDouble() * 0.12,
      isGold: rng.nextDouble() > 0.5,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw floating blobs
    for (final blob in _blobs) {
      final dx =
          blob.baseX * size.width +
          math.sin(progress * blob.speedX * math.pi * 2) *
              blob.driftRange *
              size.width;
      final dy =
          blob.baseY * size.height +
          math.cos(progress * blob.speedY * math.pi * 2) *
              blob.driftRange *
              size.height;

      final gradient = RadialGradient(
        colors: [
          blob.color1.withValues(alpha: blob.opacity),
          blob.color2.withValues(alpha: blob.opacity * 0.4),
          blob.color1.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.5, 1.0],
      );

      final rect = Rect.fromCircle(center: Offset(dx, dy), radius: blob.radius);

      final paint = Paint()..shader = gradient.createShader(rect);
      canvas.drawCircle(Offset(dx, dy), blob.radius, paint);
    }

    // Draw small sparkle particles
    for (final p in _sparkles) {
      final yOffset = (p.y + progress * p.speed) % 1.0;
      final xDrift =
          math.sin((progress * p.speed * 2 + p.x) * math.pi * 2) * 0.025;
      final px = (p.x + xDrift) * size.width;
      final py = yOffset * size.height;

      final paint = Paint()
        ..color = p.isGold
            ? _BrandColors.gold.withValues(alpha: p.opacity)
            : _BrandColors.navyMedium.withValues(alpha: p.opacity * 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

      canvas.drawCircle(Offset(px, py), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}

class _Blob {
  const _Blob({
    required this.baseX,
    required this.baseY,
    required this.radius,
    required this.color1,
    required this.color2,
    required this.speedX,
    required this.speedY,
    required this.driftRange,
    required this.opacity,
  });

  final double baseX;
  final double baseY;
  final double radius;
  final Color color1;
  final Color color2;
  final double speedX;
  final double speedY;
  final double driftRange;
  final double opacity;
}

class _Particle {
  const _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.opacity,
    required this.isGold,
  });

  final double x;
  final double y;
  final double size;
  final double speed;
  final double opacity;
  final bool isGold;
}

/// Input formatter that forces all text to lowercase.
class _LowercaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toLowerCase());
  }
}
