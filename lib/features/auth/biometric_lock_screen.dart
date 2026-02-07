import 'package:flutter/material.dart';
import '../../core/services/biometric_unlock_service.dart';

class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({required this.service, super.key});

  final BiometricUnlockService service;

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _isBusy = false;
  String _message = 'Unlock to continue';

  @override
  void initState() {
    super.initState();
    _attemptUnlock();
  }

  Future<void> _attemptUnlock() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _message = 'Authenticating...';
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
      _message = 'Authentication failed. Try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.fingerprint,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Biometric Unlock',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _message,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isBusy ? null : _attemptUnlock,
                  child: Text(_isBusy ? 'Please wait...' : 'Try Again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
