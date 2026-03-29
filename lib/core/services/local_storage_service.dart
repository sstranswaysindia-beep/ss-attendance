import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static final LocalStorageService _instance = LocalStorageService._internal();
  factory LocalStorageService() => _instance;
  LocalStorageService._internal();

  static const String _keyPlantId = 'td_plant';
  static const String _keyVehicleId = 'td_vehicle';
  static const String _keyLogoutTimestamp = 'td_logout_ts';
  static const String _keyTripSheetPlantPrefix = 'ts_trip_sheet_plant_';
  static const String _keyTripSheetVehiclePrefix = 'ts_trip_sheet_vehicle_';

  /// Save plant ID to local storage
  Future<void> savePlantId(String plantId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPlantId, plantId);
  }

  /// Get plant ID from local storage
  Future<String?> getPlantId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPlantId);
  }

  /// Save vehicle ID to local storage
  Future<void> saveVehicleId(String vehicleId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVehicleId, vehicleId);
  }

  /// Get vehicle ID from local storage
  Future<String?> getVehicleId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyVehicleId);
  }

  /// Clear plant and vehicle selections
  Future<void> clearSelections() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPlantId);
    await prefs.remove(_keyVehicleId);
  }

  /// Save logout timestamp
  Future<void> saveLogoutTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyLogoutTimestamp,
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  /// Get logout timestamp
  Future<int?> getLogoutTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getString(_keyLogoutTimestamp);
    return timestamp != null ? int.tryParse(timestamp) : null;
  }

  /// Save Trip Sheet plant ID locally for a user
  Future<void> saveTripSheetPlantId(String userId, String plantId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_keyTripSheetPlantPrefix$userId', plantId);
  }

  /// Get Trip Sheet plant ID locally for a user
  Future<String?> getTripSheetPlantId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_keyTripSheetPlantPrefix$userId');
  }

  /// Save Trip Sheet vehicle ID locally for a user
  Future<void> saveTripSheetVehicleId(String userId, String vehicleId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_keyTripSheetVehiclePrefix$userId', vehicleId);
  }

  /// Get Trip Sheet vehicle ID locally for a user
  Future<String?> getTripSheetVehicleId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_keyTripSheetVehiclePrefix$userId');
  }

  /// Clear Trip Sheet local selections for a user
  Future<void> clearTripSheetSelections(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyTripSheetPlantPrefix$userId');
    await prefs.remove('$_keyTripSheetVehiclePrefix$userId');
  }
}
