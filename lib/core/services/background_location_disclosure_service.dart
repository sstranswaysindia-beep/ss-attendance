import 'package:shared_preferences/shared_preferences.dart';

class BackgroundLocationDisclosureService {
  static const int _policyVersion = 1;
  static const String _keyAcceptedVersion =
      'bg_location_disclosure_accepted_version';

  static Future<bool> isAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    final acceptedVersion = prefs.getInt(_keyAcceptedVersion) ?? 0;
    return acceptedVersion >= _policyVersion;
  }

  static Future<void> markAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAcceptedVersion, _policyVersion);
  }
}
