import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_user.dart';
import '../models/driver_vehicle.dart';
import 'notification_service.dart';

class AuthFailure implements Exception {
  AuthFailure(this.message);

  final String message;

  @override
  String toString() => 'AuthFailure: $message';
}

class AuthAccessStatus {
  const AuthAccessStatus({
    required this.shouldLogout,
    this.message,
    this.driverStatus,
  });

  const AuthAccessStatus.allowed()
    : shouldLogout = false,
      message = null,
      driverStatus = null;

  final bool shouldLogout;
  final String? message;
  final String? driverStatus;
}

class AuthRepository {
  AuthRepository({
    http.Client? client,
    Uri? endpoint,
    Uri? deviceEndpoint,
    Uri? sessionStatusEndpoint,
  }) : _client = client ?? http.Client(),
       _endpoint = endpoint ?? Uri.parse(_defaultEndpoint),
       _deviceEndpoint = deviceEndpoint ?? Uri.parse(_defaultDeviceEndpoint),
       _sessionStatusEndpoint =
           sessionStatusEndpoint ?? Uri.parse(_defaultSessionStatusEndpoint);

  static const String _defaultEndpoint =
      'https://sstranswaysindia.com/api/mobile/mobile_login.php';
  static const String _defaultDeviceEndpoint =
      'https://sstranswaysindia.com/api/mobile/user_device_sync.php';
  static const String _defaultSessionStatusEndpoint =
      'https://sstranswaysindia.com/api/mobile/session_status.php';
  static const String _defaultTrainingReqStatusEndpoint =
      'https://sstranswaysindia.com/api/mobile/training_req_status.php';
  static const String _defaultTrainingReqClearEndpoint =
      'https://sstranswaysindia.com/api/mobile/training_req_clear.php';
  static const String _defaultEmployeeRegStatusEndpoint =
      'https://sstranswaysindia.com/api/mobile/employee_reg_status.php';

  final http.Client _client;
  final Uri _endpoint;
  final Uri _deviceEndpoint;
  final Uri _sessionStatusEndpoint;
  final Uri _trainingReqStatusEndpoint = Uri.parse(
    _defaultTrainingReqStatusEndpoint,
  );
  final Uri _trainingReqClearEndpoint = Uri.parse(
    _defaultTrainingReqClearEndpoint,
  );
  final Uri _employeeRegStatusEndpoint = Uri.parse(
    _defaultEmployeeRegStatusEndpoint,
  );

  static final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();

