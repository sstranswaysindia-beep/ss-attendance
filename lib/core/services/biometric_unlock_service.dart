import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricUnlockService {
  static const _prefPrefix = 'biometric_unlock_';
  final LocalAuthentication _auth = LocalAuthentication();

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> isSupported() async {
    if (!_isAndroid) return false;
    final isDeviceSupported = await _auth.isDeviceSupported();
    if (!isDeviceSupported) return false;
    return _auth.canCheckBiometrics;
  }

  Future<bool> authenticate({bool allowDevicePasscode = true}) async {
    if (!_isAndroid) return true;
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock SS Transways India',
        options: AuthenticationOptions(
          biometricOnly: !allowDevicePasscode,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> isEnabledForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefPrefix$userId') ?? false;
  }

  Future<void> setEnabledForUser(String userId, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefPrefix$userId', enabled);
  }
}
