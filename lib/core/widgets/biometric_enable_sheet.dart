import 'package:flutter/material.dart';

import '../services/biometric_unlock_service.dart';

/// A premium bottom-sheet that allows the user to enable or disable
/// biometric (fingerprint / face) unlock for the app.
///
/// Shows the device support status, a toggle, and a fingerprint animation.
/// Returns `true` when the user has biometric enabled upon dismissal.
class BiometricEnableSheet extends StatefulWidget {
  const BiometricEnableSheet({
    super.key,
    required this.userId,
  });

  final String userId;

  /// Convenience helper – shows the sheet and returns whether biometric
  /// was enabled when the user dismissed it.
  static Future<bool> show(BuildContext context, {required String userId}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      transitionAnimationController: AnimationController(
        vsync: Navigator.of(context),
        duration: const Duration(milliseconds: 420),
      ),
      builder: (_) => BiometricEnableSheet(userId: userId),
    );
    return result ?? false;
  }

  @override
  State<BiometricEnableSheet> createState() => _BiometricEnableSheetState();
}

class _BiometricEnableSheetState extends State<BiometricEnableSheet>
    with SingleTickerProviderStateMixin {
  final BiometricUnlockService _service = BiometricUnlockService();
  bool _isEnabled = false;
  bool _isSupported = false;
  bool _isLoading = true;
  bool _isToggling = false;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // Premium color palette
  static const _sheetGradientStart = Color(0xFF0D1B2A); // dark navy
  static const _sheetGradientEnd = Color(0xFF1B2838);
  static const _accentGreen = Color(0xFF00E676);
  static const _accentAmber = Color(0xFFFFAB40);
  static const _cardBg = Color(0xFF1E3348);
  static const _fingerprintGreen = Color(0xFF00E676);
  static const _fingerprintGrey = Color(0xFF78909C);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadStatus();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoading = true);
    try {
      final supported = await _service.isSupported();
      final enabled = await _service.isEnabledForUser(widget.userId);
      if (!mounted) return;
      setState(() {
        _isSupported = supported;
        _isEnabled = enabled;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleToggle(bool value) async {
    if (_isToggling) return;
    if (value && !_isSupported) return;

    setState(() => _isToggling = true);
    try {
      // If enabling, authenticate first for confirmation
      if (value) {
        final authenticated = await _service.authenticate();
        if (!authenticated) {
          if (!mounted) return;
          setState(() => _isToggling = false);
          return;
        }
      }

      await _service.setEnabledForUser(widget.userId, value);
      if (!mounted) return;
      setState(() {
        _isEnabled = value;
        _isToggling = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isToggling = false);
    }
  }

  void _done() {
    Navigator.of(context).pop(_isEnabled);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_sheetGradientStart, _sheetGradientEnd],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.only(bottom: bottomPadding + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.30),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 24),

          // Animated fingerprint icon
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (_isEnabled ? _fingerprintGreen : _fingerprintGrey)
                        .withOpacity(0.18),
                    Colors.transparent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isEnabled ? _fingerprintGreen : _fingerprintGrey)
                        .withOpacity(0.25),
                    blurRadius: 32,
                    spreadRadius: 8,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: Icon(
                Icons.fingerprint_rounded,
                size: 56,
                color: _isEnabled ? _fingerprintGreen : _fingerprintGrey,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Title
          Text(
            _isEnabled ? 'Biometric Unlock Active' : 'Secure Your App',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Text(
              _isSupported
                  ? (_isEnabled
                      ? 'Your app is protected with biometric authentication. Unlock with your fingerprint or face.'
                      : 'Enable biometric unlock to add an extra layer of security. Use your fingerprint or face to unlock.')
                  : 'Biometric authentication is not available on this device.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.white.withOpacity(0.7),
                height: 1.45,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Toggle card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _isEnabled
                      ? _accentGreen.withOpacity(0.25)
                      : Colors.white.withOpacity(0.08),
                ),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (_isEnabled ? _accentGreen : _accentAmber)
                          .withOpacity(0.15),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      _isEnabled
                          ? Icons.lock_open_rounded
                          : Icons.lock_outline_rounded,
                      color: _isEnabled ? _accentGreen : _accentAmber,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isEnabled
                              ? 'Biometric Unlock Enabled'
                              : 'Enable Biometric Unlock',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isSupported
                              ? 'Fingerprint or face recognition'
                              : 'Not supported on this device',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isLoading || _isToggling)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white70,
                      ),
                    )
                  else
                    Switch.adaptive(
                      value: _isEnabled,
                      onChanged: _isSupported ? _handleToggle : null,
                      activeTrackColor: _accentGreen.withOpacity(0.35),
                      thumbColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return _accentGreen;
                        }
                        return Colors.white;
                      }),
                      trackOutlineColor:
                          WidgetStateProperty.all(Colors.transparent),
                      inactiveTrackColor: Colors.white.withOpacity(0.15),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Security features list
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              decoration: BoxDecoration(
                color: _cardBg.withOpacity(0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                children: [
                  _SecurityFeatureRow(
                    icon: Icons.speed_rounded,
                    label: 'Instant unlock',
                    isActive: _isEnabled,
                  ),
                  const SizedBox(height: 10),
                  _SecurityFeatureRow(
                    icon: Icons.shield_rounded,
                    label: 'Prevents unauthorized access',
                    isActive: _isEnabled,
                  ),
                  const SizedBox(height: 10),
                  _SecurityFeatureRow(
                    icon: Icons.privacy_tip_rounded,
                    label: 'Your data stays private',
                    isActive: _isEnabled,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 22),

          // Action button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _isEnabled ? _accentGreen : _accentAmber,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                onPressed: _isSupported && !_isEnabled
                    ? () => _handleToggle(true)
                    : _done,
                icon: Icon(
                  _isEnabled
                      ? Icons.check_circle_rounded
                      : (_isSupported
                          ? Icons.fingerprint_rounded
                          : Icons.close_rounded),
                  size: 20,
                ),
                label: Text(
                  _isEnabled
                      ? 'Done'
                      : (_isSupported ? 'Enable Now' : 'Close'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SecurityFeatureRow extends StatelessWidget {
  const _SecurityFeatureRow({
    required this.icon,
    required this.label,
    required this.isActive,
  });

  final IconData icon;
  final String label;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: isActive
              ? const Color(0xFF00E676)
              : Colors.white.withOpacity(0.4),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isActive
                  ? Colors.white.withOpacity(0.85)
                  : Colors.white.withOpacity(0.4),
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        Icon(
          isActive ? Icons.check_circle_rounded : Icons.circle_outlined,
          size: 17,
          color: isActive
              ? const Color(0xFF00E676)
              : Colors.white.withOpacity(0.25),
        ),
      ],
    );
  }
}
