import 'package:flutter/material.dart';
import '../../core/constants/assets.dart';
import '../../core/services/biometric_unlock_service.dart';

class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({required this.service, super.key});

  final BiometricUnlockService service;

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen>
    with SingleTickerProviderStateMixin {
  bool _isBusy = false;
  bool _failed = false;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Small delay so the screen renders first, then OS prompt appears on top
    Future.delayed(const Duration(milliseconds: 400), _attemptUnlock);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _attemptUnlock() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _failed = false;
    });

    final success = await widget.service.authenticate(
      allowDevicePasscode: true,
    );

    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _isBusy = false;
      _failed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF020024),
                Color(0xFF0D0D4A),
                Color(0xFF1A1A6C),
                Color(0xFF5050B5),
              ],
              stops: [0.0, 0.35, 0.65, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),

                // ── Logo + Branding ─────────────────────────────
                ScaleTransition(
                  scale: _pulseAnim,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.08),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.12),
                        width: 1.5,
                      ),
                    ),
                    padding: const EdgeInsets.all(18),
                    child: Image.asset(
                      AppAssets.logo,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.shield_rounded,
                        size: 48,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'SS Transways India',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your Reliable Logistic Partner',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.45),
                    letterSpacing: 0.3,
                  ),
                ),

                const Spacer(flex: 2),

                // ── Lock indicator ──────────────────────────────
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white.withOpacity(0.06),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _failed
                            ? Icons.lock_outline_rounded
                            : Icons.fingerprint_rounded,
                        color: _failed
                            ? Colors.redAccent.shade100
                            : const Color(0xFF00D4FF),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isBusy
                            ? 'Verifying identity...'
                            : _failed
                                ? 'Authentication failed'
                                : 'App is locked',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _failed
                              ? Colors.redAccent.shade100
                              : Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Retry button (only shows after failure) ─────
                if (_failed && !_isBusy)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: FilledButton.icon(
                      onPressed: _attemptUnlock,
                      icon: const Icon(Icons.fingerprint_rounded, size: 20),
                      label: const Text('Unlock with Biometric'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF00D4FF),
                        foregroundColor: const Color(0xFF020024),
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 24,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),

                const Spacer(flex: 1),

                // ── Subtle footer ───────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shield_rounded,
                        size: 14,
                        color: Colors.white.withOpacity(0.2),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Protected with biometric security',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.2),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