  Future<AppUser> login({
    required String username,
    required String password,
    String appVariant = 'driver',
  }) async {
    try {
      Map<String, String> devicePayload = {};
      try {
        devicePayload = await _collectDeviceInfo(appVariant: appVariant);
      } catch (_) {
        devicePayload = {};
      }

      final requestBody = <String, dynamic>{
        'username': username,
        'password': password,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      requestBody.addAll(devicePayload);
      if (appVariant.isNotEmpty) {
        requestBody['appVariant'] = appVariant;
      }

      final response = await _client
          .post(
            _endpoint,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 15));

      final statusCode = response.statusCode;
      final body = response.body;

      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        throw AuthFailure(
          'Invalid response from server (status: $statusCode).',
        );
      }

      if (statusCode != 200 || payload['status'] != 'ok') {
        final errorMessage = payload['error']?.toString();
        throw AuthFailure(
          errorMessage ?? 'Login failed (status: $statusCode).',
        );
      }

      final userJson =
          payload['user'] as Map<String, dynamic>? ??
          (throw AuthFailure('Missing user information from server.'));

      // Debug: Print user data from API
      print('AuthRepository: User data from API: $userJson');

      // Send FCM token to server after successful login
      await _sendFCMTokenToServer(userJson['id']?.toString() ?? username);

      final userIdString = userJson['id']?.toString() ?? username;
      final userNameString = userJson['username']?.toString() ?? username;
      if (devicePayload.isNotEmpty) {
        await _postDeviceInfo(
          payload: devicePayload,
          userId: userIdString,
          username: userNameString,
        );
      }

      final role = _parseRole(userJson['role']?.toString());
      final apiUsername = userJson['username']?.toString() ?? username;
      final roleRaw = userJson['role']?.toString() ?? '';
      final referralLikeUser =
          _parseFlag(userJson['is_referral_user']) ||
          userJson['referred_by'] != null ||
          roleRaw.trim().toLowerCase().contains('refer');
      final bool canViewDocuments = _parseFlag(
        userJson['view_document'] ?? userJson['viewDocument'],
      );
      final bool geofencingEnabled = _parseFlag(
        userJson['geofencing_enable'] ?? userJson['geofencingEnabled'],
      );
      final bool proxyEnabled = _parseFlag(
        userJson['proxy_enabled'] ?? userJson['proxyEnabled'],
      );
      final bool trainingRequired = _parseFlag(
        userJson['training_req'] ?? userJson['trainingRequired'],
      );
      final bool advanceEntryAllowed = _parseFlag(
        userJson['advance_entry'] ?? userJson['advanceEntry'],
      );
      final bool employeeRegEnabled = _parseFlag(
        userJson['employee_reg'] ?? userJson['employeeRegEnabled'],
      );

      final driverJson = _asStringMap(payload['driver']);
      final supervisorJson = _asStringMap(payload['supervisor']);

      // Debug: Print flow information
      print('AuthRepository: Role: $role');
      print('AuthRepository: Has driverJson: ${driverJson != null}');
      print('AuthRepository: Has supervisorJson: ${supervisorJson != null}');

      // Handle admin users
      if (role == UserRole.admin && driverJson == null) {
        final displayName =
            userJson['full_name']?.toString() ??
            userJson['username']?.toString() ??
            username;

        return AppUser(
          id: userJson['id']?.toString() ?? username,
          displayName: displayName,
          role: role,
          username: apiUsername,
          canViewDocuments: canViewDocuments,
          geofencingEnabled: geofencingEnabled,
          proxyEnabled: proxyEnabled,
          trainingRequired: trainingRequired,
          advanceEntryAllowed: advanceEntryAllowed,
          employeeRegEnabled: employeeRegEnabled,
        );
      }

      // Handle referral users (no driver mapping expected)
      if (role == UserRole.referral && driverJson == null) {
        final displayName =
            userJson['full_name']?.toString() ??
            userJson['username']?.toString() ??
            username;

        return AppUser(
          id: userJson['id']?.toString() ?? username,
          displayName: displayName,
          role: role,
          username: apiUsername,
          canViewDocuments: canViewDocuments,
          geofencingEnabled: geofencingEnabled,
          proxyEnabled: proxyEnabled,
          trainingRequired: trainingRequired,
          advanceEntryAllowed: advanceEntryAllowed,
          employeeRegEnabled: employeeRegEnabled,
        );
      }

      // Safety fallback for referral-like users when role text is inconsistent.
      if (driverJson == null && referralLikeUser) {
        final displayName =
            userJson['full_name']?.toString() ??
            userJson['username']?.toString() ??
            username;

        return AppUser(
          id: userJson['id']?.toString() ?? username,
          displayName: displayName,
          role: UserRole.referral,
          username: apiUsername,
          canViewDocuments: canViewDocuments,
          geofencingEnabled: geofencingEnabled,
          proxyEnabled: proxyEnabled,
          trainingRequired: trainingRequired,
          advanceEntryAllowed: advanceEntryAllowed,
          employeeRegEnabled: employeeRegEnabled,
        );
      }

      // Handle supervisors without driver_id (fallback case)
      if (role == UserRole.supervisor && driverJson == null) {
        final displayName =
            userJson['full_name']?.toString() ??
            userJson['username']?.toString() ??
            username;

        // Process vehicles for supervisors without driver_id
        final vehiclesJson = _asList(payload['vehicles']);
        print(
          'AuthRepository: Processing vehicles for supervisor without driver_id',
        );
        print('AuthRepository: Vehicles JSON count: ${vehiclesJson.length}');
        final vehicles = vehiclesJson
            .map((item) {
              print('AuthRepository: Vehicle item: $item');
              final vehicleJson = _asStringMap(item);
              if (vehicleJson == null) return null;
              return DriverVehicle.fromJson(vehicleJson);
            })
            .whereType<DriverVehicle>()
            .where((vehicle) {
              final isValid =
                  vehicle.vehicleNumber.isNotEmpty && vehicle.id.isNotEmpty;
              print(
                'AuthRepository: Vehicle ${vehicle.vehicleNumber} (ID: ${vehicle.id}) - Valid: $isValid',
              );
              return isValid;
            })
            .toList(growable: false);
        print(
          'AuthRepository: Final vehicles count for supervisor: ${vehicles.length}',
        );

        // Get plant information for supervisors without driver_id
        final supervisedPlants = _asStringMapList(
          supervisorJson?['supervisedPlants'],
        );
        final supervisedPlantIds = _asList(
          supervisorJson?['supervisedPlantIds'],
        );

        // Set default plant information from first supervised plant
        String? defaultPlantId;
        String? defaultPlantName;
        if (supervisedPlantIds.isNotEmpty && supervisedPlants.isNotEmpty) {
          defaultPlantId = supervisedPlantIds.first.toString();
          defaultPlantName = supervisedPlants.first['plant_name']?.toString();
        }

        return AppUser(
          id: userJson['id']?.toString() ?? username,
          displayName: displayName,
          role: role,
          username: apiUsername,
          // Set plant information for attendance and other features
          plantId: defaultPlantId,
          plantName: defaultPlantName,
          defaultPlantId: defaultPlantId,
          defaultPlantName: defaultPlantName,
          supervisedPlants: supervisedPlants,
          supervisedPlantIds: supervisedPlantIds,
          availableVehicles: vehicles,
          canViewDocuments: canViewDocuments,
          geofencingEnabled: geofencingEnabled,
          proxyEnabled: proxyEnabled,
          trainingRequired: trainingRequired,
          advanceEntryAllowed: advanceEntryAllowed,
          employeeRegEnabled: employeeRegEnabled,
        );
      }

      // Handle drivers or supervisors with driver_id
      if (role != UserRole.admin && driverJson == null) {
        throw AuthFailure('Missing driver mapping from server.');
      }

      final effectiveDriverJson = driverJson ?? <String, dynamic>{};

      final assignmentJson = _asStringMap(effectiveDriverJson['assignment']);

      final defaultPlantId =
          effectiveDriverJson['defaultPlantId']?.toString() ??
          effectiveDriverJson['plantId']?.toString();
      final defaultPlantName = effectiveDriverJson['defaultPlantName']
          ?.toString();
      final assignmentPlantId = assignmentJson?['plantId']?.toString();
      final assignmentPlantName = assignmentJson?['plantName']?.toString();
      final assignmentVehicleId = assignmentJson?['vehicleId']?.toString();
      final assignmentVehicleNumber = assignmentJson?['vehicleNumber']
          ?.toString();
      final assignmentId = assignmentJson?['assignmentId']?.toString();
      final supervisorName = effectiveDriverJson['supervisorName']?.toString();
      final joiningDateRaw = effectiveDriverJson['joiningDate']?.toString();
      DateTime? joiningDate;
      if (joiningDateRaw != null && joiningDateRaw.isNotEmpty) {
        joiningDate = DateTime.tryParse(joiningDateRaw);
      }

      final plantId =
          (assignmentPlantId != null && assignmentPlantId.isNotEmpty)
          ? assignmentPlantId
          : defaultPlantId;
      final plantName =
          (assignmentPlantName != null && assignmentPlantName.isNotEmpty)
          ? assignmentPlantName
          : defaultPlantName;

      final vehicleNumber = assignmentVehicleNumber?.isNotEmpty == true
          ? assignmentVehicleNumber
          : effectiveDriverJson['vehicleNumber']?.toString();

      final vehiclesJson = _asList(payload['vehicles']);
      print(
        'AuthRepository: Processing vehicles for driver/supervisor with driver_id',
      );
      print('AuthRepository: Vehicles JSON count: ${vehiclesJson.length}');
      final vehicles = vehiclesJson
          .map((item) {
            print('AuthRepository: Vehicle item: $item');
            final vehicleJson = _asStringMap(item);
            if (vehicleJson == null) return null;
            return DriverVehicle.fromJson(vehicleJson);
          })
          .whereType<DriverVehicle>()
          .where((vehicle) {
            final isValid =
                vehicle.vehicleNumber.isNotEmpty && vehicle.id.isNotEmpty;
            print(
              'AuthRepository: Vehicle ${vehicle.vehicleNumber} (ID: ${vehicle.id}) - Valid: $isValid',
            );
            return isValid;
          })
          .toList(growable: false);
      print('AuthRepository: Final vehicles count: ${vehicles.length}');

      // For supervisors, prioritize full_name from users table over driver name
      final displayName =
          (role == UserRole.supervisor &&
              userJson['full_name']?.toString().isNotEmpty == true)
          ? userJson['full_name']?.toString() ?? username
          : (effectiveDriverJson['name']?.toString() ?? username);

      String? pickString(Map<String, dynamic> source, List<String> keys) {
        for (final key in keys) {
          final value = source[key];
          if (value == null) continue;
          final trimmed = value.toString().trim();
          if (trimmed.isNotEmpty) {
            return trimmed;
          }
        }
        return null;
      }

      final contactNumber = pickString(effectiveDriverJson, const [
        'contact',
        'contact_number',
        'phone',
      ]);
      final dlNumber = pickString(effectiveDriverJson, const [
        'dlNumber',
        'dl_number',
      ]);
      final dlValidity = pickString(effectiveDriverJson, const [
        'dlValidity',
        'dl_validity',
        'license_expiry_date',
      ]);
      final dlIssueDate = pickString(effectiveDriverJson, const [
        'dlIssueDate',
        'dl_issue_date',
      ]);
      final nomineeName = pickString(effectiveDriverJson, const [
        'nomineeName',
        'nominee_name',
      ]);
      final nomineeRelation = pickString(effectiveDriverJson, const [
        'nomineeRelation',
        'relation_nominee',
      ]);
      final nomineeContact = pickString(effectiveDriverJson, const [
        'nomineeContact',
        'nominee_contact',
      ]);

      return AppUser(
        id: userJson['id']?.toString() ?? username,
        displayName: displayName,
        role: role,
        username: apiUsername,
        employeeId: effectiveDriverJson['employeeId']?.toString(),
        driverId: effectiveDriverJson['driverId']?.toString(),
        plantId: plantId,
        plantName: plantName,
        defaultPlantId: defaultPlantId,
        defaultPlantName: defaultPlantName,
        assignmentId: assignmentId,
        assignmentPlantId: assignmentPlantId,
        assignmentPlantName: assignmentPlantName,
        assignmentVehicleId: assignmentVehicleId,
        assignmentVehicleNumber: assignmentVehicleNumber,
        salary: effectiveDriverJson['salary']?.toString(),
        profilePhoto: effectiveDriverJson['profilePhoto']?.toString(),
        aadhaar: effectiveDriverJson['aadhaar']?.toString(),
        contactNumber: contactNumber,
        esiNumber: effectiveDriverJson['esiNumber']?.toString(),
        uanNumber: effectiveDriverJson['uanNumber']?.toString(),
        ifscCode: effectiveDriverJson['ifsc']?.toString(),
        ifscVerified: effectiveDriverJson['ifscVerified'] == true,
        bankAccount: effectiveDriverJson['bankAccount']?.toString(),
        branchName: effectiveDriverJson['branchName']?.toString(),
        fatherName: effectiveDriverJson['fatherName']?.toString(),
        address: effectiveDriverJson['address']?.toString(),
        dlNumber: dlNumber,
        dlValidity: dlValidity,
        dlIssueDate: dlIssueDate,
        nomineeName: nomineeName,
        nomineeRelation: nomineeRelation,
        nomineeContact: nomineeContact,
        vehicleNumber: vehicleNumber,
        driverRole: effectiveDriverJson['role']?.toString(),
        availableVehicles: vehicles,
        joiningDate: joiningDate,
        supervisorName: supervisorName,
        supervisedPlants: _asStringMapList(supervisorJson?['supervisedPlants']),
        supervisedPlantIds: _asList(supervisorJson?['supervisedPlantIds']),
        canViewDocuments: canViewDocuments,
        geofencingEnabled: geofencingEnabled,
        proxyEnabled: proxyEnabled,
        trainingRequired: trainingRequired,
        advanceEntryAllowed: advanceEntryAllowed,
        employeeRegEnabled: employeeRegEnabled,
      );
    } on AuthFailure {
      rethrow;
    } catch (error, stackTrace) {
      print('AuthRepository: Login parsing failed: $error');
      print(stackTrace);
      throw AuthFailure('Login data error: $error');
    }
  }

  Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return null;
  }

  List<dynamic> _asList(dynamic value) {
    if (value is List) {
      return value;
    }
    return const [];
  }

  List<Map<String, dynamic>> _asStringMapList(dynamic value) {
    return _asList(value)
        .map(_asStringMap)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  UserRole _parseRole(String? raw) {
    final normalized = raw?.trim().toLowerCase() ?? '';
    if (normalized.contains('refer')) {
      return UserRole.referral;
    }
    switch (normalized) {
      case 'admin':
        return UserRole.admin;
      case 'supervisor':
        return UserRole.supervisor;
      case 'driver':
        return UserRole.driver;
      case 'referral':
      case 'referred':
        return UserRole.referral;
      default:
        return UserRole.driver;
    }
  }

  bool _parseFlag(dynamic raw) {
    if (raw == null) {
      return false;
    }
    if (raw is bool) {
      return raw;
    }
    final normalized = raw.toString().trim().toLowerCase();
    return normalized == 'y' ||
        normalized == 'yes' ||
        normalized == '1' ||
        normalized == 'true';
  }

  Future<Map<String, String>> _collectDeviceInfo({
    String appVariant = 'driver',
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();

    String platform = 'unknown';
    String deviceId = '';
    String deviceModel = '';
    String osVersion = '';
    String deviceBrand = '';
    String architecture = '';

    try {
      if (Platform.isAndroid) {
        platform = 'android';
        final info = await _deviceInfoPlugin.androidInfo;
        deviceId = info.id;
        deviceBrand = info.brand ?? '';
        final manufacturer = info.manufacturer ?? '';
        final model = info.model ?? '';
        deviceModel = (manufacturer.isNotEmpty ? '$manufacturer ' : '') + model;
        osVersion = 'Android ${info.version.release ?? ''}'.trim();
        architecture = info.supportedAbis?.join(', ') ?? '';
        if (deviceId.isEmpty) {
          deviceId = info.serialNumber;
        }
      } else if (Platform.isIOS) {
        platform = 'ios';
        final info = await _deviceInfoPlugin.iosInfo;
        deviceId = info.identifierForVendor ?? '';
        deviceModel = info.utsname.machine ?? info.model ?? '';
        osVersion = '${info.systemName ?? 'iOS'} ${info.systemVersion ?? ''}'
            .trim();
      } else if (Platform.isMacOS) {
        platform = 'macos';
        final info = await _deviceInfoPlugin.macOsInfo;
        deviceModel = info.model;
        osVersion = 'macOS ${info.osRelease}'.trim();
        architecture = info.arch;
        deviceId = info.systemGUID ?? '';
      } else if (Platform.isWindows) {
        platform = 'windows';
        final info = await _deviceInfoPlugin.windowsInfo;
        deviceModel = info.computerName ?? '';
        osVersion = info.displayVersion ?? Platform.operatingSystemVersion;
        deviceId = info.deviceId ?? '';
      } else if (Platform.isLinux) {
        platform = 'linux';
        final info = await _deviceInfoPlugin.linuxInfo;
        deviceModel = info.name ?? Platform.operatingSystemVersion;
        osVersion = info.version ?? Platform.operatingSystem;
        deviceId = info.machineId ?? '';
      }
    } catch (_) {
      // Best-effort only; fall back to defaults.
    }

    if (deviceId.isEmpty) {
      deviceId =
          '${platform}_${packageInfo.packageName}_${DateTime.now().millisecondsSinceEpoch}';
    }

    final payload = <String, String>{
      'deviceId': deviceId,
      'devicePlatform': platform,
      'deviceModel': deviceModel,
      'osVersion': osVersion,
      'appVersion': packageInfo.version,
      'appBuild': packageInfo.buildNumber,
      'appIdentifier': packageInfo.packageName,
    };

    if (deviceBrand.isNotEmpty) {
      payload['deviceBrand'] = deviceBrand;
    }
    if (architecture.isNotEmpty) {
      payload['architecture'] = architecture;
    }
    if (appVariant.isNotEmpty) {
      payload['appVariant'] = appVariant;
    }

    return payload;
  }

  Future<void> _postDeviceInfo({
    required Map<String, String> payload,
    required String userId,
    String? username,
  }) async {
    final body = Map<String, String>.from(payload)..['userId'] = userId;
    if (username != null && username.isNotEmpty) {
      body['username'] = username;
    }
    try {
      await _client
          .post(
            _deviceEndpoint,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Ignore errors; device reporting is best-effort.
    }
  }

  Future<void> syncDeviceInfo({
    required AppUser user,
    String appVariant = 'driver',
  }) async {
    try {
      final payload = await _collectDeviceInfo(appVariant: appVariant);
      await _postDeviceInfo(
        payload: payload,
        userId: user.id,
        username: user.displayName,
      );
    } catch (_) {
      // Ignore failures.
    }
  }

  Future<AuthAccessStatus> checkSessionStatus({required AppUser user}) async {
    final body = <String, dynamic>{
      'userId': user.id,
      'username': user.username ?? user.displayName,
      'role': user.role.name,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    final driverId = user.driverId;
    if (driverId != null && driverId.isNotEmpty) {
      body['driverId'] = driverId;
    }

    try {
      final response = await _client
          .post(
            _sessionStatusEndpoint,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final shouldLogout =
          payload['shouldLogout'] == true ||
          payload['isActive'] == false ||
          payload['error'] == 'account_inactive' ||
          payload['error'] == 'driver_not_found' ||
          payload['error'] == 'session_mismatch' ||
          payload['error'] == 'user_not_found';

      if (shouldLogout) {
        return AuthAccessStatus(
          shouldLogout: true,
          message: payload['message']?.toString(),
          driverStatus: payload['driverStatus']?.toString(),
        );
      }

      return const AuthAccessStatus.allowed();
    } catch (_) {
      // Network/server format failures should not force a logout. The login API
      // and the next successful status check still enforce disabled accounts.
      return const AuthAccessStatus.allowed();
    }
  }

  Future<bool?> fetchTrainingRequired({
    required String userId,
    String? username,
  }) async {
    try {
      final response = await _client
          .post(
            _trainingReqStatusEndpoint,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': userId, 'username': username}),
          )
          .timeout(const Duration(seconds: 8));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || payload['status'] != 'ok') {
        throw AuthFailure(
          payload['error']?.toString() ?? 'Unable to check flag',
        );
      }
      final raw = payload['training_req'] ?? payload['trainingRequired'];
      return _parseFlag(raw);
    } catch (_) {
      // Best-effort; do not block app flow if server not reachable.
      return null;
    }
  }

  Future<void> clearTrainingRequired({
    required String userId,
    String? username,
  }) async {
    final response = await _client
        .post(
          _trainingReqClearEndpoint,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'userId': userId, 'username': username}),
        )
        .timeout(const Duration(seconds: 8));
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || payload['status'] != 'ok') {
      throw AuthFailure(payload['error']?.toString() ?? 'Unable to clear flag');
    }
  }

  Future<bool?> fetchEmployeeRegEnabled({
    required String userId,
    String? username,
  }) async {
    try {
      final response = await _client
          .post(
            _employeeRegStatusEndpoint,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': userId, 'username': username}),
          )
          .timeout(const Duration(seconds: 8));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || payload['status'] != 'ok') {
        throw AuthFailure(
          payload['error']?.toString() ?? 'Unable to check flag',
        );
      }
      final raw = payload['employee_reg'] ?? payload['employeeRegEnabled'];
      return _parseFlag(raw);
    } catch (_) {
      return null;
    }
  }

  /// Send FCM token to server for push notifications
  Future<void> _sendFCMTokenToServer(String userId) async {
    try {
      final notificationService = NotificationService();
      final fcmToken = notificationService.fcmToken;

      if (fcmToken != null && fcmToken.isNotEmpty) {
        final response = await _client
            .post(
              Uri.parse(
                'https://sstranswaysindia.com/api/mobile/fcm_token_update.php',
              ),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({
                'userId': userId,
                'fcmToken': fcmToken,
                'platform': 'mobile',
              }),
            )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final payload = jsonDecode(response.body) as Map<String, dynamic>;
          if (payload['status'] == 'ok') {
            print('FCM token sent to server successfully');
          } else {
            print('Failed to send FCM token to server: ${payload['error']}');
          }
        } else {
          print('Failed to send FCM token to server: ${response.statusCode}');
        }
      }
    } catch (e) {
      print('Error sending FCM token to server: $e');
      // Don't throw error as this shouldn't block login
    }
  }
}
