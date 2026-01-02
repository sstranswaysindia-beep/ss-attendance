import 'package:shared_preferences/shared_preferences.dart';

/// Simple helper to persist a front-end override for training requirement.
class TrainingFlagService {
  static const _key = 'training_required_override';

  /// Returns true if override is set to require training.
  static Future<bool> isTrainingRequiredOverride() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  /// Persist override flag (true => require training).
  static Future<void> setTrainingRequiredOverride(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }

  /// Clear override (same as setting false).
  static Future<void> clear() => setTrainingRequiredOverride(false);
}
