import 'package:shared_preferences/shared_preferences.dart';

class AttendanceResumeService {
  static const String _pendingKey = 'pending_attendance_camera_user_id';

  static Future<void> markPendingCameraCapture(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingKey, userId);
  }

  static Future<bool> hasPendingCameraCapture(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingKey) == userId;
  }

  static Future<void> clearPendingCameraCapture() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKey);
  }
}
