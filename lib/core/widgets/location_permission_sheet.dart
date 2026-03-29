import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// A compact bottom-sheet that requests "Allow all the time" location permission.
///
/// Returns `true` when the permission is [LocationPermission.always].
class LocationPermissionSheet extends StatefulWidget {
  const LocationPermissionSheet({super.key});

  /// Convenience helper – shows the sheet and returns whether the user
  /// ended up with "always" permission.
  static Future<bool> show(BuildContext context) async {
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
      builder: (_) => const LocationPermissionSheet(),
    );
    return result ?? false;
  }

  @override
  State<LocationPermissionSheet> createState() =>
      _LocationPermissionSheetState();
}

class _LocationPermissionSheetState extends State<LocationPermissionSheet>
    with SingleTickerProviderStateMixin {
  bool _isAlways = false;
  bool _checking = true;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  static const _bgStart = Color(0xFF0D1B3E);
  static const _bgEnd = Color(0xFF1A2E5A);
  static const _green = Color(0xFF00E676);
  static const _orange = Color(0xFFFFAB40);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _checkPermission();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    setState(() => _checking = true);
    try {
      final permission = await Geolocator.checkPermission();
      if (!mounted) return;
      setState(() {
        _isAlways = permission == LocationPermission.always;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checking = false);
    }
  }

  Future<void> _handleToggle(bool value) async {
    await _openPermissionSettings();
  }

  /// Opens the app's permission settings page directly (not App Info).
  /// On Android this navigates to Settings → App → Permissions.
  Future<void> _openPermissionSettings() async {
    try {
      await ph.openAppSettings();
      // Wait for user to come back, then re-check
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await _checkPermission();
    } catch (_) {
      // Fallback: try Geolocator's location settings
      try {
        await Geolocator.openLocationSettings();
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await _checkPermission();
      } catch (_) {}
    }
  }

  void _done() {
    Navigator.of(context).pop(_isAlways);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_bgStart, _bgEnd],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
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
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // ── Header row: icon + title ─────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (_isAlways ? _green : _orange).withOpacity(0.15),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      _isAlways
                          ? Icons.location_on_rounded
                          : Icons.location_off_rounded,
                      color: _isAlways ? _green : _orange,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isAlways
                            ? 'GPS Location Active ✓'
                            : 'Required GPS Location',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Required GPS Access',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // ── Toggle card ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.gps_fixed_rounded,
                    color: Colors.white.withOpacity(0.7),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Allow all the time',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (_checking)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    )
                  else
                    Switch.adaptive(
                      value: _isAlways,
                      onChanged: _handleToggle,
                      activeColor: _green,
                      activeTrackColor: _green.withOpacity(0.3),
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor: Colors.white.withOpacity(0.15),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          // ── Action buttons ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _done,
                    child: const Text(
                      'Not now',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _isAlways ? _green : _orange,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isAlways ? _done : _openPermissionSettings,
                    icon: Icon(
                      _isAlways
                          ? Icons.check_circle_rounded
                          : Icons.settings_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _isAlways ? 'Done' : 'Open Permissions',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
