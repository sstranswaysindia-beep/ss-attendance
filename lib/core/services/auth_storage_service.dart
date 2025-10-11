import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_user.dart';

class AuthStorageService {
  static const String _userKey = 'logged_in_user';
  static const String _isLoggedInKey = 'is_logged_in';

  /// Save user data to local storage
  static Future<void> saveUser(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = jsonEncode(user.toJson());
    await prefs.setString(_userKey, userJson);
    await prefs.setBool(_isLoggedInKey, true);
  }

  /// Get saved user data from local storage
  static Future<AppUser?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool(_isLoggedInKey) ?? false;
    
    if (!isLoggedIn) {
      return null;
    }

    final userJson = prefs.getString(_userKey);
    if (userJson == null) {
      return null;
    }

    try {
      final userMap = jsonDecode(userJson) as Map<String, dynamic>;
      return AppUser.fromJson(userMap);
    } catch (e) {
      // If there's an error parsing the user data, clear it
      await clearUser();
      return null;
    }
  }

  /// Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  /// Clear user data from local storage (logout)
  static Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.setBool(_isLoggedInKey, false);
  }

  /// Update user data (for profile updates, etc.)
  static Future<void> updateUser(AppUser user) async {
    await saveUser(user);
  }
}
