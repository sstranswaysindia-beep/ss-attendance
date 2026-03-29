import 'package:shared_preferences/shared_preferences.dart';

class GpsPingThrottle {
  static const String _keyPrefix = 'gps_ping_last_sent_ms_';

  static Future<bool> shouldSend(
    String driverId, {
    Duration minGap = const Duration(minutes: 12),
  }) async {
    if (driverId.isEmpty) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final key = '$_keyPrefix$driverId';
    final lastSentMs = prefs.getInt(key);
    if (lastSentMs == null) {
      return true;
    }

    final elapsedMs = DateTime.now().millisecondsSinceEpoch - lastSentMs;
    return elapsedMs >= minGap.inMilliseconds;
  }

  static Future<void> markSent(String driverId) async {
    if (driverId.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final key = '$_keyPrefix$driverId';
    await prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);
  }
}
